from __future__ import annotations

import json
import os
import socket
import subprocess
import time
import uuid
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit

from .models import (
    AgentDesktopError,
    Config,
    Launch,
    Session,
    State,
    cleanup_session,
    read_session,
    remove_tree,
    state_lock,
    unit_name,
    validate_id,
    write_json,
)

_LIVE = {"activating", "active", "reloading", "deactivating"}
_TERMINAL = {"inactive", "failed"}
_MAX_FRAME = 64 * 1024
_MAX_ARGUMENTS = 256
_MAX_ARGUMENT_BYTES = 32 * 1024


@dataclass(frozen=True, slots=True)
class UnitStatus:
    load: str
    active: str

    @property
    def live(self) -> bool:
        return self.active in _LIVE

    @property
    def terminal(self) -> bool:
        return self.load == "not-found" or self.active in _TERMINAL


def run(
    arguments: Sequence[str],
    *,
    check: bool = True,
    timeout: float = 30,
    environment: dict[str, str] | None = None,
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
    except FileNotFoundError as error:
        raise AgentDesktopError(f"required command not found: {arguments[0]}", "missing_command") from error
    except OSError as error:
        raise AgentDesktopError(f"could not run {arguments[0]}: {error}", "command_failed") from error
    except subprocess.TimeoutExpired as error:
        raise AgentDesktopError(f"command timed out: {arguments[0]}", "command_timeout") from error
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or error.stdout.strip()
        raise AgentDesktopError(
            f"{arguments[0]} failed" + (f": {detail}" if detail else ""),
            "command_failed",
        ) from error


class SessionManager:
    def __init__(self, config: Config, config_path: Path) -> None:
        self.config = config
        self.config_path = config_path.resolve()

    def create(self, agent_id: str, session_id: str | None = None) -> Session:
        agent_id = self._id(agent_id, "agent ID")
        selected = self._id(session_id or self._new_id(agent_id), "session ID")
        with state_lock(self.config):
            sessions = self._records(tolerate_invalid=False)
            if self.config.max_sessions is not None and (
                sum(session.state.consumes_capacity for session in sessions) >= self.config.max_sessions
            ):
                raise AgentDesktopError(
                    f"agent desktop capacity reached ({self.config.max_sessions})",
                    "capacity_exhausted",
                )
            path = self.config.state_path(selected)
            if path.exists() and read_session(self.config, path).state != State.STOPPED:
                raise AgentDesktopError(f"session already exists: {selected}", "session_exists")
            self._cleanup(selected)
            now = time.time()
            session = Session(
                id=selected,
                agent_id=agent_id,
                unit=unit_name(selected),
                state=State.STARTING,
                created_at=now,
                updated_at=now,
                runtime_dir=self.config.runtime_dir(selected),
            )
            write_json(path, session)
            try:
                run(self._start_arguments(session), timeout=10)
            except AgentDesktopError as error:
                start_error = error
            else:
                start_error = None
        if start_error is not None:
            self._fail_create(session, start_error)
            raise start_error
        try:
            return self._wait_ready(session)
        except AgentDesktopError as error:
            self._fail_create(session, error)
            raise

    def status(self, session_id: str) -> Session:
        selected = self._id(session_id, "session ID")
        with state_lock(self.config):
            return self._reconcile(read_session(self.config, self.config.state_path(selected)))

    def list(self) -> list[Session]:
        with state_lock(self.config):
            return self._records(tolerate_invalid=True)

    def destroy(self, session_id: str) -> Session:
        selected = self._id(session_id, "session ID")
        path = self.config.state_path(selected)
        with state_lock(self.config):
            session = read_session(self.config, path)
            if session.state != State.STOPPED:
                write_json(
                    path,
                    session.model_copy(update={"state": State.STOPPING, "updated_at": time.time()}),
                )
        self._stop(session.unit)
        self._cleanup(selected)
        with state_lock(self.config):
            try:
                current = read_session(self.config, path)
            except AgentDesktopError:
                current = session
            now = time.time()
            stopped = current.model_copy(
                update={
                    "state": State.STOPPED,
                    "updated_at": now,
                    "stopped_at": current.stopped_at or now,
                    "message": None,
                }
            )
            write_json(path, stopped)
            return stopped

    def launch(self, session_id: str, arguments: Sequence[str]) -> Launch:
        values = self._arguments(arguments)
        return self._send(self._launchable(session_id), values)

    def launch_browser(self, session_id: str, url: str) -> Launch:
        session = self._launchable(session_id)
        self._browser_url(url)
        assert session.browser_profile is not None
        return self._send(
            session,
            (
                self.config.commands.vivaldi,
                f"--user-data-dir={session.browser_profile}",
                "--no-first-run",
                "--no-default-browser-check",
                "--force-renderer-accessibility",
                "--ozone-platform=wayland",
                "--new-window",
                url,
            ),
        )

    def _records(self, *, tolerate_invalid: bool) -> list[Session]:
        sessions: list[Session] = []
        for path in sorted((self.config.state_root / "sessions").glob("*.json")):
            try:
                sessions.append(self._reconcile(read_session(self.config, path)))
            except AgentDesktopError as error:
                if not tolerate_invalid or error.code != "state_error":
                    raise
        return sorted(sessions, key=lambda session: session.created_at, reverse=True)

    def _reconcile(self, session: Session) -> Session:
        if not session.state.consumes_capacity:
            return session
        status = self._unit_status(session.unit)
        if status.live:
            return session
        if not status.terminal:
            raise AgentDesktopError(
                f"unknown unit state for {session.id}: {status.active}",
                "control_plane_error",
            )
        stopped = session.state == State.STOPPING
        now = time.time()
        updated = session.model_copy(
            update={
                "state": State.STOPPED if stopped else State.FAILED,
                "updated_at": now,
                "stopped_at": now,
                "message": None if stopped else "session unit is no longer active",
            }
        )
        self._cleanup(session.id)
        write_json(self.config.state_path(session.id), updated)
        return updated

    def _wait_ready(self, session: Session) -> Session:
        deadline = time.monotonic() + self.config.create_timeout_seconds + 2
        missing_grace = time.monotonic() + 2
        while time.monotonic() < deadline:
            with state_lock(self.config):
                current = read_session(self.config, self.config.state_path(session.id))
            if current.state in {State.FAILED, State.STOPPED}:
                raise AgentDesktopError(
                    current.message or f"session stopped while starting: {session.id}",
                    "session_start_failed",
                )
            status = self._unit_status(session.unit)
            if current.state.launchable and status.live:
                return current
            if status.live or (status.load == "not-found" and time.monotonic() < missing_grace):
                time.sleep(0.05)
                continue
            raise AgentDesktopError(
                f"session unit stopped while starting: {session.id}",
                "session_start_failed",
            )
        raise AgentDesktopError(
            f"timed out waiting for session readiness: {session.id}",
            "readiness_timeout",
        )

    def _fail_create(self, session: Session, error: AgentDesktopError) -> None:
        cleanup_error: AgentDesktopError | None = None
        try:
            self._stop(session.unit)
        except AgentDesktopError as failure:
            cleanup_error = failure
        if cleanup_error is None:
            try:
                self._cleanup(session.id)
            except AgentDesktopError as failure:
                cleanup_error = failure
        with state_lock(self.config):
            path = self.config.state_path(session.id)
            try:
                current = read_session(self.config, path)
            except AgentDesktopError:
                current = session
            now = time.time()
            message = str(error)
            if cleanup_error:
                message += f"; cleanup failed: {cleanup_error}"
            write_json(
                path,
                current.model_copy(
                    update={
                        "state": State.FAILED,
                        "updated_at": now,
                        "stopped_at": None if cleanup_error else now,
                        "message": message,
                    }
                ),
            )
        if cleanup_error:
            raise AgentDesktopError(message, "cleanup_failed") from error

    def _launchable(self, session_id: str) -> Session:
        session = self.status(session_id)
        if not session.state.launchable:
            raise AgentDesktopError(
                f"session cannot launch applications while {session.state}",
                "session_not_ready",
            )
        expected = self.config.runtime_dir(session.id) / "control.sock"
        if session.control_socket != expected or not expected.is_socket():
            raise AgentDesktopError(
                "session application control endpoint is unavailable",
                "control_unavailable",
            )
        return session

    @staticmethod
    def _send(session: Session, arguments: tuple[str, ...]) -> Launch:
        assert session.control_socket is not None
        request = {"version": 1, "operation": "launch", "arguments": list(arguments)}
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                connection.settimeout(5)
                connection.connect(str(session.control_socket))
                connection.sendall(json.dumps(request, separators=(",", ":")).encode() + b"\n")
                document = json.loads(_read_frame(connection, "response"))
        except AgentDesktopError:
            raise
        except (OSError, ValueError, UnicodeError) as error:
            raise AgentDesktopError(f"could not launch application: {error}", "control_failed") from error
        if not isinstance(document, dict) or type(document.get("ok")) is not bool:
            raise AgentDesktopError("invalid application control response", "control_failed")
        if document["ok"] is False:
            if (
                set(document) != {"ok", "code", "message"}
                or document.get("code") != "launch_failed"
                or not isinstance(document.get("message"), str)
            ):
                raise AgentDesktopError("invalid application control response", "control_failed")
            raise AgentDesktopError(document["message"], "launch_failed")
        if set(document) != {"ok", "pid", "arguments"} or type(document.get("pid")) is not int:
            raise AgentDesktopError("invalid application control response", "control_failed")
        if document["pid"] <= 0 or document.get("arguments") != list(arguments):
            raise AgentDesktopError("application control response changed the command", "control_failed")
        return Launch(pid=document["pid"], arguments=arguments)

    def _unit_status(self, unit: str) -> UnitStatus:
        result = run(
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
        properties = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
        if not properties.get("LoadState") or not properties.get("ActiveState"):
            raise AgentDesktopError(f"systemd returned incomplete state for {unit}", "control_plane_error")
        return UnitStatus(properties["LoadState"], properties["ActiveState"])

    def _stop(self, unit: str) -> None:
        status = self._unit_status(unit)
        if status.terminal:
            return
        if not status.live:
            raise AgentDesktopError(
                f"cannot stop unit in unknown state: {status.active}",
                "control_plane_error",
            )
        result = run(
            [self.config.commands.systemctl, "--user", "stop", unit],
            check=False,
            timeout=self.config.stop_timeout_seconds + 2,
        )
        if result.returncode != 0:
            raise AgentDesktopError(
                f"failed to stop session unit: {result.stderr.strip()}",
                "control_plane_error",
            )
        deadline = time.monotonic() + self.config.stop_timeout_seconds + 2
        while time.monotonic() < deadline:
            if self._unit_status(unit).terminal:
                return
            time.sleep(0.05)
        raise AgentDesktopError(f"session unit did not stop: {unit}", "stop_timeout")

    def _cleanup(self, session_id: str) -> None:
        cleanup_session(self.config, session_id)
        remove_tree(self.config.runtime_dir(session_id))

    def _start_arguments(self, session: Session) -> list[str]:
        runtime_base = Path(os.getenv("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
        try:
            runtime_name = session.runtime_dir.relative_to(runtime_base)
        except ValueError as error:
            raise AgentDesktopError(f"runtime directory must be below {runtime_base}", "config_error") from error
        cleanup = (
            f"{self.config.commands.systemd_run} --user --wait --collect --quiet "
            f"--unit=agent-desktop-cleanup-{session.id}.service {self.config.commands.cleanup} "
            f"--config {self.config_path} --session-id {session.id}"
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
            f"--property=RuntimeDirectory={runtime_name}",
            "--property=RuntimeDirectoryMode=0700",
            f"--property=ExecStopPost={cleanup}",
            f"--property=TimeoutStopSec={self.config.stop_timeout_seconds}",
            f"--property=RuntimeMaxSec={self.config.runtime_limit_seconds}",
            "--property=UMask=0077",
            self.config.commands.session,
            "--config",
            str(self.config_path),
            "--session-id",
            session.id,
            "--agent-id",
            session.agent_id,
        ]

    @staticmethod
    def _arguments(arguments: Sequence[str]) -> tuple[str, ...]:
        values = tuple(arguments)
        if not 1 <= len(values) <= _MAX_ARGUMENTS:
            raise AgentDesktopError(f"command must contain 1-{_MAX_ARGUMENTS} arguments", "invalid_command")
        if any(not isinstance(value, str) or not value or "\0" in value for value in values):
            raise AgentDesktopError(
                "command arguments must be non-empty strings without NULs",
                "invalid_command",
            )
        if sum(len(value.encode()) for value in values) > _MAX_ARGUMENT_BYTES:
            raise AgentDesktopError("command arguments are too large", "invalid_command")
        return values

    @staticmethod
    def _browser_url(url: str) -> None:
        if not url or "\0" in url or len(url.encode()) > 8192:
            raise AgentDesktopError("invalid browser destination", "invalid_url")
        parsed = urlsplit(url)
        valid = (
            parsed.scheme == "about"
            or (parsed.scheme in {"http", "https"} and bool(parsed.netloc))
            or (parsed.scheme == "file" and parsed.netloc in {"", "localhost"} and parsed.path.startswith("/"))
        )
        if not valid:
            raise AgentDesktopError(
                "browser URL must use https, http, about, or an absolute file URL",
                "invalid_url",
            )

    @staticmethod
    def _id(value: str, label: str) -> str:
        try:
            return validate_id(value, label)
        except ValueError as error:
            raise AgentDesktopError(str(error), "invalid_id") from error

    @staticmethod
    def _new_id(agent_id: str) -> str:
        prefix = agent_id.lower().replace("_", "-").replace(".", "-")[:48]
        return f"{prefix}-{uuid.uuid4().hex[:8]}"


def _read_frame(connection: socket.socket, kind: str) -> bytes:
    payload = bytearray()
    while b"\n" not in payload:
        chunk = connection.recv(4096)
        if not chunk:
            raise ValueError(f"control {kind} ended before a newline")
        payload.extend(chunk)
        if len(payload) > _MAX_FRAME:
            raise ValueError(f"control {kind} is too large")
    line, remainder = bytes(payload).split(b"\n", 1)
    if remainder:
        raise ValueError(f"control {kind} contains trailing data")
    return line
