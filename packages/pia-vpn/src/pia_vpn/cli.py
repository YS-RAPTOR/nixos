from __future__ import annotations

import asyncio
import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import click
from pydantic import ValidationError

from .control import request
from .errors import PiaVpnError
from .models import Config, Status, load_config
from .storage import read_model


@dataclass
class Context:
    config: Config
    config_path: Path | None


def call(context: Context, command: str, **params: Any) -> Any:
    return asyncio.run(request(context.config, command, **params))


@click.group()
@click.option(
    "--config",
    "config_path",
    type=click.Path(path_type=Path),
    help="configuration JSON",
)
@click.pass_context
def command(context: click.Context, config_path: Path | None) -> None:
    """Control Private Internet Access WireGuard."""
    context.obj = Context(load_config(config_path), config_path)


@command.command()
@click.option("--waybar", is_flag=True, help="print a Waybar JSON object")
@click.pass_obj
def status(context: Context, waybar: bool) -> None:
    """Show connection status without contacting PIA."""
    value = read_model(context.config.status_path, Status)
    click.echo(json.dumps(_waybar(value)) if waybar else _status_text(value))


@command.command()
@click.pass_obj
def connect(context: Context) -> None:
    """Connect using the selected location."""
    call(context, "connect")
    click.echo("PIA connection requested")


@command.command()
@click.pass_obj
def disconnect(context: Context) -> None:
    """Disconnect intentionally and permit direct internet."""
    call(context, "disconnect")
    click.echo("PIA disconnected")


@command.command()
@click.pass_obj
def toggle(context: Context) -> None:
    """Toggle the desired connection state."""
    value = call(context, "toggle")
    click.echo(value["state"])


@command.command()
@click.option("--json", "as_json", is_flag=True, help="print machine-readable JSON")
@click.pass_obj
def locations(context: Context, as_json: bool) -> None:
    """List cached PIA locations."""
    values = call(context, "locations")
    if as_json:
        click.echo(json.dumps(values, sort_keys=True))
    else:
        for value in values:
            click.echo(f"{value['id']:<24} {value['name']}")


@command.group()
def location() -> None:
    """Inspect or change the selected location."""


@location.command("current")
@click.pass_obj
def location_current(context: Context) -> None:
    value = call(context, "location.current")
    click.echo(f"configured default: {value['default_region']}")
    click.echo(f"runtime override: {value['override_region'] or 'none'}")
    click.echo(
        f"effective: {value['effective_region_name'] or value['effective_region']} ({value['effective_region']})"
    )


@location.command("set")
@click.argument("region_id")
@click.pass_obj
def location_set(context: Context, region_id: str) -> None:
    value = call(context, "location.set", region=region_id)
    click.echo(f"PIA location set to {value['effective_region']}")


@location.command("reset")
@click.pass_obj
def location_reset(context: Context) -> None:
    value = call(context, "location.reset")
    click.echo(f"PIA location reset to configured default {value['effective_region']}")


@command.group()
def credentials() -> None:
    """Manage the TPM2-encrypted PIA credential."""


@credentials.command("set")
@click.pass_obj
def credentials_set(context: Context) -> None:
    username = click.prompt("PIA username")
    password = click.prompt("PIA password", hide_input=True, confirmation_prompt=True)
    payload = json.dumps({"username": username, "password": password}).encode()
    _helper(context, "set", payload)
    call(context, "credentials.changed")
    click.echo("PIA credentials stored")


@credentials.command("clear")
@click.option("--yes", is_flag=True, help="do not prompt for confirmation")
@click.pass_obj
def credentials_clear(context: Context, yes: bool) -> None:
    if not yes and not click.confirm("Disconnect and remove the PIA credential?"):
        raise click.Abort()
    call(context, "credentials.clearing")
    _helper(context, "clear")
    click.echo("PIA credentials removed")


def _helper(context: Context, action: str, payload: bytes | None = None) -> None:
    helper = os.environ.get("PIA_VPN_CREDENTIAL_HELPER", "pia-vpn-credential-helper")
    arguments = [helper, action]
    if context.config_path:
        arguments.extend(("--config", str(context.config_path)))
    if os.geteuid() != 0:
        arguments.insert(0, "pkexec")
    try:
        subprocess.run(arguments, input=payload, check=True)
    except (OSError, subprocess.SubprocessError) as error:
        raise PiaVpnError("credential helper failed", "credential_error") from error


def _status_text(value: Status) -> str:
    location_name = value.effective_region_name or value.effective_region
    lines = [
        f"state: {value.state}",
        f"desired: {'connected' if value.desired else 'disconnected'}",
        f"location: {location_name} ({value.effective_region})",
        f"configured default: {value.default_region}",
        f"interface: {value.interface}",
    ]
    if value.message:
        lines.append(f"message: {value.message}")
    if value.handshake_age is not None:
        lines.append(f"handshake age: {value.handshake_age:.0f}s")
    return "\n".join(lines)


def _waybar(value: Status) -> dict[str, Any]:
    icon = {
        "setup-required": "󰌾",
        "disconnected": "󰯄",
        "connecting": "󰔟",
        "connected": "󰒘",
        "blocked": "󰌾",
    }[value.state]
    location_name = value.effective_region_name or value.effective_region
    source = "override" if value.override_region else "configured default"
    tooltip = [
        f"PIA: {value.state}",
        f"Location: {location_name} ({source})",
        f"Configured default: {value.default_region}",
        f"Interface: {value.interface}",
    ]
    if value.handshake_age is not None:
        tooltip.append(f"Handshake: {value.handshake_age:.0f}s ago")
    if value.message:
        tooltip.append(value.message)
    tooltip.extend(("Left click: connect/disconnect", "Right click: select location"))
    return {
        "text": icon,
        "class": value.state,
        "alt": value.state,
        "tooltip": "\n".join(tooltip),
    }


def main() -> None:
    try:
        command(prog_name="pia-vpn", standalone_mode=False)
    except click.ClickException as error:
        error.show()
        raise SystemExit(error.exit_code) from error
    except click.Abort as error:
        raise SystemExit(1) from error
    except (PiaVpnError, ValidationError) as error:
        failure = click.ClickException(str(error))
        failure.show()
        raise SystemExit(1) from error
