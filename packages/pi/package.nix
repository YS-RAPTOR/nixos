{
  autoPatchelfHook,
  fetchurl,
  lib,
  makeWrapper,
  ripgrep,
  stdenv,
}:
let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  source =
    sources.platforms.${stdenv.hostPlatform.system} or (throw "pi: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "pi";
  inherit (source) version;

  src = fetchurl { inherit (source) url hash; };

  dontStrip = true;
  sourceRoot = "pi";

  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/libexec/pi" "$out/bin"
    cp -r . "$out/libexec/pi"
    chmod +x "$out/libexec/pi/pi"

    makeWrapper "$out/libexec/pi/pi" "$out/bin/pi" \
        --argv0 pi \
        --prefix PATH : ${lib.makeBinPath [ ripgrep ]}

    install -Dm644 README.md "$out/share/doc/pi/README.md"
    install -Dm644 CHANGELOG.md "$out/share/doc/pi/CHANGELOG.md"

    runHook postInstall
  '';

  meta = {
    description = "Coding agent CLI with file, shell, and session tools";
    homepage = "https://github.com/earendil-works/pi";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = builtins.attrNames sources.platforms;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
