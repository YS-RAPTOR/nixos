import json
import socket
import sys
from pathlib import Path

import pytest

from agent_desktop.errors import AgentDesktopError
from agent_desktop.models import Config
from agent_desktop.session import RuntimeLayout, SessionRuntime


def test_runtime_layout_is_private_and_routes_services_locally(tmp_path: Path) -> None:
    config = Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        portal_service_dir=Path("/nix/store/portal/share/dbus-1/services"),
        browser_overlay_root=tmp_path / "browser-overlays",
        output_width=1024,
        output_height=768,
    )
    layout = RuntimeLayout(config, "session-1")
    layout.prepare()

    assert layout.root.stat().st_mode & 0o777 == 0o700
    assert layout.browser_upper.stat().st_mode & 0o777 == 0o700
    assert layout.browser_work.stat().st_mode & 0o777 == 0o700
    sway = layout.sway_config.read_text()
    assert "output HEADLESS-1 mode 1024x768@60Hz" in sway
    assert "seat seat0 fallback true" in sway
    assert 'seat seat0 attach "*"' in sway

    portals = (layout.config_dir / "xdg-desktop-portal" / "portals.conf").read_text()
    assert "default=none" in portals
    assert "ScreenCast=wlr" in portals
    assert "Screenshot=wlr" in portals
    assert "Access=gtk" in portals

    wireplumber = (
        layout.config_dir
        / "wireplumber"
        / "wireplumber.conf.d"
        / "10-agent-isolation.conf"
    ).read_text()
    assert "hardware.bluetooth = disabled" in wireplumber
    assert "policy.standard" not in wireplumber

    bus = layout.dbus_config.read_text()
    assert str(layout.dbus_socket) in bus
    assert str(config.portal_service_dir) in bus


def test_control_socket_launches_exact_argv_as_a_noncritical_session_child(
    tmp_path: Path,
) -> None:
    config = Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        browser_overlay_root=tmp_path / "browser-overlays",
        portal_service_dir=tmp_path / "services",
    )
    runtime = SessionRuntime(config, "session-1", "agent-1")
    runtime.layout.prepare()
    runtime._start_control()
    arguments = [sys.executable, "-c", "import time; time.sleep(2)", "exact value"]

    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.connect(str(runtime.layout.control_socket))
            client.sendall(
                json.dumps(
                    {"version": 1, "operation": "launch", "arguments": arguments}
                ).encode()
                + b"\n"
            )
            runtime._accept_control_requests(runtime._base_environment())
            response = json.loads(client.recv(65536))

        assert response["ok"] is True
        assert response["pid"] > 0
        assert response["arguments"] == arguments
        launched = runtime.children[-1]
        assert launched.process.args == arguments
        assert not launched.critical
    finally:
        runtime._stop_control()
        runtime._stop_children()


@pytest.mark.parametrize(
    "payload",
    [
        {"version": 1, "operation": "launch", "arguments": []},
        {"operation": "launch", "arguments": ["true"]},
        {"version": True, "operation": "launch", "arguments": ["true"]},
    ],
)
def test_control_socket_rejects_invalid_requests_without_spawning(
    tmp_path: Path,
    payload: dict[str, object],
) -> None:
    config = Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        browser_overlay_root=tmp_path / "browser-overlays",
        portal_service_dir=tmp_path / "services",
    )
    runtime = SessionRuntime(config, "session-1", "agent-1")
    runtime.layout.prepare()
    runtime._start_control()

    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.connect(str(runtime.layout.control_socket))
            client.sendall(json.dumps(payload).encode() + b"\n")
            runtime._accept_control_requests(runtime._base_environment())
            response = json.loads(client.recv(65536))

        assert response["ok"] is False
        assert response["code"] == "launch_failed"
        assert runtime.children == []
    finally:
        runtime._stop_control()


def test_process_reaping_distinguishes_applications_from_critical_services(
    tmp_path: Path,
) -> None:
    config = Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        browser_overlay_root=tmp_path / "browser-overlays",
        portal_service_dir=tmp_path / "services",
    )
    runtime = SessionRuntime(config, "session-1", "agent-1")
    runtime.layout.prepare()
    environment = runtime._base_environment()

    application = runtime.processes.spawn(
        "application:test",
        [sys.executable, "-c", "raise SystemExit(0)"],
        environment,
        runtime.layout.logs_dir / "app.log",
        critical=False,
    )
    application.wait(timeout=2)
    runtime.processes.reap()
    assert runtime.children == []

    service = runtime.processes.spawn(
        "critical-test",
        [sys.executable, "-c", "raise SystemExit(7)"],
        environment,
        runtime.layout.logs_dir / "service.log",
    )
    service.wait(timeout=2)
    try:
        with pytest.raises(AgentDesktopError, match="status 7") as failure:
            runtime.processes.reap()
        assert failure.value.code == "child_exited"
    finally:
        runtime.processes.stop(list(runtime.children), timeout=1)


def test_child_environment_does_not_inherit_primary_desktop_or_credentials(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.setenv("PATH", "/nix/store/tools/bin")
    monkeypatch.setenv("DISPLAY", ":0")
    monkeypatch.setenv("WAYLAND_DISPLAY", "wayland-primary")
    monkeypatch.setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/primary/bus")
    monkeypatch.setenv("SSH_AUTH_SOCK", "/primary/ssh-agent")
    monkeypatch.setenv("SECRET_TOKEN", "must-not-leak")
    config = Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        portal_service_dir=tmp_path / "services",
    )

    environment = SessionRuntime(config, "session-1", "agent-1")._base_environment()

    assert environment["HOME"] == str(tmp_path / "home")
    assert environment["PATH"] == "/nix/store/tools/bin"
    assert environment["XDG_RUNTIME_DIR"] == str(config.runtime_dir("session-1"))
    assert environment["WLR_BACKENDS"] == "headless"
    assert environment["GSETTINGS_BACKEND"] == "memory"
    for name in (
        "DISPLAY",
        "WAYLAND_DISPLAY",
        "DBUS_SESSION_BUS_ADDRESS",
        "SSH_AUTH_SOCK",
        "SECRET_TOKEN",
    ):
        assert name not in environment
