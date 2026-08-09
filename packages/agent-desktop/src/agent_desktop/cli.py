from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import click

from .models import (
    AgentDesktopError,
    Config,
    Launch,
    Session,
    State,
    default_config_path,
    load_config,
)
from .system import SessionManager
from .viewer import ViewerClient


@dataclass(frozen=True)
class Context:
    config: Config
    path: Path

    @property
    def manager(self) -> SessionManager:
        return SessionManager(self.config, self.path)


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
@click.option("--session-id", help="fixed session ID")
@click.option("--json", "as_json", is_flag=True, help="print JSON")
@click.option("--view", "open_viewer", is_flag=True, help="open the viewer")
@click.pass_obj
def create(
    context: Context,
    agent_id: str,
    session_id: str | None,
    as_json: bool,
    open_viewer: bool,
) -> None:
    """Create a desktop for AGENT_ID and wait until it is ready."""
    session = context.manager.create(agent_id, session_id)
    _print(session, as_json)
    if open_viewer:
        try:
            ViewerClient(context.config).open(session.id)
        except AgentDesktopError as error:
            click.echo(f"warning: {error}", err=True)


@command.command()
@click.argument("session_id")
@click.option("--json", "as_json", is_flag=True, help="print JSON")
@click.pass_obj
def status(context: Context, session_id: str, as_json: bool) -> None:
    """Show one desktop's lifecycle state."""
    _print(context.manager.status(session_id), as_json)


@command.command("list")
@click.option("--json", "as_json", is_flag=True, help="print JSON")
@click.option("--all", "include_stopped", is_flag=True, help="include stopped desktops")
@click.pass_obj
def list_sessions(context: Context, as_json: bool, include_stopped: bool) -> None:
    """List known agent desktops."""
    sessions = context.manager.list()
    if not include_stopped:
        sessions = [session for session in sessions if session.state != State.STOPPED]
    if as_json:
        click.echo(json.dumps([session.public() for session in sessions], sort_keys=True))
    elif not sessions:
        click.echo("No agent desktops")
    else:
        for session in sessions:
            click.echo(f"{session.id:<64} {session.state:<9} agent={session.agent_id}")


@command.command("exec", context_settings={"ignore_unknown_options": True})
@click.argument("session_id")
@click.argument("arguments", nargs=-1, required=True, type=click.UNPROCESSED)
@click.option("--json", "as_json", is_flag=True, help="print JSON")
@click.pass_obj
def exec_command(context: Context, session_id: str, arguments: tuple[str, ...], as_json: bool) -> None:
    """Launch COMMAND with exact arguments using: exec SESSION -- COMMAND."""
    _print(context.manager.launch(session_id, arguments), as_json)


@command.command()
@click.argument("session_id")
@click.argument("url", required=False, default="about:blank")
@click.option("--json", "as_json", is_flag=True, help="print JSON")
@click.pass_obj
def browser(context: Context, session_id: str, url: str, as_json: bool) -> None:
    """Launch Vivaldi with the desktop's disposable profile."""
    _print(context.manager.launch_browser(session_id, url), as_json)


@command.command()
@click.argument("session_id")
@click.option("--json", "as_json", is_flag=True, help="print JSON")
@click.pass_obj
def destroy(context: Context, session_id: str, as_json: bool) -> None:
    """Stop a desktop and all applications belonging to it."""
    _print(context.manager.destroy(session_id), as_json)


@command.command()
@click.argument("session_id", required=False)
@click.option("--print", "print_url", is_flag=True, help="print instead of opening")
@click.pass_obj
def view(context: Context, session_id: str | None, print_url: bool) -> None:
    """Open the viewer, optionally selecting SESSION_ID."""
    viewer = ViewerClient(context.config)
    url = viewer.url(session_id) if print_url else viewer.open(session_id)
    if print_url:
        click.echo(url)


def _print(value: Session | Launch, as_json: bool) -> None:
    if as_json:
        click.echo(json.dumps(value.public(), sort_keys=True))
    elif isinstance(value, Launch):
        click.echo(f"pid: {value.pid}")
        click.echo("command: " + " ".join(value.arguments))
    else:
        click.echo(f"session: {value.id}\nagent: {value.agent_id}\nstate: {value.state}\nunit: {value.unit}")
        for label, field in (
            ("wayland", value.wayland_display),
            ("cua socket", value.cua_socket),
            ("vnc socket", value.vnc_socket),
            ("control socket", value.control_socket),
            ("browser profile", value.browser_profile),
            ("message", value.message),
        ):
            if field is not None:
                click.echo(f"{label}: {field}")


def main() -> None:
    try:
        command(prog_name="agent-desktop", standalone_mode=False)
    except click.ClickException as error:
        error.show()
        raise SystemExit(error.exit_code) from error
    except click.Abort as error:
        raise SystemExit(1) from error
    except (AgentDesktopError, ValueError) as error:
        failure = click.ClickException(str(error))
        failure.show()
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
