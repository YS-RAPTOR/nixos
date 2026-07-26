{
  inputs,
  makeWrapper,
  stdenv,
  symlinkJoin,
}:
let
  gh = inputs.nixpkgs.legacyPackages.${stdenv.hostPlatform.system}.gh;
in
symlinkJoin {
  name = "gh-${gh.version}";
  paths = [ gh ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/gh" \
        --unset GITHUB_TOKEN
  '';
  meta = gh.meta;
}
