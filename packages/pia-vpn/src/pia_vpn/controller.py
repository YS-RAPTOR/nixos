from __future__ import annotations

import asyncio
import grp
import logging
import os
import signal
import time
from importlib import resources
from pathlib import Path
from typing import Any

import click
from aiohttp import web
from pydantic import ValidationError

from .errors import PiaVpnError
from .models import (
    Config,
    ConnectionState,
    Credentials,
    Preferences,
    ServerList,
    Status,
    load_config,
)
from .pia import PiaClient
from .storage import read_model, write_json
from .system import SystemNetwork

_LOG = logging.getLogger("pia-vpn-controller")


class Controller:
    def __init__(self, config: Config) -> None:
        self.config = config
        self.preferences = read_model(
            config.preferences_path, Preferences, Preferences()
        )
        self.regions: ServerList | None = None
        try:
            self.regions = read_model(config.regions_path, ServerList)
        except PiaVpnError:
            pass
        self.network = SystemNetwork(config)
        ca = config.ca_certificate or Path(
            str(resources.files("pia_vpn") / "ca.rsa.4096.crt")
        )
        self.pia = PiaClient(ca, config.command_timeout)
        self.desired = config.auto_start
        self.changed = asyncio.Event()
        self.stopping = asyncio.Event()
        self.lifecycle = asyncio.Lock()
        self.status = self._status(
            ConnectionState.SETUP_REQUIRED
            if not self.credential_path().is_file()
            else ConnectionState.DISCONNECTED,
            message="PIA credentials are not configured"
            if not self.credential_path().is_file()
            else None,
        )

    def credential_path(self) -> Path:
        override = os.environ.get("PIA_VPN_CREDENTIAL_FILE")
        if override:
            return Path(override)
        directory = os.environ.get("CREDENTIALS_DIRECTORY")
        return (
            Path(directory) / self.config.credential_name
            if directory
            else Path("/nonexistent")
        )

    def credentials(self) -> Credentials:
        path = self.credential_path()
        try:
            return Credentials.model_validate_json(path.read_bytes())
        except OSError as error:
            raise PiaVpnError(
                "PIA credentials are not configured", "setup_required"
            ) from error
        except ValidationError as error:
            raise PiaVpnError(
                "PIA credentials are invalid", "invalid_credentials"
            ) from error

    async def serve(self) -> None:
        self.config.runtime_dir.mkdir(mode=0o750, parents=True, exist_ok=True)
        self.config.state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.config.socket_path.unlink(missing_ok=True)
        self._publish(self.status)

        app = web.Application(client_max_size=64 * 1024)
        app.router.add_post("/command", self.handle)
        runner = web.AppRunner(app, access_log=None)
        await runner.setup()
        site = web.UnixSite(runner, str(self.config.socket_path))
        await site.start()
        os.chmod(self.config.socket_path, 0o660)
        if self.config.socket_group:
            os.chown(
                self.config.socket_path,
                -1,
                grp.getgrnam(self.config.socket_group).gr_gid,
            )

        worker = asyncio.create_task(self.run(), name="pia-vpn-worker")
        await self.stopping.wait()
        worker.cancel()
        await asyncio.gather(worker, return_exceptions=True)
        await runner.cleanup()
        self.config.socket_path.unlink(missing_ok=True)

    async def handle(self, request: web.Request) -> web.Response:
        try:
            value = await request.json()
            if not isinstance(value, dict) or not isinstance(value.get("command"), str):
                raise PiaVpnError("invalid controller request", "invalid_request")
            params = value.get("params", {})
            if not isinstance(params, dict):
                raise PiaVpnError("request params must be an object", "invalid_request")
            result = await self.dispatch(value["command"], params)
            return web.json_response({"result": result})
        except PiaVpnError as error:
            return web.json_response(
                {"error": {"code": error.code, "message": str(error)}}, status=400
            )
        except Exception:  # noqa: BLE001 - contain failures at the local API boundary
            _LOG.exception("controller request failed")
            return web.json_response(
                {
                    "error": {
                        "code": "internal_error",
                        "message": "controller request failed",
                    }
                },
                status=500,
            )

    async def dispatch(self, command: str, params: dict[str, Any]) -> Any:
        if command == "status":
            return self.status.public()
        if command == "connect":
            self.credentials()
            self.desired = True
            self.changed.set()
            return self.status.public()
        if command == "disconnect":
            self.desired = False
            self.changed.set()
            await self._disconnect(unprotect=True)
            return self.status.public()
        if command == "toggle":
            return await self.dispatch("disconnect" if self.desired else "connect", {})
        if command == "locations":
            if not self.regions:
                raise PiaVpnError(
                    "PIA location cache is not available yet", "locations_unavailable"
                )
            return [
                region.public() for region in self.regions.regions if region.servers.wg
            ]
        if command == "location.current":
            return self._location()
        if command == "location.set":
            region_id = params.get("region")
            if not isinstance(region_id, str) or not self.regions:
                raise PiaVpnError(
                    "a cached PIA region ID is required", "invalid_request"
                )
            self.regions.region(region_id)
            self.preferences = Preferences(region=region_id)
            write_json(self.config.preferences_path, self.preferences)
            self.changed.set()
            return self._location()
        if command == "location.reset":
            self.preferences = Preferences()
            write_json(self.config.preferences_path, self.preferences)
            self.changed.set()
            return self._location()
        if command == "credentials.changed":
            self.credentials()
            self.desired = self.config.auto_start
            self.changed.set()
            return None
        if command == "credentials.clearing":
            self.desired = False
            await self._disconnect(unprotect=True)
            return None
        raise PiaVpnError(f"unknown controller command: {command}", "unknown_command")

    async def run(self) -> None:
        delay = self.config.retry_initial
        while True:
            if not self.desired:
                self.changed.clear()
                await self.changed.wait()
                continue
            if not self.credential_path().is_file():
                self._publish(
                    self._status(
                        ConnectionState.SETUP_REQUIRED,
                        "PIA credentials are not configured",
                    )
                )
                self.changed.clear()
                await self.changed.wait()
                continue
            try:
                self.changed.clear()
                await self._connect()
                delay = self.config.retry_initial
                await self._monitor()
            except PiaVpnError as error:
                _LOG.warning("connection unavailable: %s", error)
                await asyncio.to_thread(self.network.disconnect, ignore_errors=True)
                self._publish(self._status(ConnectionState.BLOCKED, str(error)))
                if not self.changed.is_set():
                    try:
                        await asyncio.wait_for(self.changed.wait(), timeout=delay)
                    except TimeoutError:
                        pass
                delay = min(delay * 2, self.config.retry_max)
            except asyncio.CancelledError:
                raise
            except Exception:  # noqa: BLE001 - keep protection active on unexpected failure
                _LOG.exception("unexpected connection failure")
                self._publish(
                    self._status(
                        ConnectionState.BLOCKED, "unexpected connection failure"
                    )
                )
                await asyncio.sleep(delay)
                delay = min(delay * 2, self.config.retry_max)

    async def _connect(self) -> None:
        async with self.lifecycle:
            self._publish(self._status(ConnectionState.CONNECTING))
            await asyncio.to_thread(self.network.protect)
            credentials = self.credentials()
            token = await self.pia.token(credentials)
            regions = await self.pia.server_list()
            self.regions = regions
            write_json(self.config.regions_path, regions)
            region = regions.region(self.effective_region)
            endpoint = region.servers.wg[0]
            keys = await asyncio.to_thread(self.network.keys)
            registration = await self.pia.register(endpoint, token, keys.public)
            await asyncio.to_thread(
                self.network.protect,
                (str(registration.server_ip), registration.server_port),
            )
            await asyncio.to_thread(self.network.connect, keys, registration)
            self._publish(
                self._status(
                    ConnectionState.CONNECTED,
                    name=region.name,
                    endpoint=f"{registration.server_ip}:{registration.server_port}",
                    connected_at=time.time(),
                    handshake_age=0,
                )
            )

    async def _monitor(self) -> None:
        while self.desired:
            try:
                await asyncio.wait_for(
                    self.changed.wait(), timeout=self.config.health_interval
                )
                return
            except TimeoutError:
                pass
            age = await asyncio.to_thread(self.network.handshake_age)
            if age is None or age > self.config.handshake_max_age:
                raise PiaVpnError("WireGuard handshake is stale", "unhealthy_tunnel")
            self._publish(self.status.model_copy(update={"handshake_age": age}))

    async def _disconnect(self, *, unprotect: bool) -> None:
        async with self.lifecycle:
            await asyncio.to_thread(self.network.disconnect, ignore_errors=True)
            if unprotect:
                await asyncio.to_thread(self.network.unprotect)
            self._publish(self._status(ConnectionState.DISCONNECTED))

    @property
    def effective_region(self) -> str:
        return self.preferences.region or self.config.default_region

    def _location(self) -> dict[str, Any]:
        name = None
        if self.regions:
            try:
                name = self.regions.region(self.effective_region).name
            except PiaVpnError:
                pass
        return {
            "default_region": self.config.default_region,
            "override_region": self.preferences.region,
            "effective_region": self.effective_region,
            "effective_region_name": name,
        }

    def _status(
        self,
        state: ConnectionState,
        message: str | None = None,
        *,
        name: str | None = None,
        endpoint: str | None = None,
        connected_at: float | None = None,
        handshake_age: float | None = None,
    ) -> Status:
        return Status(
            state=state,
            desired=self.desired,
            default_region=self.config.default_region,
            override_region=self.preferences.region,
            effective_region=self.effective_region,
            effective_region_name=name,
            interface=self.config.interface,
            message=message,
            endpoint=endpoint,
            connected_at=connected_at,
            handshake_age=handshake_age,
        )

    def _publish(self, status: Status) -> None:
        self.status = status
        write_json(self.config.status_path, status)
        os.chmod(self.config.status_path, 0o640)
        if self.config.socket_group:
            os.chown(
                self.config.status_path,
                -1,
                grp.getgrnam(self.config.socket_group).gr_gid,
            )

    def stop(self) -> None:
        self.stopping.set()


async def _serve(config: Config) -> None:
    controller = Controller(config)
    loop = asyncio.get_running_loop()
    for current in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(current, controller.stop)
    await controller.serve()


@click.command()
@click.option(
    "--config",
    "config_path",
    type=click.Path(path_type=Path),
    help="configuration JSON",
)
@click.option(
    "--log-level",
    default="INFO",
    type=click.Choice(["DEBUG", "INFO", "WARNING", "ERROR"]),
)
def command(config_path: Path | None, log_level: str) -> None:
    """Run the PIA WireGuard controller."""
    logging.basicConfig(
        level=getattr(logging, log_level), format="%(levelname)s %(message)s"
    )
    try:
        asyncio.run(_serve(load_config(config_path)))
    except PiaVpnError as error:
        raise click.ClickException(str(error)) from error


def main() -> None:
    command(prog_name="pia-vpn-controller")
