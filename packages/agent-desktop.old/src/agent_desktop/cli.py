from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import click
from pydantic import ValidationError

from .errors import AgentDesktopError
from .models import Config, LaunchResult, Session, default_config_path, load_config
from .system import SessionManager
from .viewer import ViewerClient


@dataclass
class Context:
    config: Config
    config_path: Path

    def manager(self) -> SessionManager:
        return SessionManager(self.config, self.config_path)


@click.group()
@click.option(
    "--config",
    "config_path",
    type=click.Path(path_type=Path),
    help="configuration JSON",
)
@click.pass_context
def command(context: click.Context, config_path: Path | None) -> None:
    """Create and control private computer-use desktops."""
    selected = config_path or default_config_path()
    context.obj = Context(load_config(selected), selected)


@command.command()
@click.argument("agent_id")
@click.option("--session-id", help="fixed session ID instead of generating one")
@click.option("--json", "as_json", is_flag=True, help="print machine-readable JSON")
@click.option("--view", "open_viewer", is_flag=True, help="open the session viewer")
@click.pass_obj
def create(
    context: Context,
    agent_id: str,
    session_id: str | None,
    as_json: bool,
    open_viewer: bool,
) -> None:
    """Create a desktop for AGENT_ID and wait until it is ready."""
    session = context.manager().create(agent_id, session_id)
    _print_session(session, as_json)
    if open_viewer:
        try:
            ViewerClient(context.config).open(session.id)
        except AgentDesktopError as error:
            click.echo(f"warning: {error}", err=True)


@command.command()
@click.argument("session_id")
@click.option("--json", "as_json", is_flag=True, help="print machine-readable JSON")
@click.pass_obj
def status(context: Context, session_id: str, as_json: bool) -> None:
    """Show one session's current lifecycle state."""
    _print_session(context.manager().status(session_id), as_json)


@command.command("list")
@click.option("--json", "as_json", is_flag=True, help="print machine-readable JSON")
@click.option("--all", "include_stopped", is_flag=True, help="include stopped sessions")
@click.pass_obj
def list_sessions(context: Context, as_json: bool, include_stopped: bool) -> None:
    """List known agent desktops."""
    sessions = context.manager().list()
    if not include_stopped:
        sessions = [session for session in sessions if session.state != "stopped"]
    if as_json:
        click.echo(
            json.dumps([session.public() for session in sessions], sort_keys=True)
        )
        return
    if not sessions:
        click.echo("No agent desktops")
        return
    for session in sessions:
        click.echo(f"{session.id:<64} {session.state:<9} agent={session.agent_id}")


@command.command("exec", context_settings={"ignore_unknown_options": True})
@click.argument("session_id")
@click.argument("arguments", nargs=-1, required=True, type=click.UNPROCESSED)
@click.option("--json", "as_json", is_flag=True, help="print machine-readable JSON")
@click.pass_obj
def exec_command(
    context: Context, session_id: str, arguments: tuple[str, ...], as_json: bool
) -> None:
    """Launch COMMAND inside SESSION_ID using: exec SESSION_ID -- COMMAND."""
    _print_launch(context.manager().launch(session_id, arguments), as_json)


@command.command()
@click.argument("session_id")
@click.argument("url", required=False, default="about:blank")
@click.option("--json", "as_json", is_flag=True, help="print machine-readable JSON")
@click.pass_obj
def browser(context: Context, session_id: str, url: str, as_json: bool) -> None:
    """Launch disposable-profile Vivaldi inside SESSION_ID."""
    _print_launch(context.manager().launch_browser(session_id, url), as_json)


@command.command()
@click.argument("session_id")
@click.option("--json", "as_json", is_flag=True, help="print machine-readable JSON")
@click.pass_obj
def destroy(context: Context, session_id: str, as_json: bool) -> None:
    """Stop SESSION_ID and remove its temporary desktop state."""
    _print_session(context.manager().destroy(session_id), as_json)


@command.command()
@click.argument("session_id", required=False)
@click.option("--print", "print_url", is_flag=True, help="print instead of opening")
@click.pass_obj
def view(context: Context, session_id: str | None, print_url: bool) -> None:
    """Open the viewer shell, optionally selecting SESSION_ID."""
    viewer = ViewerClient(context.config)
    url = viewer.url(session_id) if print_url else viewer.open(session_id)
    if print_url:
        click.echo(url)


def _print_launch(result: LaunchResult, as_json: bool) -> None:
    if as_json:
        click.echo(json.dumps(result.public(), sort_keys=True))
        return
    click.echo(f"pid: {result.pid}")
    click.echo("command: " + " ".join(result.arguments))


def _print_session(session: Session, as_json: bool) -> None:
    if as_json:
        click.echo(json.dumps(session.public(), sort_keys=True))
        return
    click.echo(f"session: {session.id}")
    click.echo(f"agent: {session.agent_id}")
    click.echo(f"state: {session.state}")
    click.echo(f"unit: {session.unit}")
    if session.wayland_display:
        click.echo(f"wayland: {session.wayland_display}")
    if session.cua_socket:
        click.echo(f"cua socket: {session.cua_socket}")
    if session.vnc_socket:
        click.echo(f"vnc socket: {session.vnc_socket}")
    if session.control_socket:
        click.echo(f"control socket: {session.control_socket}")
    if session.browser_profile:
        click.echo(f"browser profile: {session.browser_profile}")
    if session.message:
        click.echo(f"message: {session.message}")


def main() -> None:
    try:
        command(prog_name="agent-desktop", standalone_mode=False)
    except click.ClickException as error:
        error.show()
        raise SystemExit(error.exit_code) from error
    except click.Abort as error:
        raise SystemExit(1) from error
    except (AgentDesktopError, ValidationError) as error:
        failure = click.ClickException(str(error))
        failure.show()
        raise SystemExit(1) from error
