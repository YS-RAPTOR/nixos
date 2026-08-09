{ inputs, stdenv }:
inputs.cua.packages.${stdenv.hostPlatform.system}.cua-driver.overrideAttrs (previous: {
  patches = (previous.patches or [ ]) ++ [ ./wayland-screen-size.patch ];
})
