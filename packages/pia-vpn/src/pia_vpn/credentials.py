from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

import click
from pydantic import ValidationError

from .errors import PiaVpnError
from .models import Credentials, load_config


def _store(path: Path, data: bytes) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
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


@click.command()
@click.argument("action", type=click.Choice(["set", "clear"]))
@click.option(
    "--config",
    "config_path",
    type=click.Path(path_type=Path),
    help="configuration JSON",
)
def command(action: str, config_path: Path | None) -> None:
    """Privileged helper for the encrypted PIA credential."""
    config = load_config(config_path)
    try:
        if action == "clear":
            if config.controller_unit:
                subprocess.run(
                    ["systemctl", "stop", config.controller_unit], check=True
                )
            config.credential_path.unlink(missing_ok=True)
            return
        data = sys.stdin.buffer.read(1024 * 1024 + 1)
        if len(data) > 1024 * 1024:
            raise PiaVpnError("credential input exceeds 1 MiB", "invalid_credentials")
        credentials = Credentials.model_validate_json(data)
        payload = credentials.model_dump_json().encode()
        encrypted = subprocess.run(
            [
                "systemd-creds",
                "encrypt",
                "--with-key=tpm2",
                f"--name={config.credential_name}",
                "-",
                "-",
            ],
            input=payload,
            capture_output=True,
            check=True,
        ).stdout
        _store(config.credential_path, encrypted)
        if config.controller_unit:
            subprocess.run(["systemctl", "restart", config.controller_unit], check=True)
    except ValidationError as error:
        raise click.ClickException("invalid credential input") from error
    except (OSError, subprocess.SubprocessError, PiaVpnError) as error:
        raise click.ClickException(str(error)) from error


def main() -> None:
    command(prog_name="pia-vpn-credential-helper")
