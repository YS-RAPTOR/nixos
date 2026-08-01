{
  den.aspects.development.toolchains.javascript.homeManager = { pkgs, ... }: {
    home.packages = [
      pkgs.bun
      pkgs.nodejs
      pkgs.deno
    ];
  };
}
