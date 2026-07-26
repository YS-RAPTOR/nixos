{
  den.aspects.tooling.toolchains.homeManager = { pkgs, ... }: {
    home.packages = [
      pkgs.bun
      pkgs.cargo
      pkgs.dotnet-sdk
      pkgs.gcc
      pkgs.go
      pkgs.maven
      pkgs.nodejs
      pkgs.openjdk
      pkgs.pkg-config
      pkgs.python315
      pkgs.rust-analyzer
      pkgs.rustc
      pkgs.uv
      pkgs.zig
    ];
  };
}
