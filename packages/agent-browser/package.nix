{
  fetchzip,
  lib,
  rustPlatform,
  versionCheckHook,
  which,
  writableTmpDirAsHomeHook,
}:
let
  source = builtins.fromJSON (builtins.readFile ./sources.json);
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "agent-browser";
  inherit (source) version;

  src = fetchzip { inherit (source) url hash; };
  sourceRoot = "${finalAttrs.src.name}/cli";
  cargoHash = source.cargoHash;

  patches = [ ./vivaldi-target-readiness.patch ];

  # The dashboard is unrelated to CLI-driven browser control, but RustEmbed
  # requires its source directory to exist at compile time.
  postUnpack = ''
    chmod u+w source/packages/dashboard
    mkdir -p source/packages/dashboard/out
    printf '%s\n' '<!doctype html><title>agent-browser</title>' \
      > source/packages/dashboard/out/index.html
  '';

  # Optional-tool probes must resolve inside the Nix store at runtime.
  postPatch = ''
    substituteInPlace src/doctor/helpers.rs src/install.rs --replace-fail \
      '"which"' '"${lib.getExe which}"'
  '';

  nativeCheckInputs = [ writableTmpDirAsHomeHook ];

  postInstall = ''
    cp -r ../skills ../skill-data "$out/"
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];
  versionCheckProgramArg = "--version";

  meta = {
    description = "Browser automation CLI for AI agents";
    homepage = "https://agent-browser.dev";
    license = lib.licenses.asl20;
    mainProgram = "agent-browser";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
