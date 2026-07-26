{
  appimageTools,
  fetchurl,
  lib,
  libsecret,
  stdenv,
}:
let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  source =
    sources.platforms.${stdenv.hostPlatform.system}
      or (throw "opencode-desktop: unsupported system ${stdenv.hostPlatform.system}");
  src = fetchurl { inherit (source) url hash; };
  appimageContents = appimageTools.extractType2 {
    pname = "opencode-desktop";
    inherit (source) version;
    inherit src;
  };
in
appimageTools.wrapType2 {
  pname = "opencode-desktop";
  inherit (source) version;
  inherit src;

  extraPkgs = _: [ libsecret ];

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/ai.opencode.desktop.desktop \
        "$out/share/applications/opencode-desktop.desktop"
    substituteInPlace "$out/share/applications/opencode-desktop.desktop" \
        --replace-fail "Exec=AppRun --no-sandbox %U" \
        "Exec=opencode-desktop --no-sandbox %U"
    cp -r ${appimageContents}/usr/share/icons "$out/share/icons"
  '';

  meta = {
    description = "Desktop app for the OpenCode coding agent";
    homepage = "https://opencode.ai/download";
    license = lib.licenses.mit;
    mainProgram = "opencode-desktop";
    platforms = builtins.attrNames sources.platforms;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
