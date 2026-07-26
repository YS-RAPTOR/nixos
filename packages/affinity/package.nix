{
  inputs,
  makeWrapper,
  pkgs,
  symlinkJoin,
}:
let
  affinityInputs = inputs.affinity-nix.inputs;
  stdPath = p: [
    p.zenity
    p.curl
    p.zstd
    p.coreutils
    p.gnused
    p.gnugrep
    p.wget
    p.busybox
  ];
  winePackages = pkgs.callPackage "${inputs.affinity-nix}/packages/wine/packages.nix" {
    inputs = affinityInputs;
    inherit stdPath;
  };
  aplCombined = pkgs.callPackage "${inputs.affinity-nix}/packages/apl/apl-combined.nix" {
    src = affinityInputs.plugin-loader-src;
  };
  prefixBase = pkgs.callPackage "${inputs.affinity-nix}/packages/prefixWithAffinity.nix" {
    inputs = affinityInputs;
    wine-packages = winePackages;
    apl-combined = aplCombined;
  };
  upstreamRunner = pkgs.callPackage "${inputs.affinity-nix}/packages/runner/package.nix" {
    inputs = affinityInputs;
    inherit prefixBase;
    wine-packages = winePackages;
    registry-patches = (pkgs.callPackage "${inputs.affinity-nix}/packages/registry-patches.nix" { }).combined;
    toolchain = affinityInputs.fenix.packages.${pkgs.stdenv.hostPlatform.system}.complete;
    name = "v3";
  };
  patchedRunner = upstreamRunner.package.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace crates/runner/src/main.rs \
          --replace-fail 'cmd!(WINE, "wineboot", "--update")' \
          'cmd!(WINE, "wineboot", "--update").env_remove("DISPLAY").env_remove("WAYLAND_DISPLAY")'
    '';
  });
  desktop = pkgs.callPackage "${inputs.affinity-nix}/packages/affinity-v3/desktopItems.nix" {
    affinity-v3 = patchedRunner;
  };
  icons = pkgs.callPackage "${inputs.affinity-nix}/packages/affinity-v3/icons.nix" { };
in
symlinkJoin {
  name = "affinity-v3-nvidia";
  paths = [
    patchedRunner
    desktop.affinity-v3
    icons.iconPackage
  ];
  nativeBuildInputs = [ makeWrapper ];

  postBuild = ''
    wrapProgram "$out/bin/affinity-v3" \
        --set __NV_PRIME_RENDER_OFFLOAD 1 \
        --set __NV_PRIME_RENDER_OFFLOAD_PROVIDER NVIDIA-G0 \
        --set __GLX_VENDOR_LIBRARY_NAME nvidia \
        --set __VK_LAYER_NV_optimus NVIDIA_only

    rm "$out/share/applications/affinity-v3.desktop"
    cp ${desktop.affinity-v3}/share/applications/affinity-v3.desktop \
        "$out/share/applications/affinity-v3.desktop"
    desktopExec="$(grep '^Exec=' "$out/share/applications/affinity-v3.desktop")"
    substituteInPlace "$out/share/applications/affinity-v3.desktop" \
        --replace-fail "$desktopExec" "Exec=$out/bin/affinity-v3 %U"
  '';

  meta = {
    description = "Affinity v3 with NVIDIA PRIME render offload";
    homepage = "https://affinity.serif.com/";
    license = pkgs.lib.licenses.unfree;
    mainProgram = "affinity-v3";
    platforms = [ "x86_64-linux" ];
  };
}
