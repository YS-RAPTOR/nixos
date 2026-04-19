{
    description = "Claude Code - Latest npm release";

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

            systemToPackage = {
                "x86_64-linux" = "@anthropic-ai/claude-code-linux-x64";
                "aarch64-linux" = "@anthropic-ai/claude-code-linux-arm64";
                "x86_64-darwin" = "@anthropic-ai/claude-code-darwin-x64";
                "aarch64-darwin" = "@anthropic-ai/claude-code-darwin-arm64";
            };

            mkClaudeCode =
                system:
                let
                    pkgs = import nixpkgs {
                        inherit system;
                        config = {
                            allowUnfree = true;
                            allowUnfreePredicate = (_: true);
                        };
                    };
                    wrapperPackageJson = builtins.fromJSON (
                        builtins.readFile (
                            builtins.fetchurl {
                                url = "https://registry.npmjs.org/@anthropic-ai/claude-code/latest";
                            }
                        )
                    );

                    nativePackageName = systemToPackage.${system};
                    nativePackageJson = builtins.fromJSON (
                        builtins.readFile (
                            builtins.fetchurl {
                                url = "https://registry.npmjs.org/${nativePackageName}/${wrapperPackageJson.version}";
                            }
                        )
                    );

                    src = builtins.fetchurl {
                        url = nativePackageJson.dist.tarball;
                    };
                in
                pkgs.stdenvNoCC.mkDerivation {
                    pname = "claude-code";
                    version = wrapperPackageJson.version;
                    inherit src;
                    dontStrip = true;

                    nativeBuildInputs =
                        [ pkgs.makeWrapper ]
                        ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];

                    unpackPhase = ''
                        tar -xzf "$src"
                    '';

                    sourceRoot = "package";

                    installPhase = ''
                        runHook preInstall

                        install -Dm755 claude $out/libexec/claude

                        makeWrapper $out/libexec/claude $out/bin/claude \
                            --argv0 claude

                        install -Dm644 README.md $out/share/doc/claude-code/README.md
                        install -Dm644 LICENSE.md $out/share/doc/claude-code/LICENSE.md

                        runHook postInstall
                    '';

                    meta = with pkgs.lib; {
                        description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
                        homepage = "https://github.com/anthropics/claude-code";
                        downloadPage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
                        license = licenses.unfree;
                        platforms = supportedSystems;
                        mainProgram = "claude";
                        sourceProvenance = with sourceTypes; [ binaryNativeCode ];
                    };
                };
        in
        {
            packages = forAllSystems (system: {
                claude-code = mkClaudeCode system;
                default = mkClaudeCode system;
            });
        };
}
