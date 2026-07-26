{
  appimageTools,
  fetchurl,
  lib,
  stdenv,
}:
let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  source =
    sources.platforms.${stdenv.hostPlatform.system} or (throw "t3-code: unsupported system ${stdenv.hostPlatform.system}");
  src = fetchurl { inherit (source) url hash; };
  appimageContents = appimageTools.extractType2 {
    pname = "t3-code";
    inherit (source) version;
    inherit src;
  };
in
appimageTools.wrapType2 {
  pname = "t3-code";
  inherit (source) version;
  inherit src;

  extraInstallCommands = ''
    desktopFile=""

    for candidate in \
        ${appimageContents}/*.desktop \
        ${appimageContents}/usr/share/applications/*.desktop
    do
        if [[ -f $candidate ]]; then
            desktopFile="$candidate"
            break
        fi
    done

    if [[ -z $desktopFile ]]; then
        echo "No desktop file found in extracted AppImage" >&2
        exit 1
    fi

    install -Dm444 "$desktopFile" "$out/share/applications/t3-code.desktop"
    substituteInPlace "$out/share/applications/t3-code.desktop" \
        --replace-warn "Exec=AppRun --no-sandbox" "Exec=t3-code"
    cp -r ${appimageContents}/usr/share/icons "$out/share/icons"
  '';

  meta = {
    description = "Web GUI for coding agents";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    mainProgram = "t3-code";
    platforms = builtins.attrNames sources.platforms;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
