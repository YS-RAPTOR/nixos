#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import json
import struct
import sys
from pathlib import Path
from urllib.parse import urlencode

from aiohttp import ClientSession, WSMsgType

base_url, session_id, token, value, output = sys.argv[1:]


def key(down: bool, keysym: int) -> bytes:
    return struct.pack(">BBHI", 4, int(down), 0, keysym)


def pointer(mask: int, x: int, y: int) -> bytes:
    return struct.pack(">BBHH", 5, mask, x, y)


class Rfb:
    def __init__(self, websocket: object) -> None:
        self.websocket = websocket
        self.buffer = bytearray()

    async def read(self, size: int) -> bytes:
        while len(self.buffer) < size:
            message = await asyncio.wait_for(self.websocket.receive(), 10)  # type: ignore[attr-defined]
            if message.type != WSMsgType.BINARY:
                raise RuntimeError(f"unexpected WebSocket message: {message.type}")
            self.buffer.extend(message.data)
        result = bytes(self.buffer[:size])
        del self.buffer[:size]
        return result

    async def send(self, payload: bytes) -> None:
        await self.websocket.send_bytes(payload)  # type: ignore[attr-defined]


async def main() -> None:
    async with ClientSession() as client:
        query = urlencode({"token": token})
        async with client.ws_connect(
            f"{base_url}/ws/{session_id}?{query}", protocols=("binary",), max_msg_size=0
        ) as websocket:
            rfb = Rfb(websocket)
            version = await rfb.read(12)
            if not version.startswith(b"RFB "):
                raise RuntimeError(f"invalid RFB version: {version!r}")
            await rfb.send(version)
            security_types = await rfb.read((await rfb.read(1))[0])
            if 1 not in security_types:
                raise RuntimeError("RFB no-auth type is unavailable on the private transport")
            await rfb.send(b"\x01")
            if await rfb.read(4) != b"\0\0\0\0":
                raise RuntimeError("RFB security negotiation failed")
            await rfb.send(b"\x01")
            server = await rfb.read(24)
            width, height = struct.unpack(">HH", server[:4])
            name_size = struct.unpack(">I", server[20:24])[0]
            name = (await rfb.read(name_size)).decode(errors="replace")

            # The fixture is fullscreen. Its entry center is stable in the configured
            # 1280x720 framebuffer and this sequence proves press + release, not motion.
            for mask in (0, 1, 0):
                await rfb.send(pointer(mask, 616, 247))
                await asyncio.sleep(0.25)
            # Fresh headless wlroots seats may discard their first keyboard event.
            for down in (True, False):
                await rfb.send(key(down, 0xFFE1))
                await asyncio.sleep(0.2)
            for character in value:
                for down in (True, False):
                    await rfb.send(key(down, ord(character)))
                    await asyncio.sleep(0.04)
            for down in (True, False):
                await rfb.send(key(down, 0xFF0D))
                await asyncio.sleep(0.25)

            Path(output).write_text(
                json.dumps({"height": height, "name": name, "value": value, "width": width}, sort_keys=True) + "\n"
            )


asyncio.run(main())
