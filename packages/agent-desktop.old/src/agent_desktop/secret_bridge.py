from __future__ import annotations

import asyncio
import contextlib
import logging
import signal
from collections.abc import Awaitable

import click
from dbus_next.aio.message_bus import MessageBus
from dbus_next.constants import MessageType, NameFlag, RequestNameReply
from dbus_next.message import Message

from .errors import AgentDesktopError

_LOG = logging.getLogger("agent-desktop-secret-bridge")
_SECRET_NAME = "org.freedesktop.secrets"
_DBUS_NAME = "org.freedesktop.DBus"
_DBUS_PATH = "/org/freedesktop/DBus"
_DBUS_INTERFACE = "org.freedesktop.DBus"


class SecretServiceBridge:
    def __init__(self, private_address: str, host_address: str) -> None:
        self.private_address = private_address
        self.host_address = host_address
        self.private_bus: MessageBus | None = None
        self.host_buses: dict[str, MessageBus] = {}
        self.host_bus_lock = asyncio.Lock()
        self.tasks: set[asyncio.Task[None]] = set()

    async def serve(self) -> None:
        self.private_bus = await MessageBus(
            bus_address=self.private_address, negotiate_unix_fd=True
        ).connect()
        self.private_bus.add_message_handler(self._handle_private_message)
        await self._add_match(
            self.private_bus,
            "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged'",
        )
        reply = await self.private_bus.request_name(_SECRET_NAME, NameFlag.DO_NOT_QUEUE)
        if reply != RequestNameReply.PRIMARY_OWNER:
            raise AgentDesktopError(
                "could not own org.freedesktop.secrets on the private bus",
                "secret_bridge_failed",
            )
        await self.private_bus.wait_for_disconnect()

    def _handle_private_message(self, message: Message) -> bool | None:
        if (
            message.message_type == MessageType.SIGNAL
            and message.interface == _DBUS_INTERFACE
            and message.member == "NameOwnerChanged"
            and len(message.body) == 3
        ):
            name, old_owner, new_owner = message.body
            if name.startswith(":") and old_owner and not new_owner:
                self._track(self._drop_host_bus(name))
            return None
        private_destinations = {_SECRET_NAME}
        if self.private_bus is not None and self.private_bus.unique_name is not None:
            private_destinations.add(self.private_bus.unique_name)
        if (
            message.message_type == MessageType.METHOD_CALL
            and message.destination in private_destinations
            and message.sender is not None
        ):
            self._track(self._forward_method(message))
            return True
        return None

    async def _forward_method(self, message: Message) -> None:
        assert self.private_bus is not None
        try:
            host_bus = await self._host_bus_for(message.sender)
            reply = await host_bus.call(
                Message(
                    destination=_SECRET_NAME,
                    path=message.path,
                    interface=message.interface,
                    member=message.member,
                    flags=message.flags,
                    signature=message.signature,
                    body=message.body,
                    unix_fds=message.unix_fds,
                )
            )
            if reply is None:
                return
            if reply.message_type == MessageType.ERROR:
                forwarded = Message(
                    message_type=MessageType.ERROR,
                    reply_serial=message.serial,
                    destination=message.sender,
                    error_name=reply.error_name,
                    signature=reply.signature,
                    body=reply.body,
                    unix_fds=reply.unix_fds,
                )
            else:
                forwarded = Message.new_method_return(
                    message,
                    reply.signature,
                    reply.body,
                    reply.unix_fds,
                )
            await self.private_bus.send(forwarded)
        except BaseException as error:
            if isinstance(error, asyncio.CancelledError):
                raise
            _LOG.exception("could not forward Secret Service call")
            with contextlib.suppress(Exception):
                await self.private_bus.send(
                    Message.new_error(
                        message,
                        "org.freedesktop.DBus.Error.Failed",
                        str(error),
                    )
                )

    async def _host_bus_for(self, private_sender: str) -> MessageBus:
        existing = self.host_buses.get(private_sender)
        if existing is not None:
            return existing
        async with self.host_bus_lock:
            existing = self.host_buses.get(private_sender)
            if existing is not None:
                return existing
            host_bus = await MessageBus(
                bus_address=self.host_address, negotiate_unix_fd=True
            ).connect()
            host_bus.add_message_handler(
                lambda message: self._handle_host_message(private_sender, message)
            )
            await self._add_match(
                host_bus,
                "type='signal',sender='org.freedesktop.secrets'",
            )
            self.host_buses[private_sender] = host_bus
            return host_bus

    def _handle_host_message(
        self, private_sender: str, message: Message
    ) -> bool | None:
        if message.message_type != MessageType.SIGNAL or message.path is None:
            return None
        if message.interface is None or message.member is None:
            return None
        assert self.private_bus is not None
        self._track(
            self.private_bus.send(
                Message(
                    message_type=MessageType.SIGNAL,
                    destination=private_sender,
                    path=message.path,
                    interface=message.interface,
                    member=message.member,
                    signature=message.signature,
                    body=message.body,
                    unix_fds=message.unix_fds,
                )
            )
        )
        return None

    async def _drop_host_bus(self, private_sender: str) -> None:
        host_bus = self.host_buses.pop(private_sender, None)
        if host_bus is not None:
            host_bus.disconnect()
            with contextlib.suppress(Exception):
                await host_bus.wait_for_disconnect()

    async def close(self) -> None:
        for task in tuple(self.tasks):
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)
        for private_sender in tuple(self.host_buses):
            await self._drop_host_bus(private_sender)
        if self.private_bus is not None:
            self.private_bus.disconnect()

    def _track(self, awaitable: Awaitable[None]) -> None:
        task = asyncio.ensure_future(awaitable)
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)

    @staticmethod
    async def _add_match(bus: MessageBus, rule: str) -> None:
        reply = await bus.call(
            Message(
                destination=_DBUS_NAME,
                path=_DBUS_PATH,
                interface=_DBUS_INTERFACE,
                member="AddMatch",
                signature="s",
                body=[rule],
            )
        )
        if reply is None or reply.message_type == MessageType.ERROR:
            detail = reply.body[0] if reply and reply.body else "unknown error"
            raise AgentDesktopError(
                f"could not install D-Bus match rule: {detail}",
                "secret_bridge_failed",
            )


async def run(private_address: str, host_address: str) -> None:
    bridge = SecretServiceBridge(private_address, host_address)
    task = asyncio.create_task(bridge.serve())
    stopped = asyncio.Event()
    loop = asyncio.get_running_loop()
    for selected_signal in (signal.SIGTERM, signal.SIGINT):
        with contextlib.suppress(NotImplementedError):
            loop.add_signal_handler(selected_signal, stopped.set)
    stop_task = asyncio.create_task(stopped.wait())
    try:
        await asyncio.wait(
            {task, stop_task},
            return_when=asyncio.FIRST_COMPLETED,
        )
        if task.done():
            await task
    finally:
        task.cancel()
        stop_task.cancel()
        await asyncio.gather(task, stop_task, return_exceptions=True)
        await bridge.close()


@click.command()
@click.option("--private-address", required=True)
@click.option("--host-address", required=True)
@click.option(
    "--log-level",
    default="INFO",
    type=click.Choice(["DEBUG", "INFO", "WARNING", "ERROR"]),
)
def command(private_address: str, host_address: str, log_level: str) -> None:
    """Expose the host Secret Service on one private agent D-Bus."""
    logging.basicConfig(
        level=getattr(logging, log_level), format="%(levelname)s %(message)s"
    )
    try:
        asyncio.run(run(private_address, host_address))
    except (AgentDesktopError, OSError) as error:
        raise click.ClickException(str(error)) from error


def main() -> None:
    command(prog_name="agent-desktop-secret-bridge")
