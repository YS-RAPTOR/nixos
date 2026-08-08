import asyncio
from pathlib import Path

from pia_vpn.control import request
from pia_vpn.controller import Controller
from pia_vpn.models import Config


def test_controller_exposes_setup_required_over_unix_socket(tmp_path: Path) -> None:
    async def scenario() -> None:
        config = Config(
            default_region="nz",
            runtime_dir=tmp_path / "run",
            state_dir=tmp_path / "state",
            credential_path=tmp_path / "state" / "credential.cred",
        )
        controller = Controller(config)
        server = asyncio.create_task(controller.serve())
        for _ in range(100):
            if config.socket_path.exists():
                break
            await asyncio.sleep(0.01)
        status = await request(config, "status")
        assert status["state"] == "setup-required"
        assert status["effective_region"] == "nz"
        controller.stop()
        await server

    asyncio.run(scenario())
