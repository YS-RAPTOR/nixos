{
    description = "Pi coding agent - Latest GitHub release binary";

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
                "x86_64-linux" = "pi-linux-x64.tar.gz";
                "aarch64-linux" = "pi-linux-arm64.tar.gz";
                "x86_64-darwin" = "pi-darwin-x64.tar.gz";
                "aarch64-darwin" = "pi-darwin-arm64.tar.gz";
            };

            mkPi =
                system:
                let
                    pkgs = nixpkgs.legacyPackages.${system};
                    assetName = systemToAsset.${system};
                    src = builtins.fetchurl {
                        url = "https://github.com/earendil-works/pi/releases/latest/download/${assetName}";
                    };
                in
                pkgs.stdenv.mkDerivation {
                    pname = "pi";
                    version = "latest";
                    inherit src;
                    dontStrip = true;

                    sourceRoot = "pi";

                    nativeBuildInputs = [
                        pkgs.makeWrapper
                    ]
                    ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ];

                    buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.stdenv.cc.cc.lib ];

                    installPhase = ''
                        runHook preInstall

                        mkdir -p $out/libexec/pi $out/bin
                        cp -r . $out/libexec/pi
                        chmod +x $out/libexec/pi/pi

                        makeWrapper $out/libexec/pi/pi $out/bin/pi \
                            --argv0 pi \
                            --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.ripgrep ]}

                        install -Dm644 README.md $out/share/doc/pi/README.md
                        install -Dm644 CHANGELOG.md $out/share/doc/pi/CHANGELOG.md

                        runHook postInstall
                    '';

                    meta = with pkgs.lib; {
                        description = "Coding agent CLI with read, bash, edit, write tools and session management";
                        homepage = "https://github.com/earendil-works/pi";
                        license = licenses.mit;
                        platforms = supportedSystems;
                        mainProgram = "pi";
                        sourceProvenance = with sourceTypes; [ binaryNativeCode ];
                    };
                };
        in
        {
            packages = forAllSystems (system: {
                pi = mkPi system;
                default = mkPi system;
            });
        };
}
