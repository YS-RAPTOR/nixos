{ den.aspects.development.toolchains.dotnet.homeManager = { pkgs, ... }: { home.packages = [ pkgs.dotnet-sdk ]; }; }
