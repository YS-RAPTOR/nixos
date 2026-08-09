import json
import subprocess
from collections.abc import Sequence
from pathlib import Path

import pytest

from agent_desktop.models import Config
from agent_desktop.session import SessionRuntime
from agent_desktop.system import SessionManager
from agent_desktop.viewer import ViewerClient, ViewerServer


class RecordingRunner:
    def __init__(self) -> None:
        self.calls: list[list[str]] = []

    def run(
        self,
        arguments: Sequence[str],
        *,
        check: bool = True,
        timeout: float = 30,
    ) -> subprocess.CompletedProcess[str]:
        del check, timeout
        values = list(arguments)
        self.calls.append(values)
        return subprocess.CompletedProcess(values, 0, "", "")


class BrowserOverlayProbe(SessionRuntime):
    def __init__(self, config: Config) -> None:
        super().__init__(config, "browser-session", "browser-agent")
        self.spawned: list[str] = []

    def _spawn(
        self, name: str, arguments: list[str], environment: dict[str, str]
    ) -> None:
        del name, environment
        self.spawned = arguments

    def _wait_until(self, predicate, label: str) -> None:
        del predicate, label
        (self.layout.browser_profile / ".agent-desktop-ready").touch()


class WayVNCProbe(SessionRuntime):
    def __init__(self, config: Config) -> None:
        super().__init__(config, "viewer-session", "viewer-agent")
        self.spawned: list[str] = []

    def _spawn(
        self, name: str, arguments: list[str], environment: dict[str, str]
    ) -> None:
        del name, environment
        self.spawned = arguments

    def _wait_for_path(self, path: Path, label: str) -> None:
        del path, label


def make_config(tmp_path: Path) -> Config:
    novnc = tmp_path / "novnc"
    golden = tmp_path / "golden"
    (novnc / "core").mkdir(parents=True)
    golden.mkdir()
    (novnc / "core" / "rfb.js").write_text("export default class RFB {}")
    (golden / ".agent-desktop-ready").touch()
    return Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        browser_overlay_root=tmp_path / "browser-overlays",
        vivaldi_golden_profile=golden,
        portal_service_dir=tmp_path / "services",
        novnc_web_root=novnc,
    )


def test_browser_overlay_uses_golden_lower_and_private_writable_layers(
    tmp_path: Path,
) -> None:
    config = make_config(tmp_path)
    runtime = BrowserOverlayProbe(config)
    runtime.layout.prepare()
    preferences = runtime.layout.browser_profile / "Default" / "Preferences"
    preferences.parent.mkdir()
    preferences.write_text(
        '{"profile":{"exit_type":"CrashedOnlyOnce"},'
        '"vivaldi":{"startup":{"crash_detection_last_seen_version":"8.1"}}}'
    )
    crash_reports = runtime.layout.browser_profile / "Crash Reports"
    crash_reports.mkdir()
    (crash_reports / "pending.dmp").touch()

    runtime._start_browser_profile({})

    options = runtime.spawned[runtime.spawned.index("-o") + 1]
    assert runtime.spawned[:2] == [config.commands.fuse_overlayfs, "-f"]
    assert f"lowerdir={config.vivaldi_golden_profile}" in options
    assert f"upperdir={runtime.layout.browser_upper}" in options
    assert f"workdir={runtime.layout.browser_work}" in options
    assert runtime.spawned[-1] == str(runtime.layout.browser_profile)
    document = json.loads(preferences.read_text())
    assert document["profile"]["exit_type"] == "Normal"
    assert "crash_detection_last_seen_version" not in document["vivaldi"]["startup"]
    assert not crash_reports.exists()
    assert preferences.stat().st_mode & 0o777 == 0o600


def test_wayvnc_uses_private_websocket_and_persistent_seat(tmp_path: Path) -> None:
    config = make_config(tmp_path)
    runtime = WayVNCProbe(config)

    runtime._start_wayvnc({})

    assert "--seat=seat0" in runtime.spawned
    assert f"--output={config.output_name}" in runtime.spawned
    assert f"ws-unix:{runtime.layout.vnc_socket}" in runtime.spawned
    assert "--transient-seat" not in runtime.spawned


def test_viewer_url_starts_shared_service_and_keeps_token_in_fragment(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    config = make_config(tmp_path)
    config.viewer_runtime_dir.mkdir()
    config.viewer_token_path.write_text("private-token")
    runner = RecordingRunner()
    viewer = ViewerClient(config, runner=runner)
    monkeypatch.setattr(ViewerClient, "_wait_ready", lambda self: None)

    url = viewer.url("viewer-session")

    assert runner.calls == [
        [config.commands.systemctl, "--user", "start", config.viewer_unit]
    ]
    assert url == (
        f"http://127.0.0.1:{config.viewer_port}/"
        "#token=private-token&session=viewer-session"
    )
    assert "private-token" not in url.split("#", 1)[0]


def test_viewer_server_creates_private_token(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    config = make_config(tmp_path)
    config_path = tmp_path / "config.json"
    manager = SessionManager(
        config, config_path, session_command="/nix/store/agent-desktop-session"
    )
    server = ViewerServer(config, config_path, manager)

    server.prepare()

    assert config.viewer_token_path.read_text() == server.token
    assert config.viewer_token_path.stat().st_mode & 0o777 == 0o600
