class AgentDesktopError(Exception):
    def __init__(self, message: str, code: str = "agent_desktop_error") -> None:
        super().__init__(message)
        self.code = code
