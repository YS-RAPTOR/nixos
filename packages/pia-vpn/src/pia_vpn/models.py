from __future__ import annotations

import base64
import binascii
import os
import re
from enum import StrEnum
from ipaddress import IPv4Address, IPv4Interface
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from .errors import PiaVpnError

_NAME = re.compile(r"^[A-Za-z0-9_.-]+$")


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class ExternalModel(BaseModel):
    model_config = ConfigDict(extra="ignore", frozen=True)


class Config(StrictModel):
    default_region: str
    auto_start: bool = True
    kill_switch: bool = True
    allow_lan: bool = True
    interface: str = "pia"
    runtime_dir: Path = Path("/run/pia-wireguard")
    state_dir: Path = Path("/var/lib/pia-wireguard")
    socket_group: str | None = None
    credential_path: Path = Path("/var/lib/pia-wireguard/credentials.cred")
    credential_name: str = "pia-auth"
    controller_unit: str | None = None
    ca_certificate: Path | None = None
    retry_initial: float = Field(default=2, gt=0)
    retry_max: float = Field(default=120, gt=0)
    health_interval: float = Field(default=20, gt=0)
    handshake_max_age: float = Field(default=180, gt=0)
    command_timeout: float = Field(default=30, gt=0)

    @field_validator("default_region", "interface", "credential_name")
    @classmethod
    def safe_name(cls, value: str) -> str:
        if not _NAME.fullmatch(value):
            raise ValueError(
                "must contain only letters, digits, dots, underscores, or hyphens"
            )
        return value

    @model_validator(mode="after")
    def valid_ranges(self) -> Config:
        if self.retry_max < self.retry_initial:
            raise ValueError("retry_max must not be smaller than retry_initial")
        if self.controller_unit and not _NAME.fullmatch(self.controller_unit):
            raise ValueError("controller_unit must be a plain systemd unit name")
        return self

    @property
    def socket_path(self) -> Path:
        return self.runtime_dir / "control.sock"

    @property
    def status_path(self) -> Path:
        return self.runtime_dir / "status.json"

    @property
    def wireguard_config_path(self) -> Path:
        return self.runtime_dir / f"{self.interface}.conf"

    @property
    def preferences_path(self) -> Path:
        return self.state_dir / "preferences.json"

    @property
    def regions_path(self) -> Path:
        return self.state_dir / "regions.json"


def load_config(path: Path | None = None) -> Config:
    selected = path or Path(
        os.environ.get("PIA_VPN_CONFIG", "/etc/pia-vpn/config.json")
    )
    try:
        return Config.model_validate_json(selected.read_bytes())
    except OSError as error:
        raise PiaVpnError(
            f"cannot read configuration {selected}: {error}", "config_error"
        ) from error
    except ValueError as error:
        raise PiaVpnError(
            f"invalid configuration {selected}: {error}", "config_error"
        ) from error


class Credentials(StrictModel):
    username: str
    password: str

    @field_validator("username")
    @classmethod
    def valid_username(cls, value: str) -> str:
        if not value.startswith("p"):
            raise ValueError("PIA username must start with 'p'")
        return value

    @field_validator("username", "password")
    @classmethod
    def no_line_breaks(cls, value: str) -> str:
        if not value or any(character in value for character in "\x00\r\n"):
            raise ValueError("must be non-empty and contain no line breaks")
        return value


class Endpoint(ExternalModel):
    ip: IPv4Address
    cn: str


class Servers(ExternalModel):
    wg: tuple[Endpoint, ...] = ()


class Region(ExternalModel):
    id: str
    name: str
    port_forward: bool = False
    geo: bool = False
    servers: Servers

    @field_validator("id")
    @classmethod
    def valid_id(cls, value: str) -> str:
        if not _NAME.fullmatch(value):
            raise ValueError("invalid region ID")
        return value

    def public(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "port_forward": self.port_forward,
            "geo": self.geo,
        }


class ServerList(ExternalModel):
    regions: tuple[Region, ...]

    @model_validator(mode="after")
    def usable(self) -> ServerList:
        ids = [region.id for region in self.regions]
        if not ids or len(ids) != len(set(ids)):
            raise ValueError("server list has no regions or duplicate IDs")
        return self

    def region(self, region_id: str) -> Region:
        for region in self.regions:
            if region.id == region_id and region.servers.wg:
                return region
        raise PiaVpnError(
            f"unknown or unavailable PIA region: {region_id}", "unknown_region"
        )


class Registration(ExternalModel):
    status: Literal["OK"]
    peer_ip: IPv4Interface
    server_ip: IPv4Address
    server_port: int = Field(gt=0, le=65535)
    server_vip: IPv4Address
    server_key: str
    dns_servers: tuple[IPv4Address, ...] = Field(min_length=1)

    @field_validator("server_key")
    @classmethod
    def valid_key(cls, value: str) -> str:
        try:
            decoded = base64.b64decode(value, validate=True)
        except (ValueError, binascii.Error) as error:
            raise ValueError("invalid WireGuard server key") from error
        if len(decoded) != 32:
            raise ValueError("invalid WireGuard server key")
        return value


class Preferences(StrictModel):
    region: str | None = None


class ConnectionState(StrEnum):
    SETUP_REQUIRED = "setup-required"
    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    BLOCKED = "blocked"


class Status(StrictModel):
    state: ConnectionState
    desired: bool
    default_region: str
    override_region: str | None = None
    effective_region: str
    effective_region_name: str | None = None
    interface: str
    message: str | None = None
    endpoint: str | None = None
    connected_at: float | None = None
    handshake_age: float | None = None

    def public(self) -> dict[str, Any]:
        return self.model_dump(mode="json")
