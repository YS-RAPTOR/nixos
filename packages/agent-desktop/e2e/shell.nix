{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    gcc
    pkg-config
  ];

  buildInputs = with pkgs; [
    gst_all_1.gstreamer
    libportal
  ];

  packages = with pkgs; [
    coreutils
    curl
    findutils
    gnugrep
    gnused
    iproute2
    jq
    libsecret
    pipewire
    procps
    python3
    python3Packages.aiohttp
    util-linux
    zenity
  ];

  shellHook = ''
    export AGENT_DESKTOP_E2E_SHELL=1
    export AGENT_DESKTOP_E2E_ZENITY=${pkgs.zenity}/bin/zenity
    export AGENT_DESKTOP_E2E_SECRET_TOOL=${pkgs.libsecret}/bin/secret-tool
    export AGENT_DESKTOP_E2E_PIPEWIRE_PLUGIN=${pkgs.pipewire}/lib/gstreamer-1.0
  '';
}
