{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
}:
let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  source =
    sources.platforms.${stdenv.hostPlatform.system} or (throw "wombat: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "wombat";
  inherit (source) version;

  src = fetchurl { inherit (source) url hash; };

  sourceRoot = ".";

  unpackPhase = ''
    tar -xzf "$src"
  '';

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 wombat "$out/bin/wombat"
    runHook postInstall
  '';

  meta = {
    description = "Stream processing tool from WombatWisdom";
    homepage = "https://github.com/wombatwisdom/wombat";
    license = lib.licenses.asl20;
    mainProgram = "wombat";
    platforms = builtins.attrNames sources.platforms;
  };
}
