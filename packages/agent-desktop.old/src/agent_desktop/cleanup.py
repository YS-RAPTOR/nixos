from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import click

from .errors import AgentDesktopError
from .models import Config, load_config, validate_id


def cleanup(config: Config, session_id: str) -> None:
    validate_id(session_id, "session ID")
    profile = config.runtime_dir(session_id) / "browser-profile"
    try:
        subprocess.run(
            [config.commands.fusermount, "-u", "-z", str(profile)],
            check=False,
            capture_output=True,
            timeout=config.stop_timeout_seconds,
        )
    except (OSError, subprocess.SubprocessError):
        pass
    shutil.rmtree(config.browser_overlay_dir(session_id), ignore_errors=True)


@click.command()
@click.option("--config", "config_path", required=True, type=click.Path(path_type=Path))
@click.option("--session-id", required=True)
def command(config_path: Path, session_id: str) -> None:
    """Reclaim browser-overlay state after a session unit exits."""
    try:
        cleanup(load_config(config_path), session_id)
    except (AgentDesktopError, OSError, ValueError) as error:
        raise click.ClickException(str(error)) from error


def main() -> None:
    command(prog_name="agent-desktop-cleanup")
