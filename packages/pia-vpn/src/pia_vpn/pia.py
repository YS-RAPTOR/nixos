from __future__ import annotations

import json
import socket
import ssl
from pathlib import Path
from typing import Any

import aiohttp
import certifi
from aiohttp.abc import AbstractResolver, ResolveResult
from pydantic import ValidationError

from .errors import PiaVpnError
from .models import Credentials, Endpoint, Registration, ServerList

TOKEN_URL = "https://www.privateinternetaccess.com/api/client/v2/token"
SERVER_LIST_URL = "https://serverlist.piaservers.net/vpninfo/servers/v6"
_MAX_RESPONSE = 8 * 1024 * 1024


class FixedResolver(AbstractResolver):
    """Resolve one authenticated PIA hostname to its advertised server IP."""

    def __init__(self, hostname: str, address: str) -> None:
        self.hostname = hostname
        self.address = address

    async def resolve(
        self, host: str, port: int = 0, family: socket.AddressFamily = socket.AF_INET
    ) -> list[ResolveResult]:
        if host.casefold() != self.hostname.casefold():
            raise OSError("unexpected hostname")
        result: ResolveResult = {
            "hostname": host,
            "host": self.address,
            "port": port,
            "family": socket.AF_INET,
            "proto": socket.IPPROTO_TCP,
            "flags": socket.AI_NUMERICHOST,
        }
        return [result]

    async def close(self) -> None:
        return None


class PiaClient:
    def __init__(self, ca_certificate: Path, timeout: float = 20) -> None:
        self.ca_certificate = ca_certificate
        self.timeout = aiohttp.ClientTimeout(total=timeout)

    async def token(self, credentials: Credentials) -> str:
        # PIA's reference client submits multipart form data.
        form = aiohttp.FormData(default_to_multipart=True)
        form.add_field("username", credentials.username)
        form.add_field("password", credentials.password)
        value = await self._json("POST", TOKEN_URL, data=form)
        token = value.get("token")
        if not isinstance(token, str) or not token:
            raise PiaVpnError(
                "PIA rejected the supplied credentials", "authentication_failed"
            )
        return token

    async def server_list(self) -> ServerList:
        data = await self._bytes("GET", SERVER_LIST_URL)
        first_line = data.splitlines()[0] if data.splitlines() else b""
        try:
            return ServerList.model_validate_json(first_line)
        except ValidationError as error:
            raise PiaVpnError(
                f"invalid PIA server list: {error}", "invalid_server_list"
            ) from error

    async def register(
        self, endpoint: Endpoint, token: str, public_key: str
    ) -> Registration:
        context = ssl.create_default_context(cafile=str(self.ca_certificate))
        # PIA's pinned legacy CA omits the critical marker on Basic Constraints.
        # Keep hostname, chain, and signature checks while allowing that CA.
        context.verify_flags &= ~ssl.VERIFY_X509_STRICT
        connector = aiohttp.TCPConnector(
            resolver=FixedResolver(endpoint.cn, str(endpoint.ip)),
            family=socket.AF_INET,
            ssl=context,
        )
        async with aiohttp.ClientSession(
            connector=connector, timeout=self.timeout
        ) as session:
            value = await self._json(
                "GET",
                f"https://{endpoint.cn}:1337/addKey",
                session=session,
                params={"pt": token, "pubkey": public_key},
            )
        try:
            return Registration.model_validate(value)
        except ValidationError as error:
            raise PiaVpnError(
                f"invalid PIA registration response: {error}", "invalid_response"
            ) from error

    async def _json(
        self,
        method: str,
        url: str,
        *,
        session: aiohttp.ClientSession | None = None,
        **kwargs: Any,
    ) -> dict[str, Any]:
        data = await self._bytes(method, url, session=session, **kwargs)
        try:
            value = json.loads(data)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise PiaVpnError(
                "PIA returned invalid JSON", "invalid_response"
            ) from error
        if not isinstance(value, dict):
            raise PiaVpnError("PIA returned an unexpected response", "invalid_response")
        return value

    async def _bytes(
        self,
        method: str,
        url: str,
        *,
        session: aiohttp.ClientSession | None = None,
        **kwargs: Any,
    ) -> bytes:
        owned = session is None
        current = session or aiohttp.ClientSession(
            connector=aiohttp.TCPConnector(
                ssl=ssl.create_default_context(cafile=certifi.where())
            ),
            timeout=self.timeout,
        )
        try:
            async with current.request(method, url, **kwargs) as response:
                chunks: list[bytes] = []
                size = 0
                async for chunk in response.content.iter_chunked(64 * 1024):
                    size += len(chunk)
                    if size > _MAX_RESPONSE:
                        raise PiaVpnError(
                            "PIA response exceeds 8 MiB", "invalid_response"
                        )
                    chunks.append(chunk)
                data = b"".join(chunks)
                if response.status >= 400:
                    # Do not include the URL: /addKey carries the token as a query value.
                    raise PiaVpnError(
                        f"PIA request failed with HTTP {response.status}",
                        "request_failed",
                    )
                return data
        except PiaVpnError:
            raise
        except (aiohttp.ClientError, TimeoutError, OSError) as error:
            raise PiaVpnError(
                f"cannot reach PIA: {type(error).__name__}", "network_error"
            ) from error
        finally:
            if owned:
                await current.close()
