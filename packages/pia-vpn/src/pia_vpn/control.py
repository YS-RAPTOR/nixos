from __future__ import annotations

import asyncio
from typing import Any

import aiohttp

from .errors import PiaVpnError
from .models import Config


async def request(config: Config, command: str, **params: Any) -> Any:
    deadline = asyncio.get_running_loop().time() + 10
    while True:
        connector = aiohttp.UnixConnector(path=str(config.socket_path))
        try:
            async with (
                aiohttp.ClientSession(
                    connector=connector, timeout=aiohttp.ClientTimeout(total=10)
                ) as session,
                session.post(
                    "http://localhost/command",
                    json={"command": command, "params": params},
                ) as response,
            ):
                value = await response.json()
            break
        except (aiohttp.ClientError, TimeoutError, OSError) as error:
            if asyncio.get_running_loop().time() >= deadline:
                raise PiaVpnError(
                    "PIA controller is not available", "controller_unavailable"
                ) from error
            await asyncio.sleep(0.1)

    if response.status >= 400:
        error = value.get("error", {}) if isinstance(value, dict) else {}
        raise PiaVpnError(
            str(error.get("message", "controller request failed")),
            str(error.get("code", "controller_error")),
        )
    return value.get("result") if isinstance(value, dict) else None
