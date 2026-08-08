import asyncio
import socket
from pathlib import Path

from aiohttp import web

from pia_vpn.pia import FixedResolver, PiaClient


def test_fixed_resolver_preserves_advertised_ip_without_dns() -> None:
    async def resolve() -> None:
        resolver = FixedResolver("Server-11531-3a", "158.173.167.15")
        values = await resolver.resolve("server-11531-3a", 1337)
        assert values[0]["host"] == "158.173.167.15"
        assert values[0]["port"] == 1337

    asyncio.run(resolve())


def test_http_client_reads_every_response_chunk() -> None:
    async def scenario() -> None:
        payload = b"x" * (256 * 1024)

        async def respond(_: web.Request) -> web.Response:
            return web.Response(body=payload)

        app = web.Application()
        app.router.add_get("/", respond)
        runner = web.AppRunner(app)
        await runner.setup()
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        site = web.SockSite(runner, listener)
        await site.start()
        try:
            port = listener.getsockname()[1]
            result = await PiaClient(Path("/nonexistent"))._bytes(
                "GET", f"http://127.0.0.1:{port}/"
            )
            assert result == payload
        finally:
            await runner.cleanup()

    asyncio.run(scenario())
