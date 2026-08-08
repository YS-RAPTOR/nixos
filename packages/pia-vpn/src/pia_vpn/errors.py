class PiaVpnError(Exception):
    def __init__(self, message: str, code: str = "pia_vpn_error") -> None:
        super().__init__(message)
        self.code = code
