{
    description = "T3 Code - Web GUI for coding agents";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    };

    outputs =
        { self, nixpkgs }:
        let
            supportedSystems = [
                "x86_64-linux"
            ];

            forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

            mkT3code =
                system:
                let
                    pkgs = nixpkgs.legacyPackages.${system};

                    latestRelease = builtins.fromJSON (
                        builtins.readFile (
                            builtins.fetchurl {
                                url = "https://api.github.com/repos/pingdotgg/t3code/releases/latest";
                            }
                        )
                    );

                    version = builtins.replaceStrings [ "v" ] [ "" ] latestRelease.tag_name;

                    src = builtins.fetchurl {
                        url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
                    };
                in
                pkgs.appimageTools.wrapType2 {
                    pname = "t3code";
                    inherit version src;

                    extraInstallCommands =
                        let
                            appimageContents = pkgs.appimageTools.extractType2 {
                                pname = "t3code";
                                inherit version src;
                            };
                        in
                        ''
                            install -m 444 -D ${appimageContents}/t3-code-desktop.desktop $out/share/applications/t3-code.desktop
                            substituteInPlace $out/share/applications/t3-code.desktop \
                                --replace-warn 'Exec=AppRun --no-sandbox' 'Exec=t3code'
                            cp -r ${appimageContents}/usr/share/icons $out/share/icons
                        '';

                    meta = with pkgs.lib; {
                        description = "Web GUI for coding agents";
                        homepage = "https://github.com/pingdotgg/t3code";
                        license = licenses.mit;
                        platforms = [ "x86_64-linux" ];
                        mainProgram = "t3code";
                    };
                };
        in
        {
            packages = forAllSystems (system: {
                t3code = mkT3code system;
                default = mkT3code system;
            });
        };
}
