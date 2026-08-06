{
  buildNpmPackage,
  fetchurl,
  jq,
  lib,
  makeWrapper,
  nodejs_24,
  ripgrep,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}:
let
  source = builtins.fromJSON (builtins.readFile ./sources.json);
  dependencyIntegrities = source.dependencyIntegrities;
in
buildNpmPackage {
  pname = "pi";
  inherit (source) version;

  src = fetchurl { inherit (source) url hash; };
  npmDepsHash = source.npmDepsHash;
  nodejs = nodejs_24;

  postPatch = ''
    ${lib.getExe jq} 'del(.devDependencies)' package.json > package.json.patched
    mv package.json.patched package.json

    ${lib.getExe jq} \
      --argjson integrities ${lib.escapeShellArg (builtins.toJSON dependencyIntegrities)} \
      '
        reduce ($integrities | to_entries[]) as $dependency (
          .;
          .packages["node_modules/\($dependency.key)"].integrity = $dependency.value
        )
      ' \
      npm-shrinkwrap.json > npm-shrinkwrap.json.patched
    mv npm-shrinkwrap.json.patched npm-shrinkwrap.json

    substituteInPlace dist/modes/interactive/interactive-mode.js \
      --replace-fail \
        '{ openUrl: openBrowser }' \
        '{ openUrl: openBrowser, wheelScrollLines: 3 }'
  '';

  dontNpmBuild = true;
  dontNpmPrune = true;
  npmInstallFlags = [
    "--ignore-scripts"
    "--omit=dev"
  ];
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    ${nodejs_24}/bin/node ${./patch-scrollbar.mjs} \
      "$out/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui/dist/layout.js"
  '';

  postFixup = ''
    wrapProgram "$out/bin/pi" \
      --prefix PATH : ${lib.makeBinPath [ ripgrep ]} \
      --add-flags "--exclude-tools bash"
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];
  versionCheckProgram = "${placeholder "out"}/bin/pi";
  versionCheckProgramArg = "--version";

  meta = {
    description = "Coding agent CLI with read, bash, edit, write tools and session management";
    homepage = "https://github.com/earendil-works/pi";
    changelog = "https://github.com/earendil-works/pi/blob/v${source.version}/packages/coding-agent/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "pi";
  };
}
