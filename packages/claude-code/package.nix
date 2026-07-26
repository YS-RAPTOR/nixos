{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
}:
let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  source =
    sources.platforms.${stdenv.hostPlatform.system}
      or (throw "claude-code: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "claude-code";
  inherit (source) version;

  src = fetchurl { inherit (source) url hash; };

  dontStrip = true;
  sourceRoot = ".";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  unpackPhase = ''tar -xzf "$src"'';

  installPhase = ''
    runHook preInstall
    install -Dm755 claude "$out/bin/claude"
    runHook postInstall
  '';

  meta = {
    description = "Agentic coding tool that understands and modifies codebases";
    homepage = "https://github.com/anthropics/claude-code";
    license = lib.licenses.unfree;
    mainProgram = "claude";
    platforms = builtins.attrNames sources.platforms;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
