from __future__ import annotations

import shutil
import sys
import time
import uuid
from collections.abc import Sequence
from pathlib import Path

from .control import ControlClient, LaunchRequest
from .errors import AgentDesktopError
from .models import Config, LaunchResult, Session, SessionState, validate_id
from .runtime import RuntimeLayout
from .storage import read_model, state_lock, write_json
from .systemd import CommandRunner, Runner, UserUnitController


def _checked_id(value: str, label: str) -> str:
    try:
        return validate_id(value, label)
    except ValueError as error:
        raise AgentDesktopError(str(error), "invalid_id") from error


class SessionManager:
    def __init__(
        self,
        config: Config,
        config_path: Path,
        runner: CommandRunner | None = None,
        session_command: str | None = None,
        cleanup_command: str | None = None,
    ) -> None:
        self.config = config
        selected_runner = runner or Runner()
        sibling_command = Path(sys.argv[0]).with_name("agent-desktop-session")
        selected_command = session_command or (
            str(sibling_command)
            if sibling_command.is_file()
            else shutil.which("agent-desktop-session")
        )
        if not selected_command:
            raise AgentDesktopError(
                "agent-desktop-session is not available", "missing_command"
            )
        selected_cleanup = cleanup_command or str(
            Path(selected_command).with_name("agent-desktop-cleanup")
        )
        self.units = UserUnitController(
            config,
            selected_runner,
            config_path,
            selected_command,
            selected_cleanup,
        )

    def create(self, agent_id: str, session_id: str | None = None) -> Session:
        _checked_id(agent_id, "agent ID")
        selected_id = _checked_id(
            session_id or self._new_session_id(agent_id), "session ID"
        )

        launch_error: AgentDesktopError | None = None
        with state_lock(self.config.state_root):
            active_count = sum(
                session.state.consumes_capacity for session in self._sessions()
            )
            if active_count >= self.config.max_sessions:
                raise AgentDesktopError(
                    f"agent desktop capacity reached ({self.config.max_sessions})",
                    "capacity_exhausted",
                )
            state_path = self.config.state_path(selected_id)
            if state_path.exists():
                existing = self._read_session(selected_id)
                if existing.state != SessionState.STOPPED:
                    raise AgentDesktopError(
                        f"session already exists: {selected_id}", "session_exists"
                    )

            now = time.time()
            session = Session(
                id=selected_id,
                agent_id=agent_id,
                unit=self._unit_name(selected_id),
                state=SessionState.STARTING,
                created_at=now,
                updated_at=now,
                runtime_dir=self.config.runtime_dir(selected_id),
            )
            write_json(state_path, session)
            try:
                self.units.start(session)
            except AgentDesktopError as error:
                launch_error = error

        if launch_error is not None:
            self._cleanup_failed_create(session, launch_error)
            raise launch_error

        try:
            return self._wait_for_ready(session)
        except AgentDesktopError as error:
            self._cleanup_failed_create(session, error)
            raise

    def _wait_for_ready(self, session: Session) -> Session:
        deadline = time.monotonic() + self.config.create_timeout_seconds + 2
        missing_unit_grace = time.monotonic() + 2
        while time.monotonic() < deadline:
            with state_lock(self.config.state_root):
                current = self._read_session(session.id)
            if current.state.launchable:
                return current
            if current.state == SessionState.FAILED:
                raise AgentDesktopError(
                    current.message or f"session failed to start: {session.id}",
                    "session_start_failed",
                )
            if current.state == SessionState.STOPPED:
                raise AgentDesktopError(
                    f"session was stopped during startup: {session.id}",
                    "session_stopped",
                )

            unit_status = self.units.status(session.unit)
            if unit_status.live:
                time.sleep(0.05)
                continue
            if (
                unit_status.load_state == "not-found"
                and time.monotonic() < missing_unit_grace
            ):
                time.sleep(0.05)
                continue
            if unit_status.terminal:
                raise AgentDesktopError(
                    current.message
                    or f"session unit stopped during startup: {session.id}",
                    "session_start_failed",
                )
            raise AgentDesktopError(
                f"unknown unit state for {session.id}: {unit_status.active_state}",
                "control_plane_error",
            )
        raise AgentDesktopError(
            f"timed out waiting for session readiness: {session.id}",
            "readiness_timeout",
        )

    def _cleanup_failed_create(
        self, session: Session, error: AgentDesktopError
    ) -> None:
        cleanup_error: AgentDesktopError | None = None
        try:
            self.units.stop(session.unit)
        except AgentDesktopError as stop_error:
            cleanup_error = stop_error

        with state_lock(self.config.state_root):
            state_path = self.config.state_path(session.id)
            current = session
            if state_path.exists():
                current = self._read_session(session.id)
            if current.state == SessionState.STOPPED and cleanup_error is None:
                return
            message = current.message or str(error)
            if cleanup_error:
                message = f"{message}; cleanup failed: {cleanup_error}"
            failed = current.model_copy(
                update={
                    "state": SessionState.FAILED,
                    "updated_at": time.time(),
                    "stopped_at": time.time() if cleanup_error is None else None,
                    "message": message,
                }
            )
            write_json(state_path, failed)
        if cleanup_error:
            raise AgentDesktopError(message, "cleanup_failed") from error

    def status(self, session_id: str) -> Session:
        _checked_id(session_id, "session ID")
        with state_lock(self.config.state_root):
            return self._reconcile(self._read_session(session_id))

    def list(self) -> list[Session]:
        with state_lock(self.config.state_root):
            return self._sessions()

    def launch(self, session_id: str, arguments: Sequence[str]) -> LaunchResult:
        return self._send_launch(
            self._launchable_session(session_id),
            LaunchRequest.from_arguments(arguments),
        )

    def launch_browser(self, session_id: str, url: str) -> LaunchResult:
        session = self._launchable_session(session_id)
        if session.browser_profile is None:
            raise AgentDesktopError(
                "session has no disposable browser profile", "browser_unavailable"
            )
        if (
            not url
            or "\x00" in url
            or not url.startswith(("https://", "http://", "about:", "file://"))
        ):
            raise AgentDesktopError(
                "browser URL must use https, http, about, or file",
                "invalid_url",
            )
        return self._send_launch(
            session,
            LaunchRequest.from_arguments(
                [
                    self.config.commands.vivaldi,
                    f"--user-data-dir={session.browser_profile}",
                    "--no-first-run",
                    "--no-default-browser-check",
                    "--force-renderer-accessibility",
                    "--new-window",
                    url,
                ]
            ),
        )

    def _launchable_session(self, session_id: str) -> Session:
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
    def _send_launch(session: Session, request: LaunchRequest) -> LaunchResult:
        assert session.control_socket is not None
        return ControlClient.launch(session.control_socket, request)

    def destroy(self, session_id: str) -> Session:
        _checked_id(session_id, "session ID")
        with state_lock(self.config.state_root):
            path = self.config.state_path(session_id)
            session = self._read_session(session_id)
            if session.state != SessionState.STOPPED:
                stopping = session.model_copy(
                    update={"state": SessionState.STOPPING, "updated_at": time.time()}
                )
                write_json(path, stopping)
                self.units.stop(session.unit)
            self._remove_resources(session.id)
            current = self._read_session(session.id)
            stopped = current.model_copy(
                update={
                    "state": SessionState.STOPPED,
                    "updated_at": time.time(),
                    "stopped_at": current.stopped_at or time.time(),
                    "message": None,
                }
            )
            write_json(path, stopped)
            return stopped

    def _sessions(self) -> list[Session]:
        paths = sorted(self.config.sessions_state_dir.glob("*.json"))
        sessions = (self._reconcile(self._read_session_path(path)) for path in paths)
        return sorted(sessions, key=lambda session: session.created_at, reverse=True)

    def _reconcile(self, session: Session) -> Session:
        if not session.state.needs_reconciliation:
            return session
        unit_status = self.units.status(session.unit)
        if unit_status.live:
            return session
        if not unit_status.terminal:
            raise AgentDesktopError(
                f"unknown unit state for {session.id}: {unit_status.active_state}",
                "control_plane_error",
            )
        state = (
            SessionState.STOPPED
            if session.state == SessionState.STOPPING
            else SessionState.FAILED
        )
        updated = session.model_copy(
            update={
                "state": state,
                "updated_at": time.time(),
                "stopped_at": time.time(),
                "message": None
                if state == SessionState.STOPPED
                else "session unit is no longer active",
            }
        )
        write_json(self.config.state_path(session.id), updated)
        self._remove_resources(session.id)
        return updated

    def _read_session(self, session_id: str) -> Session:
        return self._read_session_path(self.config.state_path(session_id))

    def _read_session_path(self, path: Path) -> Session:
        session = read_model(path, Session)
        if path != self.config.state_path(session.id):
            raise AgentDesktopError(
                f"session state identity does not match its path: {path}",
                "state_error",
            )
        return self._validate_session_record(session)

    def _remove_resources(self, session_id: str) -> None:
        shutil.rmtree(self.config.runtime_dir(session_id), ignore_errors=True)
        shutil.rmtree(self.config.browser_overlay_dir(session_id), ignore_errors=True)

    def _validate_session_record(self, session: Session) -> Session:
        RuntimeLayout(self.config, session.id).validate_session(
            session, self._unit_name(session.id)
        )
        return session

    @staticmethod
    def _unit_name(session_id: str) -> str:
        return f"agent-desktop-{session_id}.service"

    @staticmethod
    def _new_session_id(agent_id: str) -> str:
        prefix = agent_id.lower().replace("_", "-").replace(".", "-")[:48]
        return f"{prefix}-{uuid.uuid4().hex[:8]}"
