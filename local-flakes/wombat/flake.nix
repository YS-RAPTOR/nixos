{
    description = "Wombat - A stream processing tool";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    };

    outputs =
        { self, nixpkgs }:
        let
            supportedSystems = [
                "x86_64-linux"
                "aarch64-linux"
                "x86_64-darwin"
                "aarch64-darwin"
            ];

            forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

            # Maps nix system to GitHub release asset naming
            systemToAsset = {
                "x86_64-linux" = "Linux_x86_64";
                "aarch64-linux" = "Linux_arm64";
                "x86_64-darwin" = "Darwin_x86_64";
                "aarch64-darwin" = "Darwin_arm64";
            };

            mkWombat =
                system:
                let
                    pkgs = nixpkgs.legacyPackages.${system};
                    assetSuffix = systemToAsset.${system};
                in
                pkgs.stdenv.mkDerivation {
                    pname = "wombat";
                    version = "latest";

                    src = builtins.fetchurl {
                        url = "https://github.com/wombatwisdom/wombat/releases/latest/download/wombat_${assetSuffix}.tar.gz";
                    };

                    sourceRoot = ".";

                    unpackPhase = ''
                        tar -xzf $src
                    '';

                    nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];

                    installPhase = ''
                        runHook preInstall
                        install -Dm755 wombat $out/bin/wombat
                        runHook postInstall
                    '';

                    meta = with pkgs.lib; {
                        description = "Wombat - A stream processing tool from WombatWisdom";
                        homepage = "https://github.com/wombatwisdom/wombat";
                        license = licenses.asl20;
                        platforms = supportedSystems;
                        mainProgram = "wombat";
                    };
                };
        in
        {
            packages = forAllSystems (system: {
                wombat = mkWombat system;
                default = mkWombat system;
            });
        };
}
