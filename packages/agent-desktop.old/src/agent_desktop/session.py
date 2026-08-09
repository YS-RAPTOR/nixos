from __future__ import annotations

import logging
import os
import re
import shutil
import signal
import socket
import subprocess
import time
from collections.abc import Callable
from pathlib import Path
from types import FrameType

import click

from .browser import BrowserOverlay
from .control import ControlServer
from .desktop_bus import DesktopBus
from .errors import AgentDesktopError
from .models import Config, Session, SessionState, load_config, validate_id
from .processes import Child, ProcessGroup, run_command
from .runtime import RuntimeLayout
from .storage import write_json

_LOG = logging.getLogger("agent-desktop-session")


class _StopRequested(Exception):
    pass


class SessionRuntime:
    def __init__(self, config: Config, session_id: str, agent_id: str) -> None:
        self.config = config
        self.session_id = session_id
        self.agent_id = agent_id
        self.layout = RuntimeLayout(config, session_id)
        self.browser = BrowserOverlay(config, self.layout)
        self.processes = ProcessGroup()
        self.children = self.processes.children
        self.bus = DesktopBus(config, self.layout, self.processes, self._wait_until)
        self.stopping = False
        self.started_at = time.time()
        self.unit = f"agent-desktop-{session_id}.service"
        self.wayland_display: str | None = None
        self.sway_socket: Path | None = None
        self.at_spi_bus_address: str | None = None
        self.startup_deadline: float | None = None
        self.control = ControlServer(self.layout.control_socket)
        self.application_sequence = 0

    def serve(self) -> None:
        self.startup_deadline = time.monotonic() + self.config.create_timeout_seconds
        self._publish(SessionState.STARTING)
        try:
            environment = self._start_services()
            self._mark_ready()
            self._monitor(environment)
        except _StopRequested:
            self.stopping = True
        except BaseException as error:
            if isinstance(error, (KeyboardInterrupt, SystemExit)):
                raise
            self._report_failure(error)
            raise
        finally:
            self._shutdown()

    def _start_services(self) -> dict[str, str]:
        self.layout.prepare()
        environment = self._base_environment()
        if self.config.enable_browser_profile:
            self._start_browser_profile(environment)
        self.bus.start(environment)
        environment["DBUS_SESSION_BUS_ADDRESS"] = self._dbus_address
        if self.config.enable_secret_service:
            self.bus.start_secret_service(environment)
        if self.config.enable_at_spi:
            self.at_spi_bus_address = self.bus.start_at_spi(environment)
        self._start_sway(environment)
        if self.config.enable_vnc:
            self._start_wayvnc(environment)
        self._start_pipewire(environment)
        if self.config.enable_portals:
            self.bus.start_portals(environment)
        if self.config.enable_cua:
            self._start_cua(environment)
        self._start_control()
        if self.stopping:
            raise _StopRequested
        return environment

    def _mark_ready(self) -> None:
        self._publish(SessionState.READY, ready_at=time.time())
        _sd_notify("READY=1\nSTATUS=Agent desktop ready")

    def _report_failure(self, error: BaseException) -> None:
        _LOG.exception("session failed")
        self._log_failure_tails()
        self._publish(SessionState.FAILED, message=str(error), stopped_at=time.time())
        _sd_notify(f"STATUS=Agent desktop failed: {error}")

    def _shutdown(self) -> None:
        self._stop_control()
        self._stop_children()
        shutil.rmtree(self.layout.browser_overlay_root, ignore_errors=True)
        shutil.rmtree(self.layout.root, ignore_errors=True)
        if self.stopping:
            self._publish(SessionState.STOPPED, stopped_at=time.time())

    @property
    def _dbus_address(self) -> str:
        return self.bus.address

    def request_stop(self, _signal: int, _frame: FrameType | None) -> None:
        self.stopping = True
        _sd_notify("STOPPING=1\nSTATUS=Stopping agent desktop")

    def _base_environment(self) -> dict[str, str]:
        return self.layout.environment()

    def _start_browser_profile(self, environment: dict[str, str]) -> None:
        self.browser.start(environment, self._spawn, self._wait_until)

    def _start_sway(self, environment: dict[str, str]) -> None:
        self._spawn(
            "sway",
            [self.config.commands.sway, "-c", str(self.layout.sway_config)],
            environment,
        )
        self.wayland_display = self._wait_for_glob("wayland-*", "Wayland socket")
        sway_socket = self._wait_for_glob("sway-ipc.*.sock", "Sway IPC socket")
        self.sway_socket = self.layout.root / sway_socket
        environment["WAYLAND_DISPLAY"] = self.wayland_display
        environment["SWAYSOCK"] = str(self.sway_socket)
        self._wait_command(
            [self.config.commands.swaymsg, "-t", "get_outputs", "-r"],
            environment,
            "Sway output",
        )

    def _start_wayvnc(self, environment: dict[str, str]) -> None:
        self._spawn(
            "wayvnc",
            [
                self.config.commands.wayvnc,
                "--seat=seat0",
                f"--output={self.config.output_name}",
                f"--max-fps={self.config.vnc_max_fps}",
                "--socket",
                str(self.layout.wayvnc_control_socket),
                "--name",
                f"Agent Desktop {self.session_id}",
                f"ws-unix:{self.layout.vnc_socket}",
            ],
            environment,
        )
        self._wait_for_path(self.layout.vnc_socket, "WayVNC WebSocket")
        self._wait_for_path(self.layout.wayvnc_control_socket, "WayVNC control socket")

    def _start_pipewire(self, environment: dict[str, str]) -> None:
        self._spawn("pipewire", [self.config.commands.pipewire], environment)
        self._wait_for_path(self.layout.root / "pipewire-0", "PipeWire socket")
        self._spawn("wireplumber", [self.config.commands.wireplumber], environment)

        def wireplumber_ready() -> bool:
            result = self._run(
                [self.config.commands.pw_dump], environment, check=False, timeout=5
            )
            return result.returncode == 0 and "WirePlumber" in result.stdout

        self._wait_until(wireplumber_ready, "WirePlumber policy")

    def _start_cua(self, environment: dict[str, str]) -> None:
        self._spawn(
            "cua",
            [
                self.config.commands.cua_driver,
                "serve",
                "--socket",
                str(self.layout.cua_socket),
                "--no-overlay",
                "--no-permissions-gate",
            ],
            environment,
        )
        self._wait_for_path(self.layout.cua_socket, "CUA socket")
        self._wait_command(
            [
                self.config.commands.cua_driver,
                "status",
                "--socket",
                str(self.layout.cua_socket),
            ],
            environment,
            "CUA daemon",
        )

    def _start_control(self) -> None:
        self.control.start()

    def _stop_control(self) -> None:
        self.control.stop()

    def _accept_control_requests(self, environment: dict[str, str]) -> None:
        if self.stopping:
            return
        try:
            self.control.accept(
                lambda arguments: self._spawn_application(arguments, environment)
            )
        except AgentDesktopError:
            if not self.stopping:
                raise

    def _spawn_application(
        self, arguments: list[str], environment: dict[str, str]
    ) -> int:
        self.application_sequence += 1
        basename = Path(arguments[0]).name
        safe_name = re.sub(r"[^A-Za-z0-9_.-]+", "-", basename)[:48] or "app"
        process = self.processes.spawn(
            f"application:{safe_name}",
            arguments,
            environment,
            self.layout.logs_dir
            / f"app-{self.application_sequence:04d}-{safe_name}.log",
            critical=False,
        )
        return process.pid

    def _monitor(self, environment: dict[str, str]) -> None:
        next_health = time.monotonic() + self.config.health_interval_seconds
        while not self.stopping:
            self._accept_control_requests(environment)
            self.processes.reap()
            if time.monotonic() >= next_health:
                self._health_check(environment)
                next_health = time.monotonic() + self.config.health_interval_seconds
            time.sleep(0.2)

    def _health_check(self, environment: dict[str, str]) -> None:
        if not self.control.active or not self.layout.control_socket.is_socket():
            raise AgentDesktopError(
                "application control socket disappeared", "health_check_failed"
            )
        if self.config.enable_browser_profile and not os.path.ismount(
            self.layout.browser_profile
        ):
            raise AgentDesktopError(
                "browser profile overlay disappeared", "health_check_failed"
            )
        if self.config.enable_secret_service and not self.bus.secret_service_is_ready(
            environment
        ):
            raise AgentDesktopError(
                "shared Secret Service disappeared", "health_check_failed"
            )
        if self.config.enable_vnc and not self.layout.vnc_socket.exists():
            raise AgentDesktopError(
                "WayVNC WebSocket disappeared", "health_check_failed"
            )
        self._run(
            [self.config.commands.swaymsg, "-t", "get_outputs", "-r"],
            environment,
            timeout=5,
        )
        pipewire = self._run([self.config.commands.pw_dump], environment, timeout=5)
        if "WirePlumber" not in pipewire.stdout:
            raise AgentDesktopError(
                "WirePlumber disappeared from the private PipeWire graph",
                "health_check_failed",
            )
        if self.config.enable_portals:
            self.bus.check_portals(environment)
        if self.config.enable_cua:
            self._run(
                [
                    self.config.commands.cua_driver,
                    "status",
                    "--socket",
                    str(self.layout.cua_socket),
                ],
                environment,
                timeout=5,
            )

    def _spawn(
        self, name: str, arguments: list[str], environment: dict[str, str]
    ) -> None:
        self.processes.spawn_service(
            name,
            arguments,
            environment,
            self.layout.logs_dir / f"{name}.log",
        )

    def _run(
        self,
        arguments: list[str],
        environment: dict[str, str],
        *,
        check: bool = True,
        timeout: float = 10,
    ) -> subprocess.CompletedProcess[str]:
        return run_command(arguments, environment, check=check, timeout=timeout)

    def _wait_command(
        self,
        arguments: list[str],
        environment: dict[str, str],
        label: str,
    ) -> None:
        self._wait_until(
            lambda: self._run(arguments, environment, check=False).returncode == 0,
            label,
        )

    def _wait_for_path(self, path: Path, label: str) -> None:
        self._wait_until(path.exists, label)

    def _wait_for_glob(self, pattern: str, label: str) -> str:
        value: str | None = None

        def found() -> bool:
            nonlocal value
            candidates = [
                path.name
                for path in self.layout.root.glob(pattern)
                if not path.name.endswith(".lock")
            ]
            if candidates:
                value = min(candidates)
                return True
            return False

        self._wait_until(found, label)
        assert value is not None
        return value

    def _wait_until(self, predicate: Callable[[], bool], label: str) -> None:
        deadline = self.startup_deadline or (
            time.monotonic() + self.config.create_timeout_seconds
        )
        while time.monotonic() < deadline:
            if self.stopping:
                raise _StopRequested
            if predicate():
                return
            self.processes.ensure_running_while_waiting(label)
            time.sleep(0.05)
        if self.stopping:
            raise _StopRequested
        raise AgentDesktopError(f"timed out waiting for {label}", "readiness_timeout")

    def _log_failure_tails(self) -> None:
        for path in sorted(self.layout.logs_dir.glob("*.log")):
            try:
                lines = path.read_text(errors="replace").splitlines()[-30:]
            except OSError:
                continue
            if lines:
                _LOG.error("%s tail:\n%s", path.name, "\n".join(lines))

    def _stop_children(self) -> None:
        ordinary = [
            child
            for child in reversed(self.children)
            if child.name != "browser-overlay"
        ]
        overlay = [
            child
            for child in reversed(self.children)
            if child.name == "browser-overlay"
        ]
        self._stop_processes(ordinary)
        if self.config.enable_browser_profile:
            self.browser.unmount(self._base_environment())
        self._stop_processes(overlay)

    def _stop_processes(self, children: list[Child]) -> None:
        self.processes.stop(children, self.config.stop_timeout_seconds)

    def _publish(
        self,
        state: SessionState,
        *,
        message: str | None = None,
        ready_at: float | None = None,
        stopped_at: float | None = None,
    ) -> None:
        previous: Session | None = None
        path = self.config.state_path(self.session_id)
        if path.exists():
            try:
                previous = Session.model_validate_json(path.read_bytes())
            except ValueError:
                previous = None
        session = Session(
            id=self.session_id,
            agent_id=self.agent_id,
            unit=self.unit,
            state=state,
            created_at=previous.created_at if previous else self.started_at,
            updated_at=time.time(),
            runtime_dir=self.layout.root,
            wayland_display=self.wayland_display,
            sway_socket=self.sway_socket,
            dbus_address=self._dbus_address,
            at_spi_bus_address=self.at_spi_bus_address,
            cua_socket=self.layout.cua_socket if self.config.enable_cua else None,
            vnc_socket=self.layout.vnc_socket if self.config.enable_vnc else None,
            control_socket=(
                self.layout.control_socket if self.control.active else None
            ),
            browser_profile=(
                self.layout.browser_profile
                if self.config.enable_browser_profile
                else None
            ),
            ready_at=ready_at or (previous.ready_at if previous else None),
            stopped_at=stopped_at,
            message=message,
        )
        write_json(path, session)


def _sd_notify(message: str) -> None:
    address = os.environ.get("NOTIFY_SOCKET")
    if not address:
        return
    if address.startswith("@"):
        address = "\0" + address[1:]
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as notify:
        notify.connect(address)
        notify.sendall(message.encode())


@click.command()
@click.option("--config", "config_path", required=True, type=click.Path(path_type=Path))
@click.option("--session-id", required=True)
@click.option("--agent-id", required=True)
@click.option(
    "--log-level",
    default="INFO",
    type=click.Choice(["DEBUG", "INFO", "WARNING", "ERROR"]),
)
def command(config_path: Path, session_id: str, agent_id: str, log_level: str) -> None:
    """Run one complete agent desktop inside its owning systemd unit."""
    logging.basicConfig(
        level=getattr(logging, log_level), format="%(levelname)s %(message)s"
    )
    try:
        validate_id(session_id, "session ID")
        validate_id(agent_id, "agent ID")
        runtime = SessionRuntime(load_config(config_path), session_id, agent_id)
        signal.signal(signal.SIGTERM, runtime.request_stop)
        signal.signal(signal.SIGINT, runtime.request_stop)
        runtime.serve()
    except (AgentDesktopError, ValueError) as error:
        raise click.ClickException(str(error)) from error


def main() -> None:
    command(prog_name="agent-desktop-session")
