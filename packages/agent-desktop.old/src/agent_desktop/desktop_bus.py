from __future__ import annotations

import re
import subprocess
from collections.abc import Callable

from .errors import AgentDesktopError
from .models import Config
from .processes import ProcessGroup, run_command
from .runtime import RuntimeLayout

_BUS_ADDRESS = re.compile(r'"([^"]+)"')
_PORTAL_INTERFACES = (
    "org.freedesktop.portal.ScreenCast",
    "org.freedesktop.portal.Screenshot",
)

WaitUntil = Callable[[Callable[[], bool], str], None]


class DesktopBus:
    """Private D-Bus, accessibility, Secret Service, and portal services."""

    def __init__(
        self,
        config: Config,
        layout: RuntimeLayout,
        processes: ProcessGroup,
        wait_until: WaitUntil,
    ) -> None:
        self.config = config
        self.layout = layout
        self.processes = processes
        self.wait_until = wait_until

    @property
    def address(self) -> str:
        return f"unix:path={self.layout.dbus_socket}"

    def start(self, environment: dict[str, str]) -> None:
        self._spawn(
            "dbus",
            [
                self.config.commands.dbus_daemon,
                f"--config-file={self.layout.dbus_config}",
                "--nofork",
                "--nopidfile",
            ],
            environment,
        )
        self.wait_until(self.layout.dbus_socket.exists, "private D-Bus")

    def start_secret_service(self, environment: dict[str, str]) -> None:
        self._start_service(
            "secret-service-bridge",
            [
                self.config.commands.secret_bridge,
                "--private-address",
                self.address,
                "--host-address",
                self.config.host_dbus_address,
            ],
            environment,
            "org.freedesktop.secrets",
            "shared Secret Service",
        )

    def start_at_spi(self, environment: dict[str, str]) -> str:
        self._spawn(
            "at-spi",
            [self.config.commands.at_spi_bus_launcher, "--launch-immediately"],
            environment,
        )
        self._wait_for_name(self.address, "org.a11y.Bus", "AT-SPI bus")
        for property_name in ("IsEnabled", "ScreenReaderEnabled"):
            self._enable_accessibility_property(property_name, environment)

        result = self._run(
            self._busctl(
                self.address,
                "call",
                "org.a11y.Bus",
                "/org/a11y/bus",
                "org.a11y.Bus",
                "GetAddress",
            ),
            environment,
        )
        match = _BUS_ADDRESS.search(result.stdout)
        if not match:
            raise AgentDesktopError("AT-SPI returned no bus address", "at_spi_failed")
        address = match.group(1)
        registry_environment = environment | {
            "AT_SPI_BUS_ADDRESS": address,
            "DBUS_SESSION_BUS_ADDRESS": address,
        }
        environment["AT_SPI_BUS_ADDRESS"] = address
        self._spawn(
            "at-spi-registry",
            [
                self.config.commands.at_spi_registry,
                "--dbus-name",
                "org.a11y.atspi.Registry",
            ],
            registry_environment,
        )
        self._wait_for_name(
            address,
            "org.a11y.atspi.Registry",
            "AT-SPI registry",
        )
        return address

    def start_portals(self, environment: dict[str, str]) -> None:
        services = (
            (
                "portal-gtk",
                [self.config.commands.portal_gtk],
                "org.freedesktop.impl.portal.desktop.gtk",
                "GTK portal",
            ),
            (
                "portal-wlr",
                [self.config.commands.portal_wlr, "-l", "INFO"],
                "org.freedesktop.impl.portal.desktop.wlr",
                "wlroots portal",
            ),
            (
                "portal",
                [self.config.commands.portal, "-v"],
                "org.freedesktop.portal.Desktop",
                "portal frontend",
            ),
        )
        for name, arguments, bus_name, label in services:
            self._start_service(name, arguments, environment, bus_name, label)
        for interface in _PORTAL_INTERFACES:
            self.wait_until(
                lambda interface=interface: (
                    self._run(
                        self._portal_version(interface), environment, check=False
                    ).returncode
                    == 0
                ),
                f"{interface.rsplit('.', 1)[-1]} portal",
            )

    def secret_service_is_ready(self, environment: dict[str, str]) -> bool:
        return self._name_owned(self.address, "org.freedesktop.secrets", environment)

    def check_portals(self, environment: dict[str, str]) -> None:
        for interface in _PORTAL_INTERFACES:
            self._run(self._portal_version(interface), environment, timeout=5)

    def _enable_accessibility_property(
        self, property_name: str, environment: dict[str, str]
    ) -> None:
        target = (
            "org.a11y.Bus",
            "/org/a11y/bus",
            "org.a11y.Status",
            property_name,
        )
        self._run(
            self._busctl(self.address, "set-property", *target, "b", "true"),
            environment,
        )
        status = self._run(
            self._busctl(self.address, "get-property", *target),
            environment,
        )
        if status.stdout.strip() != "b true":
            raise AgentDesktopError(
                f"AT-SPI status property did not stay enabled: {property_name}",
                "at_spi_failed",
            )

    def _start_service(
        self,
        name: str,
        arguments: list[str],
        environment: dict[str, str],
        bus_name: str,
        label: str,
    ) -> None:
        self._spawn(name, arguments, environment)
        self._wait_for_name(self.address, bus_name, label)

    def _wait_for_name(self, address: str, name: str, label: str) -> None:
        environment = self.layout.environment() | {
            "DBUS_SESSION_BUS_ADDRESS": self.address
        }
        self.wait_until(
            lambda: self._name_owned(address, name, environment),
            label,
        )

    def _name_owned(self, address: str, name: str, environment: dict[str, str]) -> bool:
        result = self._run(
            self._busctl(address, "--no-pager", "--no-legend", "list"),
            environment,
            check=False,
            timeout=5,
        )
        if result.returncode != 0:
            return False
        return any(
            len(fields) >= 2 and fields[0] == name and fields[1].isdigit()
            for fields in (line.split() for line in result.stdout.splitlines())
        )

    def _portal_version(self, interface: str) -> list[str]:
        return self._busctl(
            self.address,
            "get-property",
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            interface,
            "version",
        )

    def _busctl(self, address: str, *arguments: str) -> list[str]:
        return [self.config.commands.busctl, f"--address={address}", *arguments]

    def _spawn(
        self, name: str, arguments: list[str], environment: dict[str, str]
    ) -> None:
        self.processes.spawn_service(
            name,
            arguments,
            environment,
            self.layout.logs_dir / f"{name}.log",
        )

    @staticmethod
    def _run(
        arguments: list[str],
        environment: dict[str, str],
        *,
        check: bool = True,
        timeout: float = 10,
    ) -> subprocess.CompletedProcess[str]:
        return run_command(arguments, environment, check=check, timeout=timeout)
