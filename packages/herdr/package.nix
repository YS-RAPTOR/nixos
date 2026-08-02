{
  fetchurl,
  lib,
  stdenv,
}:
let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  source =
    sources.platforms.${stdenv.hostPlatform.system} or (throw "herdr: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "herdr";
  inherit (source) version;

  src = fetchurl { inherit (source) url hash; };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/herdr"
    runHook postInstall
  '';

  meta = {
    description = "Runtime for coding agents";
    homepage = "https://herdr.dev";
    changelog = "https://github.com/herdrdev/herdr/releases/tag/v${source.version}";
    license = lib.licenses.asl20;
    mainProgram = "herdr";
    platforms = builtins.attrNames sources.platforms;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
