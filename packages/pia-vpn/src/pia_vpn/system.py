from __future__ import annotations

import os
import subprocess
import time
from collections.abc import Sequence
from dataclasses import dataclass

from .errors import PiaVpnError
from .models import Config, Registration


class Runner:
    def run(
        self,
        arguments: Sequence[str],
        *,
        input: bytes | None = None,
        check: bool = True,
        timeout: float = 30,
    ) -> subprocess.CompletedProcess[bytes]:
        try:
            return subprocess.run(
                arguments,
                input=input,
                capture_output=True,
                check=check,
                timeout=timeout,
            )
        except FileNotFoundError as error:
            raise PiaVpnError(
                f"required command not found: {arguments[0]}", "missing_command"
            ) from error
        except subprocess.TimeoutExpired as error:
            raise PiaVpnError(
                f"command timed out: {arguments[0]}", "command_timeout"
            ) from error
        except subprocess.CalledProcessError as error:
            detail = error.stderr.decode(errors="replace").strip()
            raise PiaVpnError(
                f"{arguments[0]} failed" + (f": {detail}" if detail else ""),
                "command_failed",
            ) from error


@dataclass(frozen=True, slots=True)
class KeyPair:
    private: str
    public: str


class SystemNetwork:
    def __init__(self, config: Config, runner: Runner | None = None) -> None:
        self.config = config
        self.runner = runner or Runner()

    def keys(self) -> KeyPair:
        private = self.runner.run(
            ["wg", "genkey"], timeout=self.config.command_timeout
        ).stdout.strip()
        public = self.runner.run(
            ["wg", "pubkey"], input=private + b"\n", timeout=self.config.command_timeout
        ).stdout.strip()
        try:
            return KeyPair(private.decode(), public.decode())
        except UnicodeDecodeError as error:
            raise PiaVpnError(
                "wg returned an invalid key", "wireguard_error"
            ) from error

    def connect(self, keys: KeyPair, registration: Registration) -> None:
        self.disconnect(ignore_errors=True)
        dns = ", ".join(str(address) for address in registration.dns_servers)
        configuration = f"""[Interface]
Address = {registration.peer_ip}
PrivateKey = {keys.private}
DNS = {dns}

[Peer]
PersistentKeepalive = 25
PublicKey = {registration.server_key}
AllowedIPs = 0.0.0.0/0
Endpoint = {registration.server_ip}:{registration.server_port}
"""
        path = self.config.wireguard_config_path
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, "w") as stream:
            stream.write(configuration)
            stream.flush()
            os.fsync(stream.fileno())
        self.runner.run(
            ["wg-quick", "up", str(path)], timeout=self.config.command_timeout
        )

    def disconnect(self, *, ignore_errors: bool = False) -> None:
        self.runner.run(
            ["wg-quick", "down", str(self.config.wireguard_config_path)],
            check=not ignore_errors,
            timeout=self.config.command_timeout,
        )
        try:
            self.config.wireguard_config_path.unlink()
        except FileNotFoundError:
            pass

    def handshake_age(self) -> float | None:
        result = self.runner.run(
            ["wg", "show", self.config.interface, "latest-handshakes"],
            check=False,
            timeout=self.config.command_timeout,
        )
        if result.returncode != 0:
            return None
        values = result.stdout.split()
        if len(values) < 2:
            return None
        try:
            timestamp = int(values[-1])
        except ValueError:
            return None
        if timestamp <= 0:
            return float("inf")
        return max(0, time.time() - timestamp)

    def protect(self, endpoint: tuple[str, int] | None = None) -> None:
        if not self.config.kill_switch:
            return
        exists = (
            self.runner.run(
                ["nft", "list", "table", "inet", "pia_vpn"],
                check=False,
                timeout=self.config.command_timeout,
            ).returncode
            == 0
        )
        element = f"{endpoint[0]} . {endpoint[1]}" if endpoint else ""
        if exists:
            commands = ["flush set inet pia_vpn endpoints"]
            if element:
                commands.append(f"add element inet pia_vpn endpoints {{ {element} }}")
            self._nft("\n".join(commands))
            return

        lan = ""
        if self.config.allow_lan:
            lan = """ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 } accept
    ip6 daddr fe80::/10 accept"""
        initial = f"elements = {{ {element} }}" if element else ""
        self._nft(f"""table inet pia_vpn {{
  set endpoints {{ type ipv4_addr . inet_service; {initial} }}
  chain output {{
    type filter hook output priority -150; policy accept;
    oifname "lo" accept
    ct state established,related accept
    udp sport 68 udp dport 67 accept
    meta skuid {os.geteuid()} accept
    ip daddr . udp dport @endpoints accept
    oifname "{self.config.interface}" accept
    {lan}
    reject
  }}
  chain forward {{
    type filter hook forward priority -150; policy accept;
    ct state established,related accept
    oifname "{self.config.interface}" accept
    {lan}
    reject
  }}
}}""")

    def unprotect(self) -> None:
        if self.config.kill_switch:
            self.runner.run(
                ["nft", "delete", "table", "inet", "pia_vpn"],
                check=False,
                timeout=self.config.command_timeout,
            )

    def _nft(self, script: str) -> None:
        self.runner.run(
            ["nft", "--file", "-"],
            input=(script + "\n").encode(),
            timeout=self.config.command_timeout,
        )
