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

from .models import AgentDesktopError

_LOG = logging.getLogger("agent-desktop-secret-bridge")
_SECRET = "org.freedesktop.secrets"
_DBUS = "org.freedesktop.DBus"
_DBUS_PATH = "/org/freedesktop/DBus"


class SecretBridge:
    def __init__(self, private_address: str, host_address: str) -> None:
        self.private_address = private_address
        self.host_address = host_address
        self.private: MessageBus | None = None
        self.hosts: dict[str, MessageBus] = {}
        self.lock = asyncio.Lock()
        self.tasks: set[asyncio.Task[None]] = set()

    async def serve(self) -> None:
        self.private = await MessageBus(bus_address=self.private_address, negotiate_unix_fd=True).connect()
        self.private.add_message_handler(self._private_message)
        await self._add_match(
            self.private,
            "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged'",
        )
        reply = await self.private.request_name(_SECRET, NameFlag.DO_NOT_QUEUE)
        if reply != RequestNameReply.PRIMARY_OWNER:
            raise AgentDesktopError(
                "could not own org.freedesktop.secrets on the private bus",
                "secret_bridge_failed",
            )
        await self.private.wait_for_disconnect()

    def _private_message(self, message: Message) -> bool | None:
        if (
            message.message_type == MessageType.SIGNAL
            and message.interface == _DBUS
            and message.member == "NameOwnerChanged"
            and len(message.body) == 3
        ):
            name, old_owner, new_owner = message.body
            if name.startswith(":") and old_owner and not new_owner:
                self._track(self._drop(name))
            return None
        destinations = {_SECRET}
        if self.private is not None and self.private.unique_name is not None:
            destinations.add(self.private.unique_name)
        if (
            message.message_type == MessageType.METHOD_CALL
            and message.destination in destinations
            and message.sender is not None
        ):
            self._track(self._forward(message))
            return True
        return None

    async def _forward(self, message: Message) -> None:
        assert self.private is not None and message.sender is not None
        try:
            host = await self._host(message.sender)
            reply = await host.call(
                Message(
                    destination=_SECRET,
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
            forwarded = (
                Message(
                    message_type=MessageType.ERROR,
                    reply_serial=message.serial,
                    destination=message.sender,
                    error_name=reply.error_name,
                    signature=reply.signature,
                    body=reply.body,
                    unix_fds=reply.unix_fds,
                )
                if reply.message_type == MessageType.ERROR
                else Message.new_method_return(message, reply.signature, reply.body, reply.unix_fds)
            )
            await self.private.send(forwarded)
        except BaseException as error:
            if isinstance(error, asyncio.CancelledError):
                raise
            _LOG.exception("could not forward Secret Service call")
            with contextlib.suppress(Exception):
                await self.private.send(Message.new_error(message, "org.freedesktop.DBus.Error.Failed", str(error)))

    async def _host(self, sender: str) -> MessageBus:
        if existing := self.hosts.get(sender):
            return existing
        async with self.lock:
            if existing := self.hosts.get(sender):
                return existing
            bus = await MessageBus(bus_address=self.host_address, negotiate_unix_fd=True).connect()
            bus.add_message_handler(lambda message: self._host_message(sender, message))
            await self._add_match(bus, "type='signal',sender='org.freedesktop.secrets'")
            self.hosts[sender] = bus
            return bus

    def _host_message(self, sender: str, message: Message) -> bool | None:
        if (
            message.message_type != MessageType.SIGNAL
            or message.path is None
            or message.interface is None
            or message.member is None
        ):
            return None
        assert self.private is not None
        self._track(
            self.private.send(
                Message(
                    message_type=MessageType.SIGNAL,
                    destination=sender,
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

    async def _drop(self, sender: str) -> None:
        if bus := self.hosts.pop(sender, None):
            bus.disconnect()
            with contextlib.suppress(Exception):
                await bus.wait_for_disconnect()

    async def close(self) -> None:
        for task in tuple(self.tasks):
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)
        for sender in tuple(self.hosts):
            await self._drop(sender)
        if self.private is not None:
            self.private.disconnect()

    def _track(self, awaitable: Awaitable[None]) -> None:
        task = asyncio.ensure_future(awaitable)
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)

    @staticmethod
    async def _add_match(bus: MessageBus, rule: str) -> None:
        reply = await bus.call(
            Message(
                destination=_DBUS,
                path=_DBUS_PATH,
                interface=_DBUS,
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


async def run_bridge(private_address: str, host_address: str) -> None:
    bridge = SecretBridge(private_address, host_address)
    service = asyncio.create_task(bridge.serve())
    stopped = asyncio.Event()
    loop = asyncio.get_running_loop()
    for selected in (signal.SIGTERM, signal.SIGINT):
        with contextlib.suppress(NotImplementedError):
            loop.add_signal_handler(selected, stopped.set)
    stop = asyncio.create_task(stopped.wait())
    try:
        await asyncio.wait({service, stop}, return_when=asyncio.FIRST_COMPLETED)
        if service.done():
            await service
    finally:
        service.cancel()
        stop.cancel()
        await asyncio.gather(service, stop, return_exceptions=True)
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
    """Expose the host Secret Service on one private desktop bus."""
    logging.basicConfig(level=getattr(logging, log_level), format="%(levelname)s %(message)s")
    try:
        asyncio.run(run_bridge(private_address, host_address))
    except (AgentDesktopError, OSError) as error:
        raise click.ClickException(str(error)) from error


def main() -> None:
    command(prog_name="agent-desktop-secret-bridge")


if __name__ == "__main__":
    main()
