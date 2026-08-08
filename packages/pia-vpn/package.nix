{
  fetchFromGitHub,
  iproute2,
  lib,
  nftables,
  openresolv,
  python3Packages,
  runCommand,
  systemd,
  wireguard-tools,
}:
let
  piaManualConnections = fetchFromGitHub {
    owner = "pia-foss";
    repo = "manual-connections";
    rev = "a1412dbe2ca41edbb79c766bc475335cb6cb13ad";
    hash = "sha256-SaCxirr/LF2a8PdTTZY98aEYVCYC0RxfT1XpWs4x7f0=";
  };

  # wg-quick insists on UID 0 even when systemd grants the exact capabilities
  # it needs. Keep the controller unprivileged and remove only that UID gate.
  wireguardRuntime = runCommand "pia-wireguard-runtime" { } ''
    mkdir -p $out/bin
    ln -s ${wireguard-tools}/bin/wg $out/bin/wg
    cp ${wireguard-tools}/bin/.wg-quick-wrapped $out/bin/wg-quick
    sed -i '/^[[:space:]]*\[\[ \$UID == 0 \]\] || exec sudo /c\    :' $out/bin/wg-quick
    chmod +x $out/bin/wg-quick
  '';
in
python3Packages.buildPythonApplication {
  pname = "pia-vpn";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = [ python3Packages.uv-build ];
  dependencies = with python3Packages; [
    aiohttp
    certifi
    click
    pydantic
  ];

  postPatch = ''
    cp ${piaManualConnections}/ca.rsa.4096.crt src/pia_vpn/ca.rsa.4096.crt
  '';

  postInstall = ''
    mkdir -p $out/share/fish/vendor_completions.d
    _PIA_VPN_COMPLETE=fish_source $out/bin/pia-vpn \
      >$out/share/fish/vendor_completions.d/pia-vpn.fish
  '';

  makeWrapperArgs = [
    "--prefix PATH : ${
      lib.makeBinPath [
        iproute2
        nftables
        openresolv
        systemd
        wireguardRuntime
      ]
    }"
  ];

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];
  pythonImportsCheck = [ "pia_vpn" ];

  meta = {
    description = "Private Internet Access WireGuard controller and CLI";
    homepage = "https://github.com/YS-RAPTOR/NixOS";
    license = lib.licenses.mit;
    mainProgram = "pia-vpn";
    platforms = lib.platforms.linux;
  };
}
