{
    description = "Codex CLI - Latest stable release binary";

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

            systemToAsset = {
                "x86_64-linux" = "codex-x86_64-unknown-linux-musl";
                "aarch64-linux" = "codex-aarch64-unknown-linux-musl";
                "x86_64-darwin" = "codex-x86_64-apple-darwin";
                "aarch64-darwin" = "codex-aarch64-apple-darwin";
            };

            mkCodex =
                system:
                let
                    pkgs = nixpkgs.legacyPackages.${system};
                    assetName = systemToAsset.${system};
                in
                pkgs.stdenvNoCC.mkDerivation {
                    pname = "codex";
                    version = "latest";
                    dontStrip = true;

                    src = builtins.fetchurl {
                        url = "https://github.com/openai/codex/releases/latest/download/${assetName}.tar.gz";
                    };

                    sourceRoot = ".";

                    unpackPhase = ''
                        tar -xzf "$src"
                    '';

                    installPhase = ''
                        runHook preInstall

                        install -Dm755 ${assetName} $out/bin/codex

                        runHook postInstall
                    '';

                    meta = with pkgs.lib; {
                        description = "Lightweight coding agent that runs in your terminal";
                        homepage = "https://github.com/openai/codex";
                        license = licenses.asl20;
                        platforms = supportedSystems;
                        mainProgram = "codex";
                        sourceProvenance = with sourceTypes; [ binaryNativeCode ];
                    };
                };
        in
        {
            packages = forAllSystems (system: {
                codex = mkCodex system;
                default = mkCodex system;
            });
        };
}
