from __future__ import annotations

import subprocess
import time
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import TextIO

from .errors import AgentDesktopError


@dataclass(slots=True)
class Child:
    name: str
    process: subprocess.Popen[str]
    log: TextIO
    critical: bool = True


class ProcessGroup:
    """Owns session children, their logs, and their shutdown order."""

    def __init__(self) -> None:
        self.children: list[Child] = []

    def spawn(
        self,
        name: str,
        arguments: Sequence[str],
        environment: dict[str, str],
        log_path: Path,
        *,
        critical: bool = True,
    ) -> subprocess.Popen[str]:
        log = log_path.open("a", encoding="utf-8")
        try:
            process = subprocess.Popen(
                arguments,
                env=environment,
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
            )
        except OSError:
            log.close()
            raise
        self.children.append(Child(name, process, log, critical))
        return process

    def spawn_service(
        self,
        name: str,
        arguments: Sequence[str],
        environment: dict[str, str],
        log_path: Path,
    ) -> None:
        try:
            self.spawn(name, arguments, environment, log_path)
        except OSError as error:
            raise AgentDesktopError(
                f"could not start {name}: {error}", "child_start_failed"
            ) from error

    def reap(self) -> None:
        for child in list(self.children):
            return_code = child.process.poll()
            if return_code is None:
                continue
            if child.critical:
                raise AgentDesktopError(
                    f"{child.name} exited unexpectedly with status {return_code}",
                    "child_exited",
                )
            child.log.close()
            self.children.remove(child)

    def ensure_running_while_waiting(self, label: str) -> None:
        for child in self.children:
            return_code = child.process.poll()
            if return_code is not None:
                raise AgentDesktopError(
                    f"{child.name} exited while waiting for {label} "
                    f"(status {return_code})",
                    "child_exited",
                )

    def stop(self, children: list[Child], timeout: float) -> None:
        for child in children:
            if child.process.poll() is None:
                child.process.terminate()
        deadline = time.monotonic() + timeout
        for child in children:
            remaining = max(0.01, deadline - time.monotonic())
            try:
                child.process.wait(timeout=remaining)
            except subprocess.TimeoutExpired:
                child.process.kill()
                child.process.wait()
            child.log.close()


def run_command(
    arguments: Sequence[str],
    environment: dict[str, str],
    *,
    check: bool = True,
    timeout: float = 10,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            arguments,
            env=environment,
            capture_output=True,
            check=check,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError) as error:
        detail = (
            error.stderr.strip() or error.stdout.strip()
            if isinstance(error, subprocess.CalledProcessError)
            else str(error)
        )
        raise AgentDesktopError(
            f"{arguments[0]} failed" + (f": {detail}" if detail else ""),
            "command_failed",
        ) from error
