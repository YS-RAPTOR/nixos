import base64

import pytest
from pydantic import ValidationError

from pia_vpn.models import Config, Registration, ServerList


def test_config_forbids_unknown_policy() -> None:
    with pytest.raises(ValidationError):
        Config(default_region="nz", surprise=True)  # type: ignore[call-arg]


def test_server_list_ignores_unneeded_pia_fields() -> None:
    servers = ServerList.model_validate(
        {
            "groups": {"ignored": True},
            "regions": [
                {
                    "id": "nz",
                    "name": "New Zealand",
                    "country": "NZ",
                    "port_forward": True,
                    "geo": False,
                    "servers": {
                        "meta": [{"ip": "1.2.3.4"}],
                        "wg": [{"ip": "158.173.167.15", "cn": "Server-11531-3a"}],
                    },
                }
            ],
        }
    )
    assert servers.region("nz").name == "New Zealand"
    assert str(servers.region("nz").servers.wg[0].ip) == "158.173.167.15"


def test_registration_validates_wireguard_key() -> None:
    registration = Registration.model_validate(
        {
            "status": "OK",
            "peer_ip": "10.1.2.3/32",
            "server_ip": "158.173.167.15",
            "server_port": 1337,
            "server_vip": "10.1.2.1",
            "server_key": base64.b64encode(bytes(range(32))).decode(),
            "dns_servers": ["10.0.0.242"],
        }
    )
    assert registration.server_port == 1337
