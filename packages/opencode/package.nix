{
  autoPatchelfHook,
  fetchurl,
  lib,
  makeWrapper,
  ripgrep,
  stdenv,
  unzip,
}:
let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  source =
    sources.platforms.${stdenv.hostPlatform.system} or (throw "opencode: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "opencode";
  inherit (source) version;

  src = fetchurl { inherit (source) url hash; };

  dontStrip = true;
  sourceRoot = ".";

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ unzip ];

  unpackPhase = if stdenv.hostPlatform.isDarwin then ''unzip "$src"'' else ''tar -xzf "$src"'';

  installPhase = ''
    runHook preInstall

    install -Dm755 opencode "$out/libexec/opencode"
    makeWrapper "$out/libexec/opencode" "$out/bin/opencode" \
        --argv0 opencode \
        --prefix PATH : ${lib.makeBinPath [ ripgrep ]}

    runHook postInstall
  '';

  meta = {
    description = "Open source coding agent";
    homepage = "https://github.com/anomalyco/opencode";
    license = lib.licenses.mit;
    mainProgram = "opencode";
    platforms = builtins.attrNames sources.platforms;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
