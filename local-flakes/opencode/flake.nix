{
    description = "OpenCode - Latest stable release binary";

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

            desktopSystems = [
                "x86_64-linux"
                "aarch64-linux"
            ];

            forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

            systemToAsset = {
                "x86_64-linux" = {
                    fileName = "opencode-linux-x64.tar.gz";
                    binaryName = "opencode";
                };
                "aarch64-linux" = {
                    fileName = "opencode-linux-arm64.tar.gz";
                    binaryName = "opencode";
                };
                "x86_64-darwin" = {
                    fileName = "opencode-darwin-x64.zip";
                    binaryName = "opencode";
                };
                "aarch64-darwin" = {
                    fileName = "opencode-darwin-arm64.zip";
                    binaryName = "opencode";
                };
            };

            systemToDesktopAsset = {
                "x86_64-linux" = "opencode-desktop-linux-x86_64.AppImage";
                "aarch64-linux" = "opencode-desktop-linux-arm64.AppImage";
            };

            mkOpencode =
                system:
                let
                    pkgs = nixpkgs.legacyPackages.${system};
                    asset = systemToAsset.${system};
                in
                pkgs.stdenv.mkDerivation {
                    pname = "opencode";
                    version = "latest";
                    dontStrip = true;

                    src = builtins.fetchurl {
                        url = "https://github.com/anomalyco/opencode/releases/latest/download/${asset.fileName}";
                    };

                    sourceRoot = ".";

                    nativeBuildInputs = [
                        pkgs.makeWrapper
                    ]
                    ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.autoPatchelfHook ]
                    ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.unzip ];

                    unpackPhase =
                        if pkgs.lib.hasSuffix ".zip" asset.fileName then
                            ''
                                unzip "$src"
                            ''
                        else
                            ''
                                tar -xzf "$src"
                            '';

                    installPhase = ''
                        runHook preInstall

                        install -Dm755 ${asset.binaryName} $out/libexec/opencode

                        makeWrapper $out/libexec/opencode $out/bin/opencode \
                            --argv0 opencode \
                            --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.ripgrep ]}

                        runHook postInstall
                    '';

                    meta = with pkgs.lib; {
                        description = "The open source coding agent";
                        homepage = "https://github.com/anomalyco/opencode";
                        license = licenses.mit;
                        platforms = supportedSystems;
                        mainProgram = "opencode";
                    };
                };

            mkOpencodeDesktop =
                system:
                let
                    pkgs = nixpkgs.legacyPackages.${system};
                    assetName = systemToDesktopAsset.${system};
                    src = builtins.fetchurl {
                        url = "https://github.com/anomalyco/opencode/releases/latest/download/${assetName}";
                    };
                    appimageContents = pkgs.appimageTools.extractType2 {
                        pname = "opencode-desktop";
                        version = "latest";
                        inherit src;
                    };
                in
                pkgs.appimageTools.wrapType2 {
                    pname = "opencode-desktop";
                    version = "latest";
                    inherit src;

                    extraPkgs = appPkgs: [ appPkgs.libsecret ];

                    extraInstallCommands = ''
                        install -m 444 -D ${appimageContents}/ai.opencode.desktop.desktop \
                            $out/share/applications/opencode-desktop.desktop
                        substituteInPlace $out/share/applications/opencode-desktop.desktop \
                            --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=opencode-desktop --no-sandbox %U'
                        cp -r ${appimageContents}/usr/share/icons $out/share/icons
                    '';

                    meta = with pkgs.lib; {
                        description = "Desktop app for the open source coding agent";
                        homepage = "https://opencode.ai/download";
                        license = licenses.mit;
                        platforms = desktopSystems;
                        mainProgram = "opencode-desktop";
                        sourceProvenance = with sourceTypes; [ binaryNativeCode ];
                    };
                };
        in
        {
            packages = forAllSystems (
                system:
                {
                    opencode = mkOpencode system;
                    default = mkOpencode system;
                }
                // nixpkgs.lib.optionalAttrs (builtins.elem system desktopSystems) {
                    opencode-desktop = mkOpencodeDesktop system;
                }
            );
        };
}
