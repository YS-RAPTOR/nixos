from __future__ import annotations

import fcntl
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
from collections.abc import Iterator
from contextlib import contextmanager
from enum import StrEnum
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

_SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")


class AgentDesktopError(Exception):
    def __init__(self, message: str, code: str = "agent_desktop_error") -> None:
        super().__init__(message)
        self.code = code


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class Commands(StrictModel):
    dbus: str = "dbus-daemon"
    sway: str = "sway"
    swaymsg: str = "swaymsg"
    at_spi_launcher: str = "at-spi-bus-launcher"
    at_spi_registry: str = "at-spi2-registryd"
    pipewire: str = "pipewire"
    pw_dump: str = "pw-dump"
    wireplumber: str = "wireplumber"
    portal_wlr: str = "xdg-desktop-portal-wlr"
    portal_gtk: str = "xdg-desktop-portal-gtk"
    portal: str = "xdg-desktop-portal"
    busctl: str = "busctl"
    cua: str = "cua-driver"
    systemctl: str = "systemctl"
    systemd_run: str = "systemd-run"
    session: str = "agent-desktop-session"
    wayvnc: str = "wayvnc"
    vivaldi: str = "vivaldi"
    xdg_open: str = "xdg-open"
    fuse_overlayfs: str = "fuse-overlayfs"
    fusermount: str = "fusermount3"
    cleanup: str = "agent-desktop-cleanup"
    secret_bridge: str = "agent-desktop-secret-bridge"

    @field_validator("*")
    @classmethod
    def valid_command(cls, value: str) -> str:
        if not value or "\0" in value:
            raise ValueError("command paths must be non-empty")
        return value


def _runtime_root() -> Path:
    return Path(os.getenv("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "agent-desktop"


def _state_root() -> Path:
    return Path(os.getenv("XDG_STATE_HOME", Path.home() / ".local/state")) / "agent-desktop"


class Config(StrictModel):
    runtime_root: Path = Field(default_factory=_runtime_root)
    state_root: Path = Field(default_factory=_state_root)
    portal_service_dir: Path
    xdg_data_dirs: tuple[Path, ...] = ()
    commands: Commands = Commands()
    output_name: str = "HEADLESS-1"
    output_width: int = Field(1280, ge=320, le=7680)
    output_height: int = Field(720, ge=200, le=4320)
    output_refresh_hz: int = Field(60, ge=1, le=240)
    portal_max_fps: int = Field(15, ge=1, le=240)
    vnc_max_fps: int = Field(30, ge=1, le=240)
    max_sessions: int | None = Field(None, ge=1)
    create_timeout_seconds: float = Field(30, gt=0, le=300)
    stop_timeout_seconds: float = Field(15, gt=0, le=120)
    health_interval_seconds: float = Field(10, gt=0, le=300)
    runtime_limit_seconds: int = Field(14400, ge=60)
    viewer_port: int = Field(6080, ge=1024, le=65535)
    viewer_unit: str = "agent-desktop-viewer.service"
    host_dbus_address: str = Field(default_factory=lambda: f"unix:path=/run/user/{os.getuid()}/bus")
    novnc_web_root: Path = Path("/usr/share/webapps/novnc")
    vivaldi_golden_profile: Path = Field(default_factory=lambda: _state_root() / "browser-golden/vivaldi")

    @field_validator("output_name")
    @classmethod
    def valid_output(cls, value: str) -> str:
        return validate_id(value, "output name")

    @field_validator("host_dbus_address")
    @classmethod
    def valid_bus(cls, value: str) -> str:
        if not value.startswith("unix:") or "\0" in value:
            raise ValueError("host_dbus_address must be a Unix D-Bus address")
        return value

    @field_validator("viewer_unit")
    @classmethod
    def valid_unit(cls, value: str) -> str:
        if not value.endswith(".service") or "/" in value or "\0" in value:
            raise ValueError("viewer_unit must be a systemd service name")
        return value

    @model_validator(mode="after")
    def separate_roots(self) -> Config:
        if (
            self.runtime_root == self.state_root
            or self.runtime_root in self.state_root.parents
            or self.state_root in self.runtime_root.parents
        ):
            raise ValueError("runtime_root and state_root must be separate trees")
        return self

    def runtime_dir(self, session_id: str) -> Path:
        return self.runtime_root / validate_id(session_id, "session ID")

    def browser_overlay_dir(self, session_id: str) -> Path:
        return self.state_root / "browser-overlays" / validate_id(session_id, "session ID")

    def state_path(self, session_id: str) -> Path:
        return self.state_root / "sessions" / f"{validate_id(session_id, 'session ID')}.json"

    @property
    def viewer_runtime_dir(self) -> Path:
        return self.runtime_root.parent / "agent-desktop-viewer"

    @property
    def viewer_token_path(self) -> Path:
        return self.viewer_runtime_dir / "token"


class State(StrEnum):
    STARTING = "starting"
    READY = "ready"
    ACTIVE = "active"
    STOPPING = "stopping"
    FAILED = "failed"
    STOPPED = "stopped"

    @property
    def consumes_capacity(self) -> bool:
        return self in {State.STARTING, State.READY, State.ACTIVE, State.STOPPING}

    @property
    def launchable(self) -> bool:
        return self in {State.READY, State.ACTIVE}


class Session(StrictModel):
    id: str
    agent_id: str
    unit: str
    state: State
    created_at: float
    updated_at: float
    runtime_dir: Path
    wayland_display: str | None = None
    sway_socket: Path | None = None
    dbus_address: str | None = None
    at_spi_bus_address: str | None = None
    cua_socket: Path | None = None
    vnc_socket: Path | None = None
    control_socket: Path | None = None
    browser_profile: Path | None = None
    ready_at: float | None = None
    stopped_at: float | None = None
    message: str | None = None

    @field_validator("id")
    @classmethod
    def valid_session_id(cls, value: str) -> str:
        return validate_id(value, "session ID")

    @field_validator("agent_id")
    @classmethod
    def valid_agent_id(cls, value: str) -> str:
        return validate_id(value, "agent ID")

    def public(self) -> dict[str, Any]:
        return self.model_dump(mode="json")


class Launch(StrictModel):
    pid: int = Field(gt=0, strict=True)
    arguments: tuple[str, ...]

    def public(self) -> dict[str, Any]:
        return self.model_dump(mode="json")


def validate_id(value: str, label: str) -> str:
    if not _SAFE_ID.fullmatch(value):
        raise ValueError(f"{label} must be 1-64 characters using letters, digits, dots, underscores, or hyphens")
    return value


def unit_name(session_id: str) -> str:
    return f"agent-desktop-{validate_id(session_id, 'session ID')}.service"


def default_config_path() -> Path:
    if override := os.getenv("AGENT_DESKTOP_CONFIG"):
        return Path(override)
    return Path(os.getenv("XDG_CONFIG_HOME", Path.home() / ".config")) / "agent-desktop/config.json"


def load_config(path: Path | None = None) -> Config:
    selected = path or default_config_path()
    try:
        return Config.model_validate_json(selected.read_bytes())
    except (OSError, ValueError) as error:
        raise AgentDesktopError(f"cannot load configuration {selected}: {error}", "config_error") from error


def validate_session(config: Config, path: Path, session: Session) -> Session:
    root = config.runtime_dir(session.id)
    exact = {
        "unit": unit_name(session.id),
        "runtime_dir": root,
        "dbus_address": f"unix:path={root / 'bus'}",
        "cua_socket": root / "cua.sock",
        "vnc_socket": root / "wayvnc.sock",
        "control_socket": root / "control.sock",
        "browser_profile": root / "browser-profile",
    }
    if path != config.state_path(session.id) or any(
        getattr(session, name) not in {None, expected} for name, expected in exact.items()
    ):
        raise AgentDesktopError(f"session state has invalid ownership: {path}", "state_error")
    if session.sway_socket is not None and not (
        session.sway_socket.parent == root and re.fullmatch(r"sway-ipc\..+\.sock", session.sway_socket.name)
    ):
        raise AgentDesktopError(f"session state has invalid ownership: {path}", "state_error")
    if session.wayland_display is not None and not re.fullmatch(r"wayland-\d+", session.wayland_display):
        raise AgentDesktopError(f"session state has invalid ownership: {path}", "state_error")
    if session.at_spi_bus_address is not None:
        address_path = Path(session.at_spi_bus_address.removeprefix("unix:path=").split(",", 1)[0])
        if not session.at_spi_bus_address.startswith("unix:path=") or address_path.parent != root / "at-spi":
            raise AgentDesktopError(f"session state has invalid ownership: {path}", "state_error")
    required = (
        "dbus_address",
        "cua_socket",
        "vnc_socket",
        "control_socket",
        "browser_profile",
        "wayland_display",
        "sway_socket",
        "at_spi_bus_address",
    )
    if session.state.launchable and any(getattr(session, name) is None for name in required):
        raise AgentDesktopError(f"ready session has incomplete endpoints: {path}", "state_error")
    return session


def read_session(config: Config, path: Path) -> Session:
    try:
        data = path.read_bytes()
    except FileNotFoundError:
        raise AgentDesktopError(f"session state is unavailable: {path.stem}", "session_not_found") from None
    except OSError as error:
        raise AgentDesktopError(f"cannot read state {path}: {error}", "state_error") from error
    if len(data) > 1024 * 1024:
        raise AgentDesktopError(f"state file is too large: {path}", "state_error")
    try:
        return validate_session(config, path, Session.model_validate_json(data))
    except AgentDesktopError:
        raise
    except ValueError as error:
        raise AgentDesktopError(f"invalid state {path}: {error}", "state_error") from error


def remove_tree(path: Path) -> None:
    if not path.exists() and not path.is_symlink():
        return

    def retry(function: Any, target: str, _error: Any) -> None:
        try:
            selected = Path(target)
            if not selected.is_symlink():
                os.chmod(selected, 0o700)
            os.chmod(selected.parent, 0o700)
            function(target)
        except FileNotFoundError:
            pass

    try:
        shutil.rmtree(path, onerror=retry)
    except FileNotFoundError:
        return
    except OSError as error:
        raise AgentDesktopError(f"could not remove temporary state {path}: {error}", "cleanup_failed") from error
    if path.exists() or path.is_symlink():
        raise AgentDesktopError(f"temporary state remains: {path}", "cleanup_failed")


def mount_points() -> tuple[Path, ...]:
    try:
        lines = Path("/proc/self/mountinfo").read_text().splitlines()
    except OSError as error:
        raise AgentDesktopError(f"could not inspect mounts: {error}", "mount_inspection_failed") from error
    points: list[Path] = []
    for line in lines:
        fields = line.split()
        if len(fields) >= 5:
            value = re.sub(r"\\([0-7]{3})", lambda match: chr(int(match.group(1), 8)), fields[4])
            points.append(Path(value))
    return tuple(points)


def is_mount(path: Path) -> bool:
    return path in mount_points()


def cleanup_session(config: Config, session_id: str) -> None:
    runtime = config.runtime_dir(session_id)
    detail = ""
    for _ in range(3):
        mounts = sorted(
            (path for path in mount_points() if path == runtime or runtime in path.parents),
            key=lambda path: len(path.parts),
            reverse=True,
        )
        if not mounts:
            break
        for mount in mounts:
            try:
                result = subprocess.run(
                    [config.commands.fusermount, "-u", "-z", str(mount)],
                    capture_output=True,
                    check=False,
                    text=True,
                    timeout=config.stop_timeout_seconds,
                )
            except (OSError, subprocess.SubprocessError) as error:
                detail = str(error)
            else:
                detail = result.stderr.strip() or result.stdout.strip()
        time.sleep(0.05)
    remaining = [path for path in mount_points() if path == runtime or runtime in path.parents]
    if remaining:
        targets = ", ".join(map(str, remaining))
        raise AgentDesktopError(
            f"could not unmount session filesystems: {targets}" + (f": {detail}" if detail else ""),
            "cleanup_failed",
        )
    remove_tree(config.browser_overlay_dir(session_id))


def write_json(path: Path, value: BaseModel | dict[str, Any] | list[Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    payload = value.model_dump(mode="json") if isinstance(value, BaseModel) else value
    data = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode() + b"\n"
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        Path(temporary).unlink(missing_ok=True)
        raise


@contextmanager
def state_lock(config: Config) -> Iterator[None]:
    config.state_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(config.state_root, 0o700)
    descriptor = os.open(config.state_root / ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)
