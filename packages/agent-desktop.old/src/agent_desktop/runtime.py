from __future__ import annotations

import html
import os
from pathlib import Path

from .errors import AgentDesktopError
from .models import Config, Session


class RuntimeLayout:
    """Paths and generated configuration owned by one desktop session."""

    def __init__(self, config: Config, session_id: str) -> None:
        self.config = config
        self.session_id = session_id
        self.root = config.runtime_dir(session_id)
        self.config_dir = self.root / "config"
        self.logs_dir = self.root / "logs"
        self.cache_dir = self.root / "cache"
        self.data_dir = self.root / "data"
        self.state_dir = self.root / "state"
        self.dbus_socket = self.root / "bus"
        self.cua_socket = self.root / "cua.sock"
        self.vnc_socket = self.root / "wayvnc.sock"
        self.control_socket = self.root / "control.sock"
        self.wayvnc_control_socket = self.root / "wayvncctl.sock"
        self.browser_profile = self.root / "browser-profile"
        self.browser_overlay_root = config.browser_overlay_dir(session_id)
        self.browser_upper = self.browser_overlay_root / "upper"
        self.browser_work = self.browser_overlay_root / "work"
        self.sway_config = self.config_dir / "sway.conf"
        self.dbus_config = self.config_dir / "dbus.conf"

    def validate_session(self, session: Session, unit: str) -> None:
        expected_paths = {
            "runtime_dir": self.root,
            "cua_socket": self.cua_socket,
            "vnc_socket": self.vnc_socket,
            "control_socket": self.control_socket,
            "browser_profile": self.browser_profile,
        }
        paths_are_owned = all(
            getattr(session, field) in {None, expected}
            for field, expected in expected_paths.items()
        )
        sway_is_owned = session.sway_socket is None or (
            session.sway_socket.parent == self.root
            and session.sway_socket.match("sway-ipc.*.sock")
        )
        wayland_is_owned = session.wayland_display is None or (
            session.wayland_display.startswith("wayland-")
            and session.wayland_display.removeprefix("wayland-").isdigit()
        )
        at_spi_is_owned = session.at_spi_bus_address is None or (
            session.at_spi_bus_address.startswith("unix:path=")
            and Path(
                session.at_spi_bus_address.removeprefix("unix:path=").split(",", 1)[0]
            ).parent
            == self.root / "at-spi"
        )
        if (
            session.unit != unit
            or not paths_are_owned
            or not sway_is_owned
            or not wayland_is_owned
            or session.dbus_address not in {None, f"unix:path={self.dbus_socket}"}
            or not at_spi_is_owned
        ):
            raise AgentDesktopError(
                f"session state has invalid ownership paths: {session.id}",
                "state_error",
            )

    def environment(self) -> dict[str, str]:
        inherited = {
            "HOME",
            "LANG",
            "LANGUAGE",
            "LOCALE_ARCHIVE",
            "LOGNAME",
            "NIX_SSL_CERT_FILE",
            "PATH",
            "SHELL",
            "SSL_CERT_DIR",
            "SSL_CERT_FILE",
            "TERM",
            "TZ",
            "USER",
            "XCURSOR_SIZE",
            "XCURSOR_THEME",
        }
        environment = {
            name: value
            for name, value in os.environ.items()
            if name in inherited or name.startswith("LC_")
        }
        environment.update(
            {
                "XDG_RUNTIME_DIR": str(self.root),
                "XDG_CONFIG_HOME": str(self.config_dir),
                "XDG_CACHE_HOME": str(self.cache_dir),
                "XDG_DATA_HOME": str(self.data_dir),
                "XDG_STATE_HOME": str(self.state_dir),
                "XDG_CURRENT_DESKTOP": "sway",
                "XDG_SESSION_DESKTOP": "sway",
                "XDG_SESSION_TYPE": "wayland",
                "WLR_BACKENDS": "headless",
                "WLR_RENDERER": "pixman",
                "WLR_LIBINPUT_NO_DEVICES": "1",
                "WLR_HEADLESS_OUTPUTS": "1",
                "PIPEWIRE_RUNTIME_DIR": str(self.root),
                "CUA_DRIVER_RS_ENABLE_WAYLAND": "1",
                "CUA_DRIVER_RS_TELEMETRY_ENABLED": "false",
                "NO_AT_BRIDGE": "0",
                "GTK_A11Y": "atspi",
                "GSETTINGS_BACKEND": "memory",
                "PYTHONUNBUFFERED": "1",
            }
        )
        if self.config.xdg_data_dirs:
            environment["XDG_DATA_DIRS"] = ":".join(
                str(path) for path in self.config.xdg_data_dirs
            )
        return environment

    def prepare(self) -> None:
        if self.root.exists() and any(self.root.iterdir()):
            raise AgentDesktopError(
                f"runtime directory is not empty: {self.root}", "runtime_exists"
            )
        for path in self._directories():
            path.mkdir(mode=0o700, parents=True, exist_ok=True)
            os.chmod(path, 0o700)
        for path, content in self._configuration_files().items():
            path.write_text(content)
            os.chmod(path, 0o600)

    def _directories(self) -> tuple[Path, ...]:
        return (
            self.root,
            self.config_dir,
            self.logs_dir,
            self.cache_dir,
            self.data_dir,
            self.state_dir,
            self.browser_profile,
            self.browser_overlay_root,
            self.browser_upper,
            self.browser_work,
            self.config_dir / "xdg-desktop-portal",
            self.config_dir / "xdg-desktop-portal-wlr",
            self.config_dir / "wireplumber" / "wireplumber.conf.d",
        )

    def _configuration_files(self) -> dict[Path, str]:
        config = self.config
        portal_service_dir = html.escape(str(config.portal_service_dir), quote=True)
        dbus_socket = html.escape(str(self.dbus_socket), quote=True)
        return {
            self.sway_config: (
                f"output {config.output_name} mode "
                f"{config.output_width}x{config.output_height}"
                f"@{config.output_refresh_hz}Hz\n"
                "default_border pixel 0\n"
                "focus_follows_mouse no\n"
                "mouse_warping none\n"
                "seat seat0 fallback true\n"
                'seat seat0 attach "*"\n'
                "font pango:sans 10\n"
            ),
            self.config_dir / "xdg-desktop-portal" / "portals.conf": (
                "[preferred]\n"
                "default=none\n"
                "org.freedesktop.impl.portal.ScreenCast=wlr\n"
                "org.freedesktop.impl.portal.Screenshot=wlr\n"
                "org.freedesktop.impl.portal.Access=gtk\n"
            ),
            self.config_dir / "xdg-desktop-portal-wlr" / "config": (
                "[screencast]\n"
                f"output_name={config.output_name}\n"
                f"max_fps={config.portal_max_fps}\n"
                "chooser_type=none\n"
            ),
            self.config_dir
            / "wireplumber"
            / "wireplumber.conf.d"
            / "10-agent-isolation.conf": (
                "wireplumber.profiles = {\n"
                "  main = {\n"
                "    hardware.audio = disabled\n"
                "    hardware.bluetooth = disabled\n"
                "    hardware.video-capture = disabled\n"
                "  }\n"
                "}\n"
            ),
            self.dbus_config: (
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<!DOCTYPE busconfig SYSTEM "busconfig.dtd">\n'
                "<busconfig>\n"
                "  <type>session</type>\n"
                "  <keep_umask/>\n"
                f"  <listen>unix:path={dbus_socket}</listen>\n"
                "  <auth>EXTERNAL</auth>\n"
                f"  <servicedir>{portal_service_dir}</servicedir>\n"
                '  <policy context="default">\n'
                '    <allow send_destination="*" eavesdrop="true"/>\n'
                '    <allow eavesdrop="true"/>\n'
                '    <allow own="*"/>\n'
                "  </policy>\n"
                '  <apparmor mode="disabled"/>\n'
                "</busconfig>\n"
            ),
        }
