from __future__ import annotations

import os
import subprocess
import time
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from .errors import AgentDesktopError
from .models import Config, Session

_LIVE_STATES = {"activating", "active", "reloading", "deactivating"}
_TERMINAL_STATES = {"inactive", "failed"}


@dataclass(frozen=True, slots=True)
class UnitStatus:
    load_state: str
    active_state: str

    @property
    def live(self) -> bool:
        return self.active_state in _LIVE_STATES

    @property
    def terminal(self) -> bool:
        return self.load_state == "not-found" or self.active_state in _TERMINAL_STATES


class CommandRunner(Protocol):
    def run(
        self,
        arguments: Sequence[str],
        *,
        check: bool = True,
        timeout: float = 30,
    ) -> subprocess.CompletedProcess[str]: ...


class Runner:
    def run(
        self,
        arguments: Sequence[str],
        *,
        check: bool = True,
        timeout: float = 30,
    ) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(
                arguments,
                capture_output=True,
                check=check,
                text=True,
                timeout=timeout,
            )
        except FileNotFoundError as error:
            raise AgentDesktopError(
                f"required command not found: {arguments[0]}", "missing_command"
            ) from error
        except subprocess.TimeoutExpired as error:
            raise AgentDesktopError(
                f"command timed out: {arguments[0]}", "command_timeout"
            ) from error
        except subprocess.CalledProcessError as error:
            detail = error.stderr.strip() or error.stdout.strip()
            raise AgentDesktopError(
                f"{arguments[0]} failed" + (f": {detail}" if detail else ""),
                "command_failed",
            ) from error


class UserUnitController:
    """Starts and stops the transient systemd unit that owns a desktop."""

    def __init__(
        self,
        config: Config,
        runner: CommandRunner,
        config_path: Path,
        session_command: str,
        cleanup_command: str,
    ) -> None:
        self.config = config
        self.runner = runner
        self.config_path = config_path
        self.session_command = session_command
        self.cleanup_command = cleanup_command

    def start(self, session: Session) -> None:
        self.runner.run(self._start_arguments(session), timeout=10)

    def status(self, unit: str) -> UnitStatus:
        result = self.runner.run(
            [
                self.config.commands.systemctl,
                "--user",
                "show",
                unit,
                "--property=LoadState",
                "--property=ActiveState",
                "--no-pager",
            ],
            check=False,
            timeout=5,
        )
        if result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip()
            raise AgentDesktopError(
                "cannot query user unit state" + (f": {detail}" if detail else ""),
                "control_plane_error",
            )
        properties = dict(
            line.split("=", 1) for line in result.stdout.splitlines() if "=" in line
        )
        load_state = properties.get("LoadState")
        active_state = properties.get("ActiveState")
        if not load_state or not active_state:
            raise AgentDesktopError(
                f"systemd returned incomplete state for {unit}",
                "control_plane_error",
            )
        return UnitStatus(load_state, active_state)

    def stop(self, unit: str) -> None:
        status = self.status(unit)
        if status.terminal:
            return
        if not status.live:
            raise AgentDesktopError(
                f"cannot stop unit in unknown state: {status.active_state}",
                "control_plane_error",
            )
        result = self.runner.run(
            [self.config.commands.systemctl, "--user", "stop", unit],
            check=False,
            timeout=self.config.stop_timeout_seconds + 2,
        )
        if result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip()
            raise AgentDesktopError(
                "failed to stop session unit" + (f": {detail}" if detail else ""),
                "control_plane_error",
            )
        deadline = time.monotonic() + self.config.stop_timeout_seconds + 2
        while time.monotonic() < deadline:
            if self.status(unit).terminal:
                return
            time.sleep(0.05)
        raise AgentDesktopError(f"session unit did not stop: {unit}", "stop_timeout")

    def _start_arguments(self, session: Session) -> list[str]:
        cleanup = (
            f"{self.config.commands.systemd_run} --user --wait --collect --quiet "
            f"--unit=agent-desktop-cleanup-{session.id}.service "
            f"{self.cleanup_command} --config {self.config_path} "
            f"--session-id {session.id}"
        )
        return [
            self.config.commands.systemd_run,
            "--user",
            "--collect",
            "--quiet",
            "--no-block",
            f"--unit={session.unit}",
            f"--description=Agent desktop for {session.agent_id}",
            "--service-type=notify",
            "--property=NotifyAccess=main",
            "--property=KillMode=control-group",
            f"--property=RuntimeDirectory={self._runtime_directory_name(session)}",
            "--property=RuntimeDirectoryMode=0700",
            f"--property=ExecStopPost={cleanup}",
            f"--property=TimeoutStopSec={self.config.stop_timeout_seconds}",
            f"--property=RuntimeMaxSec={self.config.runtime_limit_seconds}",
            "--property=UMask=0077",
            self.session_command,
            "--config",
            str(self.config_path),
            "--session-id",
            session.id,
            "--agent-id",
            session.agent_id,
        ]

    @staticmethod
    def _runtime_root() -> Path:
        return Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))

    def _runtime_directory_name(self, session: Session) -> str:
        runtime_root = self._runtime_root()
        try:
            return session.runtime_dir.relative_to(runtime_root).as_posix()
        except ValueError as error:
            raise AgentDesktopError(
                f"runtime directory must be below {runtime_root}", "config_error"
            ) from error
