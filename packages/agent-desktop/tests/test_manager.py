from __future__ import annotations

import json
import os
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest

PACKAGE = Path(__file__).parents[1]
HOST = r"""import html, json, os, re, shutil, signal, socket, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
units = Path(os.environ.get("FAKE_SYSTEMD", "/tmp/agent-desktop-fake-units"))
units.mkdir(parents=True, exist_ok=True)
held = []
def endpoint(path):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True); path.unlink(missing_ok=True)
    value = socket.socket(socket.AF_UNIX); value.bind(str(path)); value.listen(); held.append(value)
def stay(): signal.pause()
if name == "agent-desktop-cleanup":
    config = json.loads(Path(args[args.index("--config") + 1]).read_text())
    sid = args[args.index("--session-id") + 1]
    root = Path(config.get("runtime_root", Path(os.environ["XDG_RUNTIME_DIR"]) / "agent-desktop")) / sid
    (root / "browser-profile/.fake-overlay").unlink(missing_ok=True)
    shutil.rmtree(Path(config["state_root"]) / "browser-overlays" / sid, ignore_errors=True)
elif name == "systemd-run":
    unit = next(value.split("=", 1)[1] for value in args if value.startswith("--unit="))
    if unit.startswith("agent-desktop-cleanup-"):
        raise SystemExit(0)
    sid = args[args.index("--session-id") + 1]
    config = json.loads(Path(args[args.index("--config") + 1]).read_text())
    path = Path(config["state_root"]) / "sessions" / f"{sid}.json"
    state = json.loads(path.read_text())
    root = Path(state["runtime_dir"])
    root.mkdir(parents=True, exist_ok=True)
    with socket.socket(socket.AF_UNIX) as endpoint:
        endpoint.bind(str(root / "wayvnc.sock"))
    state.update({
        "state": "ready", "updated_at": state["created_at"] + 1,
        "ready_at": state["created_at"] + 1, "wayland_display": "wayland-1",
        "sway_socket": str(root / "sway-ipc.1000.1.sock"),
        "dbus_address": f"unix:path={root / 'bus'}",
        "at_spi_bus_address": f"unix:path={root / 'at-spi/bus_0'},guid=fake",
        "cua_socket": str(root / "cua.sock"), "vnc_socket": str(root / "wayvnc.sock"),
        "control_socket": str(root / "control.sock"),
        "browser_profile": str(root / "browser-profile"),
    })
    path.write_text(json.dumps(state))
    (units / unit).touch()
elif name == "systemctl":
    action = next(value for value in args if value in {"show", "start", "stop"})
    unit = args[args.index(action) + 1]
    marker = units / unit
    if action == "show":
        print("LoadState=loaded\nActiveState=active" if marker.exists() else
              "LoadState=not-found\nActiveState=inactive")
    elif action == "stop":
        marker.unlink(missing_ok=True)
elif name == "xdg-open":
    (units / "opened-url").write_text(args[-1])
elif name == "fusermount3":
    marker = Path(args[-1]) / ".fake-overlay"
    if marker.exists(): marker.unlink()
elif name == "fuse-overlayfs":
    options = args[args.index("-o") + 1]
    lower = Path(next(value.split("=", 1)[1] for value in options.split(",") if value.startswith("lowerdir=")))
    mount = Path(args[-1]); shutil.copytree(lower, mount, dirs_exist_ok=True, symlinks=True)
    (mount / ".fake-overlay").touch(); stay()
elif name == "dbus-daemon":
    config = Path(next(value.split("=", 1)[1] for value in args if value.startswith("--config-file=")))
    endpoint(html.unescape(re.search(r"<listen>unix:path=([^<]+)</listen>", config.read_text()).group(1))); stay()
elif name == "at-spi-bus-launcher":
    endpoint(Path(os.environ["XDG_RUNTIME_DIR"]) / "at-spi/bus_0"); stay()
elif name == "sway":
    endpoint(Path(os.environ["XDG_RUNTIME_DIR"]) / "wayland-1")
    endpoint(Path(os.environ["XDG_RUNTIME_DIR"]) / "sway-ipc.1000.1.sock"); stay()
elif name == "wayvnc":
    endpoint(args[args.index("--socket") + 1]); endpoint(args[-1].removeprefix("ws-unix:")); stay()
elif name == "pipewire":
    endpoint(Path(os.environ["XDG_RUNTIME_DIR"]) / "pipewire-0"); stay()
elif name == "cua-driver":
    if args[0] == "serve": endpoint(args[args.index("--socket") + 1]); stay()
    elif not Path(args[args.index("--socket") + 1]).exists(): raise SystemExit(1)
elif name == "busctl":
    if "list" in args:
        for index, owner in enumerate(("org.freedesktop.secrets", "org.a11y.Bus", "org.a11y.atspi.Registry", "org.freedesktop.impl.portal.desktop.gtk", "org.freedesktop.impl.portal.desktop.wlr", "org.freedesktop.portal.Desktop"), 100): print(owner, index)
    elif "call" in args: print('s "unix:path=' + str(Path(os.environ["XDG_RUNTIME_DIR"]) / "at-spi/bus_0") + ',guid=fake"')
    elif "get-property" in args: print("b true" if args[-1] in {"IsEnabled", "ScreenReaderEnabled"} else "u 4")
elif name == "pw-dump": print("WirePlumber")
elif name == "swaymsg": print("[]")
elif name in {"agent-desktop-secret-bridge", "at-spi2-registryd", "wireplumber", "xdg-desktop-portal-wlr", "xdg-desktop-portal-gtk", "xdg-desktop-portal", "vivaldi"}: stay()
"""


@dataclass
class World:
    root: Path
    config: Path
    environment: dict[str, str]
    viewer_port: int

    def cli(self, *arguments: str, succeeds: bool = True) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "agent_desktop.cli",
                "--config",
                str(self.config),
                *arguments,
            ],
            cwd=PACKAGE,
            env=self.environment,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        assert (result.returncode == 0) is succeeds, result.stderr
        return result

    def create(self, session_id: str, agent_id: str = "agent") -> dict[str, Any]:
        result = self.cli("create", agent_id, "--session-id", session_id, "--json")
        return json.loads(result.stdout)

    @property
    def units(self) -> Path:
        return Path(self.environment["FAKE_SYSTEMD"])


@pytest.fixture
def world(tmp_path: Path) -> Iterator[World]:
    binary = tmp_path / "bin"
    binary.mkdir()
    host = binary / "host"
    host.write_text(f"#!{sys.executable}\n{HOST}")
    host.chmod(host.stat().st_mode | stat.S_IXUSR)
    commands = "systemd-run systemctl xdg-open fuse-overlayfs fusermount3 dbus-daemon sway swaymsg at-spi-bus-launcher at-spi2-registryd pipewire pw-dump wireplumber xdg-desktop-portal-wlr xdg-desktop-portal-gtk xdg-desktop-portal busctl cua-driver wayvnc vivaldi agent-desktop-secret-bridge agent-desktop-cleanup"
    for name in commands.split():
        (binary / name).symlink_to(host)
    runtime_base = Path(tempfile.mkdtemp(prefix="agent-desktop-test-"))
    runtime = runtime_base / "agent-desktop"
    state = tmp_path / "state"
    golden = state / "browser-golden/vivaldi"
    novnc = tmp_path / "novnc/core"
    golden.mkdir(parents=True)
    novnc.mkdir(parents=True)
    (golden / ".agent-desktop-ready").touch()
    (novnc / "rfb.js").write_text("export default class RFB {}")
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        viewer_port = listener.getsockname()[1]
    config = tmp_path / "config.json"
    config.write_text(
        json.dumps(
            {
                "runtime_root": str(runtime),
                "state_root": str(state),
                "portal_service_dir": str(tmp_path / "services"),
                "vivaldi_golden_profile": str(golden),
                "novnc_web_root": str(novnc.parent),
                "viewer_port": viewer_port,
                "max_sessions": 2,
                "create_timeout_seconds": 5,
                "stop_timeout_seconds": 1,
                "commands": {
                    "systemd_run": str(binary / "systemd-run"),
                    "systemctl": str(binary / "systemctl"),
                    "session": "/fake/agent-desktop-session",
                    "cleanup": str(binary / "agent-desktop-cleanup"),
                    "fuse_overlayfs": str(binary / "fuse-overlayfs"),
                    "fusermount": str(binary / "fusermount3"),
                    "vivaldi": str(binary / "vivaldi"),
                    "xdg_open": str(binary / "xdg-open"),
                },
            }
        )
    )
    pythonpath = os.pathsep.join(filter(None, (str(PACKAGE / "src"), os.getenv("PYTHONPATH"))))
    environment = os.environ | {
        "PYTHONPATH": pythonpath,
        "PATH": f"{binary}:{os.environ['PATH']}",
        "XDG_RUNTIME_DIR": str(runtime_base),
        "FAKE_SYSTEMD": str(tmp_path / "units"),
    }
    try:
        yield World(tmp_path, config, environment, viewer_port)
    finally:
        shutil.rmtree(runtime_base, ignore_errors=True)


def control_server(
    path: Path, replies: list[dict[str, Any]], state_path: Path | None = None
) -> tuple[list[dict[str, Any]], threading.Thread]:
    received: list[dict[str, Any]] = []
    ready = threading.Event()

    def serve() -> None:
        path.unlink(missing_ok=True)
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
            listener.bind(str(path))
            listener.listen()
            ready.set()
            for reply in replies:
                connection, _ = listener.accept()
                with connection, connection.makefile("rb") as stream:
                    request = json.loads(stream.readline())
                    received.append(request)
                    response = reply | {"arguments": request["arguments"]} if reply.get("ok") else reply
                    if reply.get("ok") and state_path is not None:
                        state = json.loads(state_path.read_text())
                        state["state"] = "active"
                        state_path.write_text(json.dumps(state))
                    connection.sendall(json.dumps(response).encode() + b"\n")

    thread = threading.Thread(target=serve)
    thread.start()
    assert ready.wait(1)
    return received, thread


def test_lifecycle_concurrency_capacity_and_crash_reclamation(world: World) -> None:
    first = world.create("desktop-one", "worker-one")
    second = world.create("desktop-two", "worker-two")
    assert first["state"] == second["state"] == "ready"
    assert first["runtime_dir"] != second["runtime_dir"]
    failure = world.cli("create", "worker-three", "--session-id", "desktop-three", succeeds=False)
    assert "capacity reached" in failure.stderr
    listed = json.loads(world.cli("list", "--json").stdout)
    assert {session["id"] for session in listed} == {"desktop-one", "desktop-two"}
    read_only = Path(first["runtime_dir"]) / "read-only"
    read_only.mkdir()
    (read_only / "temporary").write_text("remove me")
    read_only.chmod(0o500)

    stopped = json.loads(world.cli("destroy", "desktop-one", "--json").stdout)
    assert stopped["state"] == "stopped"
    assert json.loads(world.cli("destroy", "desktop-one", "--json").stdout)["state"] == "stopped"
    assert not Path(first["runtime_dir"]).exists()
    (world.units / second["unit"]).unlink()
    crashed = json.loads(world.cli("status", "desktop-two", "--json").stdout)
    assert crashed["state"] == "failed"
    assert "no longer active" in crashed["message"]
    assert not Path(second["runtime_dir"]).exists()


def test_sessions_are_unbounded_unless_an_operator_sets_a_limit(world: World) -> None:
    document = json.loads(world.config.read_text())
    document.pop("max_sessions")
    world.config.write_text(json.dumps(document))

    sessions = [world.create(f"desktop-{index}", f"worker-{index}") for index in range(1, 6)]

    assert all(session["state"] == "ready" for session in sessions)
    assert {session["id"] for session in json.loads(world.cli("list", "--json").stdout)} == {
        f"desktop-{index}" for index in range(1, 6)
    }


def test_cleanup_detaches_every_unreachable_session_mount(world: World, monkeypatch: pytest.MonkeyPatch) -> None:
    from agent_desktop.models import Config, cleanup_session

    config = Config.model_validate_json(world.config.read_text())
    runtime = config.runtime_dir("crashed-session")
    profile = runtime / "browser-profile"
    documents = runtime / "doc"
    overlay = config.browser_overlay_dir("crashed-session")
    for path in (profile, documents, overlay):
        path.mkdir(parents=True)
    mounted = {profile, documents}
    calls: list[list[str]] = []
    real_read_text = Path.read_text

    def fake_read_text(path: Path, *arguments: Any, **options: Any) -> str:
        if path == Path("/proc/self/mountinfo"):
            return "".join(
                f"{index} 1 0:99 / {mount} rw - fuse.test test rw\n" for index, mount in enumerate(mounted, 42)
            )
        return real_read_text(path, *arguments, **options)

    def fake_run(arguments: list[str], **options: Any) -> subprocess.CompletedProcess[str]:
        calls.append(arguments)
        assert arguments[:3] == [config.commands.fusermount, "-u", "-z"]
        mounted.remove(Path(arguments[-1]))
        return subprocess.CompletedProcess(arguments, 0, "", "")

    monkeypatch.setattr(Path, "read_text", fake_read_text)
    monkeypatch.setattr("agent_desktop.models.subprocess.run", fake_run)
    cleanup_session(config, "crashed-session")

    assert {Path(arguments[-1]) for arguments in calls} == {profile, documents}
    assert not overlay.exists()


def test_exact_argv_browser_action_and_launch_failure_are_contained(
    world: World,
) -> None:
    session = world.create("launch-session")
    control = Path(session["control_socket"])
    received, server = control_server(
        control,
        [
            {"ok": True, "pid": 4101},
            {"ok": True, "pid": 4102},
            {"ok": False, "code": "launch_failed", "message": "missing executable"},
        ],
        world.root / "state/sessions/launch-session.json",
    )
    literal = "exact value ; $(not-executed)"
    launched = json.loads(world.cli("exec", "--json", session["id"], "--", "printf", "%s", literal).stdout)
    browser = json.loads(world.cli("browser", "--json", session["id"], "https://example.com/a b").stdout)
    failure = world.cli("exec", session["id"], "--", "/missing", succeeds=False)
    server.join(2)
    assert not server.is_alive()
    assert launched == {"pid": 4101, "arguments": ["printf", "%s", literal]}
    assert browser["pid"] == 4102
    assert received[0]["arguments"] == ["printf", "%s", literal]
    assert received[1]["arguments"] == [
        str(world.root / "bin/vivaldi"),
        f"--user-data-dir={session['browser_profile']}",
        "--no-first-run",
        "--no-default-browser-check",
        "--force-renderer-accessibility",
        "--ozone-platform=wayland",
        "--new-window",
        "https://example.com/a b",
    ]
    assert "missing executable" in failure.stderr
    assert json.loads(world.cli("status", session["id"], "--json").stdout)["state"] == "active"
    invalid = world.cli("browser", session["id"], "--", "--unsafe-option", succeeds=False)
    assert "browser URL must use" in invalid.stderr


def test_tampered_state_fails_closed_while_listing_quarantines_it(world: World) -> None:
    session = world.create("safe-session")
    state_dir = world.root / "state/sessions"
    malformed = state_dir / "broken.json"
    malformed.write_text("not json")
    assert [item["id"] for item in json.loads(world.cli("list", "--json").stdout)] == ["safe-session"]
    assert world.cli("create", "other", "--session-id", "other-session", succeeds=False).returncode == 1
    malformed.unlink()

    valuable = world.root / "valuable"
    valuable.mkdir()
    (valuable / "keep").write_text("important")
    document = json.loads((state_dir / "safe-session.json").read_text())
    document["runtime_dir"] = str(valuable)
    (state_dir / "safe-session.json").write_text(json.dumps(document))
    failure = world.cli("destroy", "safe-session", succeeds=False)
    assert "invalid ownership" in failure.stderr
    assert (valuable / "keep").read_text() == "important"

    document["runtime_dir"] = session["runtime_dir"]
    document["id"] = "safe-session"
    (state_dir / "alias-session.json").write_text(json.dumps(document))
    assert world.cli("destroy", "alias-session", succeeds=False).returncode == 1
    assert (valuable / "keep").exists()


def test_supervisor_builds_an_isolated_launchable_desktop_and_reclaims_it(world: World) -> None:
    golden = world.root / "state/browser-golden/vivaldi"
    preferences = golden / "Default/Preferences"
    preferences.parent.mkdir()
    preferences.write_text(
        '{"profile":{"exit_type":"Crashed"},"vivaldi":{"startup":{"crash_detection_last_seen_version":"8.1"}}}'
    )
    local_state = golden / "Local State"
    local_state.write_text('{"vivaldi":{"CrashReportingConsentDialogLastSeenTime":0}}')
    (golden / "Crash Reports").mkdir()
    session_id = "runtime-session"
    world.units.mkdir(parents=True, exist_ok=True)
    (world.units / f"agent-desktop-{session_id}.service").touch()
    environment = world.environment | {
        "DISPLAY": ":0",
        "WAYLAND_DISPLAY": "wayland-primary",
        "SSH_AUTH_SOCK": "/primary/ssh",
        "SECRET_TOKEN": "must-not-leak",
    }
    process = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "agent_desktop.session",
            "--config",
            str(world.config),
            "--session-id",
            session_id,
            "--agent-id",
            "runtime-agent",
        ],
        cwd=PACKAGE,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    state_path = world.root / f"state/sessions/{session_id}.json"
    try:
        for _ in range(120):
            if state_path.exists() and json.loads(state_path.read_text())["state"] == "ready":
                break
            if process.poll() is not None:
                pytest.fail(process.communicate()[1])
            time.sleep(0.05)
        else:
            pytest.fail("supervisor did not become ready")
        probe = world.root / "application.json"
        literal = "exact value ; $(not-executed)"
        launched = json.loads(
            world.cli(
                "exec",
                "--json",
                session_id,
                "--",
                sys.executable,
                "-c",
                "import json,os,sys,time;open(sys.argv[1],'w').write(json.dumps({'env':dict(os.environ),'value':sys.argv[2]}));time.sleep(30)",
                str(probe),
                literal,
            ).stdout
        )
        for _ in range(40):
            if probe.exists():
                break
            time.sleep(0.05)
        observed = json.loads(probe.read_text())
        assert observed["value"] == literal and launched["pid"] > 0
        assert not {"DISPLAY", "SSH_AUTH_SOCK", "SECRET_TOKEN"} & observed["env"].keys()
        assert observed["env"]["WAYLAND_DISPLAY"] == "wayland-1"
        clone = Path(json.loads(state_path.read_text())["browser_profile"])
        (clone / "session-only").write_text("private")
        assert not (golden / "session-only").exists()
        clone_preferences = json.loads((clone / "Default/Preferences").read_text())
        assert clone_preferences["profile"]["exit_type"] == "Normal"
        assert clone_preferences["vivaldi"]["startup"]["crash_detection_last_seen_version"] == "8.1"
        assert clone_preferences["download"]["default_directory"].endswith("/downloads")
        clone_local_state = json.loads((clone / "Local State").read_text())
        assert clone_local_state["vivaldi"]["CrashReportingConsentDialogLastSeenTime"] > 0
        assert "CrashReportingConsentGranted" not in clone_local_state["vivaldi"]
        assert json.loads(local_state.read_text()) == {"vivaldi": {"CrashReportingConsentDialogLastSeenTime": 0}}
        assert json.loads(world.cli("status", "--json", session_id).stdout)["state"] == "active"
    finally:
        process.terminate()
        stdout, stderr = process.communicate(timeout=5)
    assert process.returncode == 0, stdout + stderr
    assert json.loads(state_path.read_text())["state"] == "stopped"
    assert not (Path(world.environment["XDG_RUNTIME_DIR"]) / f"agent-desktop/{session_id}").exists()


def test_viewer_is_loopback_authorized_and_selects_the_requested_desktop(
    world: World,
) -> None:
    session = world.create("view-session", "observer")
    process = subprocess.Popen(
        [sys.executable, "-m", "agent_desktop.viewer", "--config", str(world.config)],
        cwd=PACKAGE,
        env=world.environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    health = f"http://127.0.0.1:{world.viewer_port}/health"
    try:
        deadline = time.monotonic() + 5
        while True:
            try:
                with urllib.request.urlopen(health, timeout=0.2) as response:
                    assert json.load(response) == {"status": "ok"}
                    break
            except urllib.error.URLError:
                if time.monotonic() >= deadline:
                    pytest.fail("viewer did not become ready")
                time.sleep(0.05)
        token_path = Path(world.environment["XDG_RUNTIME_DIR"]) / "agent-desktop-viewer/token"
        token = token_path.read_text()
        assert stat.S_IMODE(token_path.stat().st_mode) == 0o600
        with pytest.raises(urllib.error.HTTPError) as unauthorized:
            urllib.request.urlopen(f"http://127.0.0.1:{world.viewer_port}/api/sessions")
        assert unauthorized.value.code == 401
        with urllib.request.urlopen(f"http://127.0.0.1:{world.viewer_port}/api/sessions?token={token}") as response:
            sessions = json.load(response)
        assert {name: sessions[0][name] for name in ("id", "agent_id", "state", "viewer_available")} == {
            "id": session["id"],
            "agent_id": "observer",
            "state": "ready",
            "viewer_available": True,
        }
        url = world.cli("view", session["id"], "--print").stdout.strip()
        public, fragment = url.split("#", 1)
        assert token not in public
        assert fragment == f"token={token}&session={session['id']}"
    finally:
        process.terminate()
        process.wait(5)
    assert not (Path(world.environment["XDG_RUNTIME_DIR"]) / "agent-desktop-viewer/token").exists()
