from __future__ import annotations

import contextlib
import html
import json
import logging
import os
import re
import signal
import socket
import subprocess
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from types import FrameType
from typing import TextIO

import click

from .models import (
    AgentDesktopError,
    Config,
    Session,
    State,
    cleanup_session,
    is_mount,
    load_config,
    read_session,
    remove_tree,
    unit_name,
    validate_id,
    write_json,
)
from .system import run

_LOG = logging.getLogger("agent-desktop-session")
_BUS_ADDRESS = re.compile(r'"([^"]+)"')
_MAX_FRAME = 64 * 1024
_MAX_ARGUMENTS = 256
_MAX_ARGUMENT_BYTES = 32 * 1024


class StopRequested(Exception):
    pass


@dataclass(slots=True)
class Child:
    name: str
    process: subprocess.Popen[str]
    log: TextIO
    critical: bool


class SessionRuntime:
    def __init__(self, config: Config, session_id: str, agent_id: str) -> None:
        self.config = config
        self.id = session_id
        self.agent_id = agent_id
        self.root = config.runtime_dir(session_id)
        self.config_dir = self.root / "config"
        self.logs = self.root / "logs"
        self.browser = self.root / "browser-profile"
        self.overlay = config.browser_overlay_dir(session_id)
        self.browser_upper = self.overlay / "upper"
        self.browser_work = self.overlay / "work"
        self.bus_socket = self.root / "bus"
        self.control_socket = self.root / "control.sock"
        self.cua_socket = self.root / "cua.sock"
        self.vnc_socket = self.root / "wayvnc.sock"
        self.vnc_control = self.root / "wayvncctl.sock"
        self.sway_config = self.config_dir / "sway.conf"
        self.dbus_config = self.config_dir / "dbus.conf"
        self.children: list[Child] = []
        self.listener: socket.socket | None = None
        self.stopping = False
        self.started_at = time.time()
        self.deadline = 0.0
        self.wayland_display: str | None = None
        self.sway_socket: Path | None = None
        self.at_spi_address: str | None = None
        self.application_sequence = 0

    def serve(self) -> None:
        self.deadline = time.monotonic() + self.config.create_timeout_seconds
        self._publish(State.STARTING)
        try:
            environment = self._start_services()
            self._publish(State.READY, ready_at=time.time())
            _sd_notify("READY=1\nSTATUS=Agent desktop ready")
            self._monitor(environment)
        except StopRequested:
            self.stopping = True
        except BaseException as error:
            if isinstance(error, (KeyboardInterrupt, SystemExit)):
                raise
            _LOG.exception("session failed")
            self._log_tails()
            self._publish(State.FAILED, message=str(error), stopped_at=time.time())
            _sd_notify(f"STATUS=Agent desktop failed: {error}")
            raise
        finally:
            self._shutdown()

    def request_stop(self, _signal: int, _frame: FrameType | None) -> None:
        self.stopping = True
        _sd_notify("STOPPING=1\nSTATUS=Stopping agent desktop")

    def _start_services(self) -> dict[str, str]:
        self._prepare()
        environment = self._environment()
        self._mount_browser(environment)
        self._spawn(
            "dbus",
            [
                self.config.commands.dbus,
                f"--config-file={self.dbus_config}",
                "--nofork",
                "--nopidfile",
            ],
            environment,
        )
        self._wait(self.bus_socket.exists, "private D-Bus")
        environment["DBUS_SESSION_BUS_ADDRESS"] = self.dbus_address
        self._spawn(
            "secret-service",
            [
                self.config.commands.secret_bridge,
                "--private-address",
                self.dbus_address,
                "--host-address",
                self.config.host_dbus_address,
            ],
            environment,
        )
        self._wait_name(
            self.dbus_address,
            "org.freedesktop.secrets",
            environment,
            "shared Secret Service",
        )
        self._start_accessibility(environment)
        self._start_sway(environment)
        self._start_wayvnc(environment)
        self._spawn("pipewire", [self.config.commands.pipewire], environment)
        self._wait((self.root / "pipewire-0").exists, "PipeWire socket")
        self._spawn("wireplumber", [self.config.commands.wireplumber], environment)
        self._wait(lambda: self._pipewire_ready(environment), "WirePlumber policy")
        self._start_portals(environment)
        self._spawn(
            "cua",
            [
                self.config.commands.cua,
                "serve",
                "--socket",
                str(self.cua_socket),
                "--no-overlay",
                "--no-permissions-gate",
            ],
            environment,
        )
        self._wait(self.cua_socket.exists, "CUA socket")
        self._wait_command(
            [self.config.commands.cua, "status", "--socket", str(self.cua_socket)],
            environment,
            "CUA daemon",
        )
        self._start_control()
        if self.stopping:
            raise StopRequested
        return environment

    @property
    def dbus_address(self) -> str:
        return f"unix:path={self.bus_socket}"

    def _start_accessibility(self, environment: dict[str, str]) -> None:
        self._spawn(
            "at-spi",
            [self.config.commands.at_spi_launcher, "--launch-immediately"],
            environment,
        )
        self._wait_name(self.dbus_address, "org.a11y.Bus", environment, "AT-SPI bus")
        for name in ("IsEnabled", "ScreenReaderEnabled"):
            target = ["org.a11y.Bus", "/org/a11y/bus", "org.a11y.Status", name]
            self._command(
                self._busctl(self.dbus_address, "set-property", *target, "b", "true"),
                environment,
            )
            result = self._command(self._busctl(self.dbus_address, "get-property", *target), environment)
            if result.stdout.strip() != "b true":
                raise AgentDesktopError(f"AT-SPI property did not stay enabled: {name}", "at_spi_failed")
        result = self._command(
            self._busctl(
                self.dbus_address,
                "call",
                "org.a11y.Bus",
                "/org/a11y/bus",
                "org.a11y.Bus",
                "GetAddress",
            ),
            environment,
        )
        match = _BUS_ADDRESS.search(result.stdout)
        if not match:
            raise AgentDesktopError("AT-SPI returned no bus address", "at_spi_failed")
        address = match.group(1)
        self.at_spi_address = address
        environment["AT_SPI_BUS_ADDRESS"] = address
        registry_environment = environment | {"DBUS_SESSION_BUS_ADDRESS": address}
        self._spawn(
            "at-spi-registry",
            [
                self.config.commands.at_spi_registry,
                "--dbus-name",
                "org.a11y.atspi.Registry",
            ],
            registry_environment,
        )
        self._wait_name(
            address,
            "org.a11y.atspi.Registry",
            registry_environment,
            "AT-SPI registry",
        )

    def _start_sway(self, environment: dict[str, str]) -> None:
        self._spawn(
            "sway",
            [self.config.commands.sway, "-c", str(self.sway_config)],
            environment,
        )
        self.wayland_display = self._wait_glob("wayland-*", "Wayland socket")
        self.sway_socket = self.root / self._wait_glob("sway-ipc.*.sock", "Sway IPC socket")
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
                str(self.vnc_control),
                "--name",
                f"Agent Desktop {self.id}",
                f"ws-unix:{self.vnc_socket}",
            ],
            environment,
        )
        self._wait(self.vnc_socket.exists, "WayVNC WebSocket")
        self._wait(self.vnc_control.exists, "WayVNC control socket")

    def _start_portals(self, environment: dict[str, str]) -> None:
        services = (
            (
                "portal-gtk",
                [self.config.commands.portal_gtk],
                "org.freedesktop.impl.portal.desktop.gtk",
                "GTK portal",
            ),
            (
                "portal-wlr",
                [self.config.commands.portal_wlr, "-l", "INFO"],
                "org.freedesktop.impl.portal.desktop.wlr",
                "wlroots portal",
            ),
            (
                "portal",
                [self.config.commands.portal, "-v"],
                "org.freedesktop.portal.Desktop",
                "portal frontend",
            ),
        )
        for name, arguments, bus_name, label in services:
            self._spawn(name, arguments, environment)
            self._wait_name(self.dbus_address, bus_name, environment, label)
        for interface in (
            "org.freedesktop.portal.ScreenCast",
            "org.freedesktop.portal.Screenshot",
        ):
            self._wait(
                lambda interface=interface: (
                    self._command(self._portal_version(interface), environment, check=False).returncode == 0
                ),
                interface.rsplit(".", 1)[-1] + " portal",
            )

    def _prepare(self) -> None:
        if self.root.exists() and any(self.root.iterdir()):
            raise AgentDesktopError(f"runtime directory is not empty: {self.root}", "runtime_exists")
        directories = (
            self.root,
            self.config_dir,
            self.logs,
            self.root / "cache",
            self.root / "data",
            self.root / "state",
            self.root / "downloads",
            self.browser,
            self.overlay,
            self.browser_upper,
            self.browser_work,
            self.config_dir / "xdg-desktop-portal",
            self.config_dir / "xdg-desktop-portal-wlr",
            self.config_dir / "wireplumber/wireplumber.conf.d",
        )
        for path in directories:
            path.mkdir(mode=0o700, parents=True, exist_ok=True)
            os.chmod(path, 0o700)
        for path, content in self._configuration().items():
            path.write_text(content)
            os.chmod(path, 0o600)

    def _configuration(self) -> dict[Path, str]:
        config = self.config
        portal_dir = html.escape(str(config.portal_service_dir), quote=True)
        bus = html.escape(str(self.bus_socket), quote=True)
        return {
            self.config_dir / "user-dirs.dirs": (f"XDG_DOWNLOAD_DIR={json.dumps(str(self.root / 'downloads'))}\n"),
            self.sway_config: (
                f"output {config.output_name} mode {config.output_width}x{config.output_height}@{config.output_refresh_hz}Hz\n"
                "default_border pixel 0\nfocus_follows_mouse no\nmouse_warping none\n"
                'seat seat0 fallback true\nseat seat0 attach "*"\nfont pango:sans 10\n'
            ),
            self.config_dir / "xdg-desktop-portal/portals.conf": (
                "[preferred]\ndefault=none\n"
                "org.freedesktop.impl.portal.ScreenCast=wlr\n"
                "org.freedesktop.impl.portal.Screenshot=wlr\n"
                "org.freedesktop.impl.portal.Access=gtk\n"
            ),
            self.config_dir / "xdg-desktop-portal-wlr/config": (
                f"[screencast]\noutput_name={config.output_name}\nmax_fps={config.portal_max_fps}\nchooser_type=none\n"
            ),
            self.config_dir / "wireplumber/wireplumber.conf.d/10-agent-isolation.conf": (
                "wireplumber.profiles = {\n  main = {\n"
                "    hardware.audio = disabled\n    hardware.bluetooth = disabled\n"
                "    hardware.video-capture = disabled\n  }\n}\n"
            ),
            self.dbus_config: (
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE busconfig SYSTEM "busconfig.dtd">\n<busconfig>\n  <type>session</type>\n'
                f"  <keep_umask/>\n  <listen>unix:path={bus}</listen>\n  <auth>EXTERNAL</auth>\n"
                f"  <servicedir>{portal_dir}</servicedir>\n"
                '  <policy context="default">\n    <allow send_destination="*" eavesdrop="true"/>\n'
                '    <allow eavesdrop="true"/>\n    <allow own="*"/>\n  </policy>\n'
                '  <apparmor mode="disabled"/>\n</busconfig>\n'
            ),
        }

    def _mount_browser(self, environment: dict[str, str]) -> None:
        golden = self.config.vivaldi_golden_profile
        if not (golden / ".agent-desktop-ready").is_file():
            raise AgentDesktopError(f"golden Vivaldi profile is not ready: {golden}", "golden_profile_unavailable")
        self._spawn(
            "browser-overlay",
            [
                self.config.commands.fuse_overlayfs,
                "-f",
                "-o",
                f"lowerdir={golden},upperdir={self.browser_upper},workdir={self.browser_work}",
                str(self.browser),
            ],
            environment,
        )
        self._wait(
            lambda: is_mount(self.browser) or (self.browser / ".fake-overlay").is_file(),
            "browser profile overlay",
        )
        if not (self.browser / ".agent-desktop-ready").is_file():
            raise AgentDesktopError("browser overlay does not expose the golden profile", "browser_overlay_failed")
        remove_tree(self.browser / "Crash Reports")
        try:
            self._update_json(self.browser / "Default/Preferences", self._normalize_preferences)
            self._update_json(self.browser / "Local State", self._normalize_local_state)
        except (OSError, ValueError, TypeError) as error:
            raise AgentDesktopError(f"could not normalize browser clone: {error}", "browser_profile_failed") from error

    def _normalize_preferences(self, document: dict[str, object]) -> None:
        profile = document.setdefault("profile", {})
        download = document.setdefault("download", {})
        if not isinstance(profile, dict) or not isinstance(download, dict):
            raise TypeError("profile or download preference is not an object")
        profile["exit_type"] = "Normal"
        download["default_directory"] = str(self.root / "downloads")

    @staticmethod
    def _normalize_local_state(document: dict[str, object]) -> None:
        vivaldi = document.setdefault("vivaldi", {})
        if not isinstance(vivaldi, dict):
            raise TypeError("Vivaldi local state is not an object")
        # Match Vivaldi's non-consenting "Don't Ask Again" dismissal. The
        # disposable clone suppresses the stale prompt without opting into
        # crash uploads or changing the host/golden profiles.
        vivaldi["CrashReportingConsentDialogLastSeenTime"] = time.time() * 1000

    @staticmethod
    def _update_json(path: Path, update: Callable[[dict[str, object]], object]) -> None:
        document = json.loads(path.read_text()) if path.is_file() else {}
        if not isinstance(document, dict):
            raise TypeError(f"{path.name} is not an object")
        update(document)
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        temporary = path.with_name(f".{path.name}.agent-desktop.tmp")
        temporary.write_text(json.dumps(document, ensure_ascii=False, separators=(",", ":")))
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)

    def _environment(self) -> dict[str, str]:
        inherited = {
            "HOME",
            "LANG",
            "LANGUAGE",
            "LOCALE_ARCHIVE",
            "LOGNAME",
            "NIX_SSL_CERT_FILE",
            "PATH",
            "SHELL",
            "SSL_CERT_DIR",
            "SSL_CERT_FILE",
            "TERM",
            "TZ",
            "USER",
            "XCURSOR_SIZE",
            "XCURSOR_THEME",
        }
        environment = {name: value for name, value in os.environ.items() if name in inherited or name.startswith("LC_")}
        environment.update(
            {
                "XDG_RUNTIME_DIR": str(self.root),
                "XDG_CONFIG_HOME": str(self.config_dir),
                "XDG_CACHE_HOME": str(self.root / "cache"),
                "XDG_DATA_HOME": str(self.root / "data"),
                "XDG_STATE_HOME": str(self.root / "state"),
                "XDG_DOWNLOAD_DIR": str(self.root / "downloads"),
                "XDG_CURRENT_DESKTOP": "sway",
                "XDG_SESSION_DESKTOP": "sway",
                "XDG_SESSION_TYPE": "wayland",
                "WLR_BACKENDS": "headless",
                "WLR_RENDERER": "pixman",
                "WLR_LIBINPUT_NO_DEVICES": "1",
                "WLR_HEADLESS_OUTPUTS": "1",
                "PIPEWIRE_RUNTIME_DIR": str(self.root),
                "CUA_DRIVER_RS_ENABLE_WAYLAND": "1",
                "CUA_DRIVER_RS_TELEMETRY_ENABLED": "false",
                "NO_AT_BRIDGE": "0",
                "GTK_A11Y": "atspi",
                "GSETTINGS_BACKEND": "memory",
                "PYTHONUNBUFFERED": "1",
            }
        )
        if self.config.xdg_data_dirs:
            environment["XDG_DATA_DIRS"] = ":".join(map(str, self.config.xdg_data_dirs))
        return environment

    def _start_control(self) -> None:
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            listener.bind(str(self.control_socket))
            os.chmod(self.control_socket, 0o600)
            listener.listen(8)
            listener.setblocking(False)
        except OSError:
            listener.close()
            raise
        self.listener = listener

    def _accept_control(self, environment: dict[str, str]) -> None:
        if self.listener is None:
            return
        while True:
            try:
                connection, _ = self.listener.accept()
            except BlockingIOError:
                return
            with connection:
                connection.settimeout(2)
                self._handle_control(connection, environment)

    def _handle_control(self, connection: socket.socket, environment: dict[str, str]) -> None:
        try:
            arguments = self._request(json.loads(_read_frame(connection)))
            self.application_sequence += 1
            name = re.sub(r"[^A-Za-z0-9_.-]+", "-", Path(arguments[0]).name)[:48] or "app"
            process = self._spawn(
                f"application:{name}",
                arguments,
                environment,
                critical=False,
                log_name=f"app-{self.application_sequence:04d}-{name}",
            )
        except (AgentDesktopError, OSError, ValueError, TypeError) as error:
            response: dict[str, object] = {
                "ok": False,
                "code": "launch_failed",
                "message": str(error),
            }
        else:
            self._publish(State.ACTIVE)
            response = {"ok": True, "pid": process.pid, "arguments": arguments}
        try:
            connection.sendall(json.dumps(response, separators=(",", ":")).encode() + b"\n")
        except OSError:
            pass

    @staticmethod
    def _request(document: object) -> list[str]:
        if not isinstance(document, dict) or set(document) != {
            "version",
            "operation",
            "arguments",
        }:
            raise ValueError("invalid control request")
        if type(document["version"]) is not int or document["version"] != 1 or document["operation"] != "launch":
            raise ValueError("unsupported control request")
        arguments = document["arguments"]
        if not isinstance(arguments, list) or not 1 <= len(arguments) <= _MAX_ARGUMENTS:
            raise ValueError(f"arguments must contain 1-{_MAX_ARGUMENTS} strings")
        if any(type(value) is not str or not value or "\0" in value for value in arguments):
            raise ValueError("arguments must be non-empty strings without NULs")
        if sum(len(value.encode()) for value in arguments) > _MAX_ARGUMENT_BYTES:
            raise ValueError("arguments are too large")
        return arguments

    def _monitor(self, environment: dict[str, str]) -> None:
        next_health = time.monotonic() + self.config.health_interval_seconds
        while not self.stopping:
            self._accept_control(environment)
            self._reap()
            if time.monotonic() >= next_health:
                self._health(environment)
                next_health = time.monotonic() + self.config.health_interval_seconds
            time.sleep(0.2)

    def _health(self, environment: dict[str, str]) -> None:
        if self.listener is None or not self.control_socket.is_socket():
            raise AgentDesktopError("application control endpoint disappeared", "health_check_failed")
        if (
            not (is_mount(self.browser) or (self.browser / ".fake-overlay").is_file())
            or not (self.browser / ".agent-desktop-ready").is_file()
        ):
            raise AgentDesktopError("browser overlay disappeared", "health_check_failed")
        if not self._name_owned(self.dbus_address, "org.freedesktop.secrets", environment):
            raise AgentDesktopError("shared Secret Service disappeared", "health_check_failed")
        if not self.vnc_socket.exists():
            raise AgentDesktopError("WayVNC WebSocket disappeared", "health_check_failed")
        self._command(
            [self.config.commands.swaymsg, "-t", "get_outputs", "-r"],
            environment,
            timeout=5,
        )
        if not self._pipewire_ready(environment):
            raise AgentDesktopError("WirePlumber disappeared", "health_check_failed")
        for interface in (
            "org.freedesktop.portal.ScreenCast",
            "org.freedesktop.portal.Screenshot",
        ):
            self._command(self._portal_version(interface), environment, timeout=5)
        self._command(
            [self.config.commands.cua, "status", "--socket", str(self.cua_socket)],
            environment,
            timeout=5,
        )

    def _spawn(
        self,
        name: str,
        arguments: Sequence[str],
        environment: dict[str, str],
        *,
        critical: bool = True,
        log_name: str | None = None,
    ) -> subprocess.Popen[str]:
        log = (self.logs / f"{log_name or name}.log").open("a", encoding="utf-8")
        try:
            process = subprocess.Popen(
                arguments,
                env=environment,
                cwd=environment.get("HOME", "/") if Path(environment.get("HOME", "/")).is_dir() else "/",
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
            )
        except OSError as error:
            log.close()
            raise AgentDesktopError(f"could not start {name}: {error}", "child_start_failed") from error
        self.children.append(Child(name, process, log, critical))
        return process

    def _reap(self) -> None:
        application_exited = False
        for child in list(self.children):
            status = child.process.poll()
            if status is None:
                continue
            if child.critical:
                raise AgentDesktopError(
                    f"{child.name} exited unexpectedly with status {status}",
                    "child_exited",
                )
            child.log.close()
            self.children.remove(child)
            application_exited = True
        if application_exited and not any(not child.critical for child in self.children):
            self._publish(State.READY)

    def _ensure_running(self, label: str) -> None:
        for child in self.children:
            if (status := child.process.poll()) is not None:
                raise AgentDesktopError(
                    f"{child.name} exited while waiting for {label} (status {status})",
                    "child_exited",
                )

    def _wait(self, predicate: Callable[[], bool], label: str) -> None:
        while time.monotonic() < self.deadline:
            if self.stopping:
                raise StopRequested
            if predicate():
                return
            self._ensure_running(label)
            time.sleep(0.05)
        raise AgentDesktopError(f"timed out waiting for {label}", "readiness_timeout")

    def _wait_glob(self, pattern: str, label: str) -> str:
        found: str | None = None

        def discover() -> bool:
            nonlocal found
            candidates = sorted(path.name for path in self.root.glob(pattern) if not path.name.endswith(".lock"))
            found = candidates[0] if candidates else None
            return found is not None

        self._wait(discover, label)
        assert found is not None
        return found

    def _wait_command(self, arguments: list[str], environment: dict[str, str], label: str) -> None:
        self._wait(
            lambda: self._command(arguments, environment, check=False).returncode == 0,
            label,
        )

    def _wait_name(self, address: str, name: str, environment: dict[str, str], label: str) -> None:
        self._wait(lambda: self._name_owned(address, name, environment), label)

    def _name_owned(self, address: str, name: str, environment: dict[str, str]) -> bool:
        result = self._command(
            self._busctl(address, "--no-pager", "--no-legend", "list"),
            environment,
            check=False,
            timeout=5,
        )
        return result.returncode == 0 and any(
            len(fields) >= 2 and fields[0] == name and fields[1].isdigit()
            for fields in (line.split() for line in result.stdout.splitlines())
        )

    def _pipewire_ready(self, environment: dict[str, str]) -> bool:
        result = self._command([self.config.commands.pw_dump], environment, check=False, timeout=5)
        return result.returncode == 0 and "WirePlumber" in result.stdout

    def _portal_version(self, interface: str) -> list[str]:
        return self._busctl(
            self.dbus_address,
            "get-property",
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            interface,
            "version",
        )

    def _busctl(self, address: str, *arguments: str) -> list[str]:
        return [self.config.commands.busctl, f"--address={address}", *arguments]

    @staticmethod
    def _command(
        arguments: Sequence[str],
        environment: dict[str, str],
        *,
        check: bool = True,
        timeout: float = 10,
    ) -> subprocess.CompletedProcess[str]:
        return run(arguments, check=check, timeout=timeout, environment=environment)

    def _shutdown(self) -> None:
        if self.listener is not None:
            self.listener.close()
            self.listener = None
        self.control_socket.unlink(missing_ok=True)
        overlay = [child for child in self.children if child.name == "browser-overlay"]
        self._stop_children([child for child in self.children if child.name != "browser-overlay"])
        try:
            cleanup_session(self.config, self.id)
        finally:
            self._stop_children(overlay)
            self.children.clear()
            if not is_mount(self.browser):
                remove_tree(self.root)
        if self.stopping:
            self._publish(State.STOPPED, stopped_at=time.time())

    def _stop_children(self, children: list[Child]) -> None:
        for child in reversed(children):
            if child.process.poll() is None:
                with contextlib.suppress(OSError):
                    child.process.terminate()
        deadline = time.monotonic() + self.config.stop_timeout_seconds
        for child in reversed(children):
            try:
                child.process.wait(timeout=max(0.01, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                with contextlib.suppress(OSError):
                    child.process.kill()
                child.process.wait()
            child.log.close()

    def _publish(
        self,
        state: State,
        *,
        message: str | None = None,
        ready_at: float | None = None,
        stopped_at: float | None = None,
    ) -> None:
        path = self.config.state_path(self.id)
        previous: Session | None = None
        if path.exists():
            try:
                previous = read_session(self.config, path)
            except AgentDesktopError:
                pass
        if previous is not None and previous.state == State.STOPPING and state.launchable:
            return
        session = Session(
            id=self.id,
            agent_id=self.agent_id,
            unit=unit_name(self.id),
            state=state,
            created_at=previous.created_at if previous else self.started_at,
            updated_at=time.time(),
            runtime_dir=self.root,
            wayland_display=self.wayland_display,
            sway_socket=self.sway_socket,
            dbus_address=self.dbus_address if self.bus_socket.exists() else None,
            at_spi_bus_address=self.at_spi_address,
            cua_socket=self.cua_socket if self.cua_socket.exists() else None,
            vnc_socket=self.vnc_socket if self.vnc_socket.exists() else None,
            control_socket=self.control_socket if self.listener is not None else None,
            browser_profile=self.browser if (self.browser / ".agent-desktop-ready").is_file() else None,
            ready_at=ready_at or (previous.ready_at if previous else None),
            stopped_at=stopped_at,
            message=message,
        )
        write_json(path, session)

    def _log_tails(self) -> None:
        for path in sorted(self.logs.glob("*.log")):
            try:
                lines = path.read_text(errors="replace").splitlines()[-30:]
            except OSError:
                continue
            if lines:
                _LOG.error("%s tail:\n%s", path.name, "\n".join(lines))


def _read_frame(connection: socket.socket) -> bytes:
    payload = bytearray()
    while b"\n" not in payload:
        chunk = connection.recv(4096)
        if not chunk:
            raise ValueError("control request ended before a newline")
        payload.extend(chunk)
        if len(payload) > _MAX_FRAME:
            raise ValueError("control request is too large")
    line, remainder = bytes(payload).split(b"\n", 1)
    if remainder:
        raise ValueError("control request contains trailing data")
    return line


def _sd_notify(message: str) -> None:
    if not (address := os.getenv("NOTIFY_SOCKET")):
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
    """Run one private desktop inside its owning systemd unit."""
    logging.basicConfig(level=getattr(logging, log_level), format="%(levelname)s %(message)s")
    try:
        validate_id(session_id, "session ID")
        validate_id(agent_id, "agent ID")
        runtime = SessionRuntime(load_config(config_path), session_id, agent_id)
        signal.signal(signal.SIGTERM, runtime.request_stop)
        signal.signal(signal.SIGINT, runtime.request_stop)
        runtime.serve()
    except (AgentDesktopError, OSError, ValueError) as error:
        raise click.ClickException(str(error)) from error


def main() -> None:
    command(prog_name="agent-desktop-session")


@click.command()
@click.option("--config", "config_path", required=True, type=click.Path(path_type=Path))
@click.option("--session-id", required=True)
def cleanup_command(config_path: Path, session_id: str) -> None:
    """Reclaim a browser overlay after its session unit exits."""
    try:
        cleanup_session(load_config(config_path), validate_id(session_id, "session ID"))
    except (AgentDesktopError, OSError, ValueError) as error:
        raise click.ClickException(str(error)) from error


def cleanup_main() -> None:
    cleanup_command(prog_name="agent-desktop-cleanup")


if __name__ == "__main__":
    main()
