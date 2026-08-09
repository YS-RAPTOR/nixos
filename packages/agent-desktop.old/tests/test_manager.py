import json
import socket
import subprocess
import time
from collections.abc import Sequence
from pathlib import Path
from threading import Event, Thread

import pytest

from agent_desktop.errors import AgentDesktopError
from agent_desktop.models import Config, Session, SessionState
from agent_desktop.storage import read_model, write_json
from agent_desktop.system import SessionManager


class FakeRunner:
    def __init__(self, config: Config) -> None:
        self.config = config
        self.arguments: list[list[str]] = []
        self.active: set[str] = set()
        self.states: dict[str, str] = {}

    def run(
        self,
        arguments: Sequence[str],
        *,
        check: bool = True,
        timeout: float = 30,
    ) -> subprocess.CompletedProcess[str]:
        del check, timeout
        values = list(arguments)
        self.arguments.append(values)
        if values[0] == self.config.commands.systemd_run:
            unit = next(
                value.removeprefix("--unit=")
                for value in values
                if value.startswith("--unit=")
            )
            session_id = values[values.index("--session-id") + 1]
            state_path = self.config.state_path(session_id)
            starting = read_model(state_path, Session)
            ready = starting.model_copy(
                update={
                    "state": SessionState.READY,
                    "updated_at": time.time(),
                    "ready_at": time.time(),
                    "wayland_display": "wayland-1",
                    "cua_socket": starting.runtime_dir / "cua.sock",
                    "control_socket": starting.runtime_dir / "control.sock",
                    "browser_profile": starting.runtime_dir / "browser-profile",
                }
            )
            write_json(state_path, ready)
            self.active.add(unit)
            self.states[unit] = "active"
            return subprocess.CompletedProcess(values, 0, "", "")
        if values[:3] == [self.config.commands.systemctl, "--user", "show"]:
            unit = values[3]
            output = (
                f"LoadState=loaded\nActiveState={self.states[unit]}\n"
                if unit in self.active
                else "LoadState=not-found\nActiveState=inactive\n"
            )
            return subprocess.CompletedProcess(values, 0, output, "")
        if values[:3] == [self.config.commands.systemctl, "--user", "stop"]:
            self.active.discard(values[-1])
            self.states.pop(values[-1], None)
            return subprocess.CompletedProcess(values, 0, "", "")
        return subprocess.CompletedProcess(values, 0, "", "")


class StartingRunner(FakeRunner):
    def __init__(self, config: Config) -> None:
        super().__init__(config)
        self.started = Event()

    def run(
        self,
        arguments: Sequence[str],
        *,
        check: bool = True,
        timeout: float = 30,
    ) -> subprocess.CompletedProcess[str]:
        values = list(arguments)
        if values[0] == self.config.commands.systemd_run:
            unit = next(
                value.removeprefix("--unit=")
                for value in values
                if value.startswith("--unit=")
            )
            self.arguments.append(values)
            self.active.add(unit)
            self.states[unit] = "activating"
            self.started.set()
            return subprocess.CompletedProcess(values, 0, "", "")
        return super().run(arguments, check=check, timeout=timeout)


class FailedStartRunner(FakeRunner):
    def run(
        self,
        arguments: Sequence[str],
        *,
        check: bool = True,
        timeout: float = 30,
    ) -> subprocess.CompletedProcess[str]:
        values = list(arguments)
        if values[0] == self.config.commands.systemd_run:
            unit = next(
                value.removeprefix("--unit=")
                for value in values
                if value.startswith("--unit=")
            )
            self.arguments.append(values)
            self.active.add(unit)
            self.states[unit] = "activating"
            raise AgentDesktopError("simulated startup timeout", "command_timeout")
        return super().run(arguments, check=check, timeout=timeout)


def make_config(tmp_path: Path) -> Config:
    return Config(
        runtime_root=tmp_path / "run",
        state_root=tmp_path / "state",
        portal_service_dir=tmp_path / "services",
    )


def test_create_and_destroy_use_one_transient_notified_unit(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    config = make_config(tmp_path)
    runner = FakeRunner(config)
    manager = SessionManager(
        config,
        tmp_path / "config.json",
        runner=runner,
        session_command="/nix/store/agent-desktop-session",
    )

    created = manager.create("worker-1", "worker-1-session")
    assert created.state == SessionState.READY
    assert created.wayland_display == "wayland-1"

    start = runner.arguments[0]
    assert "--service-type=notify" in start
    assert "--no-block" in start
    assert "--property=NotifyAccess=main" in start
    assert "--property=KillMode=control-group" in start
    assert "--property=RuntimeDirectory=run/worker-1-session" in start
    assert "--property=RuntimeDirectoryMode=0700" in start
    assert any(
        value.startswith("--property=ExecStopPost=")
        and "--session-id worker-1-session" in value
        for value in start
    )
    assert "--unit=agent-desktop-worker-1-session.service" in start

    stopped = manager.destroy(created.id)
    assert stopped.state == SessionState.STOPPED
    assert not created.runtime_dir.exists()


def test_exec_and_browser_send_exact_arguments_to_the_session_control_socket(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    config = make_config(tmp_path)
    runner = FakeRunner(config)
    manager = SessionManager(
        config,
        tmp_path / "config.json",
        runner=runner,
        session_command="/nix/store/agent-desktop-session",
    )
    created = manager.create("launcher", "launcher-session")
    control = created.runtime_dir / "control.sock"
    control.parent.mkdir(parents=True, exist_ok=True)
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(str(control))
    listener.listen(1)
    received: list[list[str]] = []

    def serve() -> None:
        for pid in (4242, 4243):
            connection, _ = listener.accept()
            with connection:
                request = json.loads(connection.recv(65536))
                arguments = request["arguments"]
                received.append(arguments)
                connection.sendall(
                    json.dumps(
                        {"ok": True, "pid": pid, "arguments": arguments}
                    ).encode()
                    + b"\n"
                )

    server = Thread(target=serve)
    server.start()
    launched = manager.launch(created.id, ["printf", "%s", "exact value"])
    browser = manager.launch_browser(created.id, "https://example.com")
    server.join(timeout=2)
    listener.close()

    assert not server.is_alive()
    assert launched.pid == 4242
    assert launched.arguments == ("printf", "%s", "exact value")
    assert browser.pid == 4243
    assert received[0] == ["printf", "%s", "exact value"]
    assert received[1] == [
        config.commands.vivaldi,
        f"--user-data-dir={created.runtime_dir / 'browser-profile'}",
        "--no-first-run",
        "--no-default-browser-check",
        "--force-renderer-accessibility",
        "--new-window",
        "https://example.com",
    ]


def test_destroy_can_cancel_a_session_during_startup(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    config = make_config(tmp_path)
    runner = StartingRunner(config)
    manager = SessionManager(
        config,
        tmp_path / "config.json",
        runner=runner,
        session_command="/nix/store/agent-desktop-session",
    )
    errors: list[AgentDesktopError] = []

    def create() -> None:
        try:
            manager.create("cancel-worker", "cancel-worker-session")
        except AgentDesktopError as error:
            errors.append(error)

    creator = Thread(target=create)
    creator.start()
    assert runner.started.wait(timeout=1)
    stopped = manager.destroy("cancel-worker-session")
    creator.join(timeout=2)

    assert not creator.is_alive()
    assert stopped.state == SessionState.STOPPED
    assert len(errors) == 1
    assert errors[0].code == "session_stopped"
    assert not runner.active


def test_failed_create_stops_an_already_created_unit(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    config = make_config(tmp_path)
    runner = FailedStartRunner(config)
    manager = SessionManager(
        config,
        tmp_path / "config.json",
        runner=runner,
        session_command="/nix/store/agent-desktop-session",
    )

    with pytest.raises(AgentDesktopError, match="simulated startup timeout"):
        manager.create("worker-timeout", "worker-timeout-session")

    assert not runner.active
    failed = read_model(config.state_path("worker-timeout-session"), Session)
    assert failed.state == SessionState.FAILED
    assert failed.stopped_at is not None


def test_list_keeps_an_activating_unit_live(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    config = make_config(tmp_path)
    runner = FakeRunner(config)
    manager = SessionManager(
        config,
        tmp_path / "config.json",
        runner=runner,
        session_command="/nix/store/agent-desktop-session",
    )
    created = manager.create("worker-3", "worker-3-session")
    runner.states[created.unit] = "activating"

    assert manager.status(created.id).state == SessionState.READY


def test_list_reconciles_a_crashed_unit_to_failed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
    config = make_config(tmp_path)
    runner = FakeRunner(config)
    manager = SessionManager(
        config,
        tmp_path / "config.json",
        runner=runner,
        session_command="/nix/store/agent-desktop-session",
    )
    created = manager.create("worker-2", "worker-2-session")
    runner.active.clear()

    sessions = manager.list()
    assert len(sessions) == 1
    assert sessions[0].id == created.id
    assert sessions[0].state == SessionState.FAILED
    assert sessions[0].message == "session unit is no longer active"
