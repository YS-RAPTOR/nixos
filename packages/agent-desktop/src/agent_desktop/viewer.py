from __future__ import annotations

import asyncio
import contextlib
import os
import secrets
import signal
import subprocess
import time
import urllib.error
import urllib.request
from importlib.resources import files
from pathlib import Path
from typing import Any

import click
from aiohttp import ClientError, ClientSession, UnixConnector, WSMsgType, web

from .models import AgentDesktopError, Config, Session, load_config, validate_id
from .system import SessionManager, run


class ViewerServer:
    def __init__(self, config: Config, config_path: Path) -> None:
        self.config = config
        self.manager = SessionManager(config, config_path)
        self.token = secrets.token_urlsafe(32)
        self.app = web.Application()
        self.app.add_routes(
            [
                web.get("/health", self.health),
                web.get("/api/sessions", self.sessions),
                web.post("/api/sessions/{session_id}/destroy", self.destroy),
                web.get("/ws/{session_id}", self.websocket),
                web.get("/", self.asset),
                web.get("/app.js", self.asset),
                web.get("/style.css", self.asset),
            ]
        )
        self.app.router.add_static("/novnc/", str(config.novnc_web_root), follow_symlinks=False)

    def prepare(self) -> None:
        if not (self.config.novnc_web_root / "core/rfb.js").is_file():
            raise AgentDesktopError(
                f"noVNC assets not found under {self.config.novnc_web_root}",
                "viewer_config_error",
            )
        self.config.viewer_runtime_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.config.viewer_runtime_dir, 0o700)
        self.config.viewer_token_path.write_text(self.token)
        os.chmod(self.config.viewer_token_path, 0o600)

    async def health(self, _request: web.Request) -> web.Response:
        return web.json_response({"status": "ok"})

    async def sessions(self, request: web.Request) -> web.Response:
        self._authorize(request)
        sessions = await asyncio.to_thread(self.manager.list)
        return web.json_response([self._public(session) for session in sessions])

    async def destroy(self, request: web.Request) -> web.Response:
        self._authorize(request)
        try:
            session = await asyncio.to_thread(self.manager.destroy, self._session_id(request))
        except AgentDesktopError as error:
            raise web.HTTPConflict(text=str(error)) from error
        return web.json_response(self._public(session))

    async def websocket(self, request: web.Request) -> web.StreamResponse:
        self._authorize(request)
        try:
            session = await asyncio.to_thread(self.manager.status, self._session_id(request))
            socket_path = self._vnc_socket(session)
        except AgentDesktopError as error:
            raise web.HTTPConflict(text=str(error)) from error
        downstream = web.WebSocketResponse(protocols=("binary",))
        await downstream.prepare(request)
        try:
            async with (
                ClientSession(connector=UnixConnector(path=str(socket_path))) as client,
                client.ws_connect("ws://localhost/", protocols=("binary",), max_msg_size=0) as upstream,
            ):
                tasks = {
                    asyncio.create_task(self._relay(downstream, upstream)),
                    asyncio.create_task(self._relay(upstream, downstream)),
                }
                done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
                for task in pending:
                    task.cancel()
                await asyncio.gather(*done, *pending, return_exceptions=True)
        except (ClientError, OSError, TimeoutError) as error:
            await downstream.close(code=1011, message=str(error).encode()[:120])
        return downstream

    @staticmethod
    async def _relay(source: Any, target: Any) -> None:
        async for message in source:
            if message.type == WSMsgType.BINARY:
                await target.send_bytes(message.data)
            elif message.type == WSMsgType.TEXT:
                await target.send_str(message.data)
            elif message.type in {WSMsgType.CLOSE, WSMsgType.CLOSED, WSMsgType.ERROR}:
                break

    async def asset(self, request: web.Request) -> web.FileResponse:
        name = {"/": "index.html", "/app.js": "app.js", "/style.css": "style.css"}[request.path]
        return web.FileResponse(str(files("agent_desktop").joinpath("assets", name)))

    def _authorize(self, request: web.Request) -> None:
        if not secrets.compare_digest(request.query.get("token", ""), self.token):
            raise web.HTTPUnauthorized(text="invalid viewer token")

    @staticmethod
    def _session_id(request: web.Request) -> str:
        try:
            return validate_id(request.match_info["session_id"], "session ID")
        except ValueError as error:
            raise web.HTTPBadRequest(text=str(error)) from error

    def _vnc_socket(self, session: Session) -> Path:
        expected = self.config.runtime_dir(session.id) / "wayvnc.sock"
        if not session.state.launchable:
            raise AgentDesktopError(f"session is {session.state}", "session_not_ready")
        if session.vnc_socket != expected or not expected.is_socket():
            raise AgentDesktopError("session VNC endpoint is unavailable", "vnc_unavailable")
        return expected

    def _public(self, session: Session) -> dict[str, object]:
        expected = self.config.runtime_dir(session.id) / "wayvnc.sock"
        return {
            "id": session.id,
            "agent_id": session.agent_id,
            "state": session.state,
            "created_at": session.created_at,
            "updated_at": session.updated_at,
            "ready_at": session.ready_at,
            "message": session.message,
            "viewer_available": session.state.launchable and session.vnc_socket == expected and expected.is_socket(),
        }


class ViewerClient:
    def __init__(self, config: Config) -> None:
        self.config = config

    def url(self, session_id: str | None = None) -> str:
        if session_id is not None:
            try:
                validate_id(session_id, "session ID")
            except ValueError as error:
                raise AgentDesktopError(str(error), "invalid_id") from error
        run(
            [
                self.config.commands.systemctl,
                "--user",
                "start",
                self.config.viewer_unit,
            ],
            timeout=10,
        )
        self._wait_ready()
        try:
            token = self.config.viewer_token_path.read_text().strip()
        except OSError as error:
            raise AgentDesktopError(f"could not read viewer token: {error}", "viewer_start_failed") from error
        if not token:
            raise AgentDesktopError("viewer token is empty", "viewer_start_failed")
        fragment = f"token={token}"
        if session_id is not None:
            fragment += f"&session={session_id}"
        return f"http://127.0.0.1:{self.config.viewer_port}/#{fragment}"

    def open(self, session_id: str | None = None) -> str:
        url = self.url(session_id)
        try:
            process = subprocess.Popen(
                [self.config.commands.xdg_open, url],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            try:
                return_code = process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                return url
            if return_code != 0:
                raise OSError(f"xdg-open exited with status {return_code}")
        except OSError as error:
            raise AgentDesktopError(
                f"could not open viewer; open this URL manually: {url}: {error}",
                "viewer_open_failed",
            ) from error
        return url

    def _wait_ready(self) -> None:
        deadline = time.monotonic() + 10
        health = f"http://127.0.0.1:{self.config.viewer_port}/health"
        while time.monotonic() < deadline:
            if self.config.viewer_token_path.is_file():
                try:
                    with urllib.request.urlopen(health, timeout=0.5) as response:
                        if response.status == 200:
                            return
                except (OSError, urllib.error.URLError):
                    pass
            time.sleep(0.05)
        raise AgentDesktopError(
            f"viewer service did not become ready: {self.config.viewer_unit}",
            "viewer_start_failed",
        )


async def serve(config: Config, config_path: Path) -> None:
    server = ViewerServer(config, config_path)
    server.prepare()
    runner = web.AppRunner(server.app, access_log=None)
    await runner.setup()
    await web.TCPSite(runner, "127.0.0.1", config.viewer_port).start()
    stopped = asyncio.Event()
    loop = asyncio.get_running_loop()
    for selected in (signal.SIGTERM, signal.SIGINT):
        with contextlib.suppress(NotImplementedError):
            loop.add_signal_handler(selected, stopped.set)
    try:
        await stopped.wait()
    finally:
        await runner.cleanup()
        config.viewer_token_path.unlink(missing_ok=True)


@click.command()
@click.option("--config", "config_path", required=True, type=click.Path(path_type=Path))
def command(config_path: Path) -> None:
    """Serve the loopback-only multi-session viewer."""
    try:
        asyncio.run(serve(load_config(config_path), config_path))
    except (AgentDesktopError, OSError) as error:
        raise click.ClickException(str(error)) from error


def main() -> None:
    command(prog_name="agent-desktop-viewer")


if __name__ == "__main__":
    main()
