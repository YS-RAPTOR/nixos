import json
from pathlib import Path

from click.testing import CliRunner

from pia_vpn.cli import command
from pia_vpn.models import Config, ConnectionState, Status
from pia_vpn.storage import read_model, write_json


def test_atomic_model_storage_is_private(tmp_path: Path) -> None:
    path = tmp_path / "config.json"
    write_json(path, Config(default_region="nz"))
    assert read_model(path, Config).default_region == "nz"
    assert path.stat().st_mode & 0o777 == 0o600


def test_waybar_status_reads_only_local_state(tmp_path: Path) -> None:
    config_path = tmp_path / "config.json"
    config_path.write_text(
        json.dumps(
            {
                "default_region": "nz",
                "runtime_dir": str(tmp_path / "run"),
                "state_dir": str(tmp_path / "state"),
                "credential_path": str(tmp_path / "state" / "credential.cred"),
            }
        )
    )
    config = Config.model_validate_json(config_path.read_bytes())
    write_json(
        config.status_path,
        Status(
            state=ConnectionState.CONNECTED,
            desired=True,
            default_region="nz",
            effective_region="nz",
            effective_region_name="New Zealand",
            interface="pia",
        ),
    )
    result = CliRunner().invoke(
        command, ["--config", str(config_path), "status", "--waybar"]
    )
    assert result.exit_code == 0
    value = json.loads(result.output)
    assert value["class"] == "connected"
    assert "New Zealand" in value["tooltip"]
