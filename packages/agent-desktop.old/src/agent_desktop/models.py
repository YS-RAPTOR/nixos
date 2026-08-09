from __future__ import annotations

import os
import re
from enum import StrEnum
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from .errors import AgentDesktopError

_SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    def public(self) -> dict[str, object]:
        return self.model_dump(mode="json")


class CommandPaths(StrictModel):
    dbus_daemon: str = "dbus-daemon"
    sway: str = "sway"
    swaymsg: str = "swaymsg"
    at_spi_bus_launcher: str = "at-spi-bus-launcher"
    at_spi_registry: str = "at-spi2-registryd"
    pipewire: str = "pipewire"
    pw_dump: str = "pw-dump"
    wireplumber: str = "wireplumber"
    portal_wlr: str = "xdg-desktop-portal-wlr"
    portal_gtk: str = "xdg-desktop-portal-gtk"
    portal: str = "xdg-desktop-portal"
    busctl: str = "busctl"
    cua_driver: str = "cua-driver"
    systemctl: str = "systemctl"
    systemd_run: str = "systemd-run"
    wayvnc: str = "wayvnc"
    vivaldi: str = "vivaldi"
    xdg_open: str = "xdg-open"
    fuse_overlayfs: str = "fuse-overlayfs"
    fusermount: str = "fusermount3"
    secret_bridge: str = "agent-desktop-secret-bridge"

    @field_validator("*")
    @classmethod
    def command_is_not_empty(cls, value: str) -> str:
        if not value or "\x00" in value:
            raise ValueError("command paths must be non-empty")
        return value


def _default_runtime_root() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        runtime = f"/run/user/{os.getuid()}"
    return Path(runtime) / "agent-desktop"


def _default_state_root() -> Path:
    state = os.environ.get("XDG_STATE_HOME")
    if not state:
        state = str(Path.home() / ".local" / "state")
    return Path(state) / "agent-desktop"


class Config(StrictModel):
    runtime_root: Path = Field(default_factory=_default_runtime_root)
    state_root: Path = Field(default_factory=_default_state_root)
    portal_service_dir: Path
    xdg_data_dirs: tuple[Path, ...] = ()
    commands: CommandPaths = CommandPaths()
    output_name: str = "HEADLESS-1"
    output_width: int = Field(default=1280, ge=320, le=7680)
    output_height: int = Field(default=720, ge=200, le=4320)
    output_refresh_hz: int = Field(default=60, ge=1, le=240)
    portal_max_fps: int = Field(default=15, ge=1, le=240)
    vnc_max_fps: int = Field(default=30, ge=1, le=240)
    max_sessions: int = Field(default=4, ge=1, le=32)
    create_timeout_seconds: float = Field(default=30, gt=0, le=300)
    stop_timeout_seconds: float = Field(default=15, gt=0, le=120)
    health_interval_seconds: float = Field(default=10, gt=0, le=300)
    runtime_limit_seconds: int = Field(default=14400, ge=60)
    viewer_port: int = Field(default=6080, ge=1024, le=65535)
    viewer_unit: str = "agent-desktop-viewer.service"
    host_dbus_address: str = Field(
        default_factory=lambda: f"unix:path=/run/user/{os.getuid()}/bus"
    )
    novnc_web_root: Path = Path("/usr/share/webapps/novnc")
    browser_overlay_root: Path = Field(
        default_factory=lambda: _default_state_root() / "browser-overlays"
    )
    vivaldi_golden_profile: Path = Field(
        default_factory=lambda: _default_state_root() / "browser-golden" / "vivaldi"
    )
    enable_at_spi: bool = True
    enable_portals: bool = True
    enable_cua: bool = True
    enable_vnc: bool = True
    enable_browser_profile: bool = True
    enable_secret_service: bool = True

    @field_validator("output_name")
    @classmethod
    def safe_output_name(cls, value: str) -> str:
        if not _SAFE_ID.fullmatch(value):
            raise ValueError("output_name contains unsupported characters")
        return value

    @field_validator("host_dbus_address")
    @classmethod
    def valid_host_bus_address(cls, value: str) -> str:
        if not value.startswith("unix:") or "\x00" in value:
            raise ValueError("host_dbus_address must be a Unix D-Bus address")
        return value

    @field_validator("viewer_unit")
    @classmethod
    def safe_viewer_unit(cls, value: str) -> str:
        if not value.endswith(".service") or "/" in value or "\x00" in value:
            raise ValueError("viewer_unit must be a systemd service name")
        return value

    @model_validator(mode="after")
    def distinct_roots(self) -> Config:
        if (
            self.runtime_root == self.state_root
            or self.runtime_root in self.state_root.parents
            or self.state_root in self.runtime_root.parents
        ):
            raise ValueError("runtime_root and state_root must be separate trees")
        return self

    @property
    def sessions_state_dir(self) -> Path:
        return self.state_root / "sessions"

    @property
    def viewer_runtime_dir(self) -> Path:
        runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        return Path(runtime) / "agent-desktop-viewer"

    @property
    def viewer_token_path(self) -> Path:
        return self.viewer_runtime_dir / "token"

    def runtime_dir(self, session_id: str) -> Path:
        validate_id(session_id, "session ID")
        return self.runtime_root / session_id

    def browser_overlay_dir(self, session_id: str) -> Path:
        validate_id(session_id, "session ID")
        return self.browser_overlay_root / session_id

    def state_path(self, session_id: str) -> Path:
        validate_id(session_id, "session ID")
        return self.sessions_state_dir / f"{session_id}.json"


class SessionState(StrEnum):
    STARTING = "starting"
    READY = "ready"
    ACTIVE = "active"
    STOPPING = "stopping"
    FAILED = "failed"
    STOPPED = "stopped"

    @property
    def launchable(self) -> bool:
        return self in {SessionState.READY, SessionState.ACTIVE}

    @property
    def consumes_capacity(self) -> bool:
        return self == SessionState.STARTING or self.launchable

    @property
    def needs_reconciliation(self) -> bool:
        return self.consumes_capacity or self == SessionState.STOPPING


class Session(StrictModel):
    id: str
    agent_id: str
    unit: str
    state: SessionState
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
    def safe_session_id(cls, value: str) -> str:
        return validate_id(value, "session ID")

    @field_validator("agent_id")
    @classmethod
    def safe_agent_id(cls, value: str) -> str:
        return validate_id(value, "agent ID")


class LaunchResult(StrictModel):
    pid: int = Field(gt=0, strict=True)
    arguments: tuple[str, ...]


def validate_id(value: str, label: str) -> str:
    if not _SAFE_ID.fullmatch(value):
        raise ValueError(
            f"{label} must be 1-64 characters using letters, digits, dots, "
            "underscores, or hyphens"
        )
    return value


def default_config_path() -> Path:
    override = os.environ.get("AGENT_DESKTOP_CONFIG")
    if override:
        return Path(override)
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_home / "agent-desktop" / "config.json"


def load_config(path: Path | None = None) -> Config:
    selected = path or default_config_path()
    try:
        return Config.model_validate_json(selected.read_bytes())
    except OSError as error:
        raise AgentDesktopError(
            f"cannot read configuration {selected}: {error}", "config_error"
        ) from error
    except ValueError as error:
        raise AgentDesktopError(
            f"invalid configuration {selected}: {error}", "config_error"
        ) from error
