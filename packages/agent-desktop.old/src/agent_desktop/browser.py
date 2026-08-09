from __future__ import annotations

import json
import logging
import os
import shutil
from collections.abc import Callable

from .errors import AgentDesktopError
from .models import Config
from .processes import run_command
from .runtime import RuntimeLayout

_LOG = logging.getLogger("agent-desktop-session")

Spawn = Callable[[str, list[str], dict[str, str]], None]
WaitUntil = Callable[[Callable[[], bool], str], None]


class BrowserOverlay:
    """Creates and normalizes one disposable Vivaldi overlay."""

    def __init__(self, config: Config, layout: RuntimeLayout) -> None:
        self.config = config
        self.layout = layout

    def start(
        self,
        environment: dict[str, str],
        spawn: Spawn,
        wait_until: WaitUntil,
    ) -> None:
        golden = self.config.vivaldi_golden_profile
        if not (golden / ".agent-desktop-ready").is_file():
            raise AgentDesktopError(
                f"golden Vivaldi profile is not ready: {golden}",
                "golden_profile_unavailable",
            )
        spawn(
            "browser-overlay",
            [
                self.config.commands.fuse_overlayfs,
                "-f",
                "-o",
                (
                    f"lowerdir={golden},upperdir={self.layout.browser_upper},"
                    f"workdir={self.layout.browser_work}"
                ),
                str(self.layout.browser_profile),
            ],
            environment,
        )
        wait_until(
            lambda: os.path.ismount(self.layout.browser_profile),
            "browser profile overlay",
        )
        if not (self.layout.browser_profile / ".agent-desktop-ready").is_file():
            raise AgentDesktopError(
                "browser profile overlay does not expose the golden profile",
                "browser_overlay_failed",
            )
        self._normalize()

    def unmount(self, environment: dict[str, str]) -> None:
        try:
            result = run_command(
                [
                    self.config.commands.fusermount,
                    "-u",
                    "-z",
                    str(self.layout.browser_profile),
                ],
                environment,
                check=False,
                timeout=self.config.stop_timeout_seconds,
            )
            if result.returncode != 0 and os.path.ismount(self.layout.browser_profile):
                _LOG.warning("could not unmount browser profile: %s", result.stderr)
        except AgentDesktopError as error:
            _LOG.warning("could not unmount browser profile: %s", error)

    def _normalize(self) -> None:
        shutil.rmtree(self.layout.browser_profile / "Crash Reports", ignore_errors=True)
        preferences = self.layout.browser_profile / "Default" / "Preferences"
        if not preferences.is_file():
            return
        try:
            document = json.loads(preferences.read_text())
            profile = document.setdefault("profile", {})
            if not isinstance(profile, dict):
                raise TypeError("profile preference is not an object")
            profile["exit_type"] = "Normal"
            vivaldi = document.get("vivaldi")
            if isinstance(vivaldi, dict) and isinstance(vivaldi.get("startup"), dict):
                vivaldi["startup"].pop("crash_detection_last_seen_version", None)
            temporary = preferences.with_name(".Preferences.agent-desktop.tmp")
            temporary.write_text(
                json.dumps(document, ensure_ascii=False, separators=(",", ":"))
            )
            os.chmod(temporary, 0o600)
            os.replace(temporary, preferences)
        except (OSError, ValueError, TypeError) as error:
            raise AgentDesktopError(
                f"could not normalize disposable browser profile: {error}",
                "browser_profile_failed",
            ) from error
