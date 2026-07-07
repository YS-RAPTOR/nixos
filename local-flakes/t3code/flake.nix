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

                    releases = builtins.fromJSON (
                        builtins.readFile (
                            builtins.fetchurl {
                                url = "https://api.github.com/repos/pingdotgg/t3code/releases?per_page=20";
                            }
                        )
                    );

                    nightlyReleases = builtins.filter (release: pkgs.lib.hasInfix "-nightly." release.tag_name) releases;

                    release =
                        if nightlyReleases == [ ] then
                            throw "No nightly release found in t3code GitHub releases"
                        else
                            builtins.head nightlyReleases;

                    tag = release.tag_name;
                    version = pkgs.lib.removePrefix "v" tag;

                    appimageAssets = builtins.filter (
                        asset: asset.name == "T3-Code-${version}-x86_64.AppImage"
                    ) release.assets;

                    appimageAsset =
                        if appimageAssets == [ ] then
                            throw "No x86_64 AppImage found for t3code release ${tag}"
                        else
                            builtins.head appimageAssets;

                    src = pkgs.fetchurl {
                        url = appimageAsset.browser_download_url;
                        hash = builtins.convertHash {
                            hashAlgo = "sha256";
                            hash = pkgs.lib.removePrefix "sha256:" appimageAsset.digest;
                            toHashFormat = "sri";
                        };
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
                            desktopFile=""

                            for candidate in \
                                ${appimageContents}/*.desktop \
                                ${appimageContents}/usr/share/applications/*.desktop
                            do
                                if [ -f "$candidate" ]; then
                                    desktopFile="$candidate"
                                    break
                                fi
                            done

                            if [ -z "$desktopFile" ]; then
                                echo "No desktop file found in extracted AppImage" >&2
                                exit 1
                            fi

                            install -m 444 -D "$desktopFile" $out/share/applications/t3code.desktop
                            substituteInPlace $out/share/applications/t3code.desktop \
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
