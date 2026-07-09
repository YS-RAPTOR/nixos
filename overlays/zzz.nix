[
    (final: prev: {
        vivaldi = prev.vivaldi.override {
            proprietaryCodecs = true;
        };

        gh = final.symlinkJoin {
            name = "gh-${prev.gh.version}";
            paths = [ prev.gh ];
            buildInputs = [ final.makeWrapper ];
            postBuild = ''
                wrapProgram $out/bin/gh \
                  --set GITHUB_TOKEN ""
            '';
        };

        mailspring = final.symlinkJoin {
            name = "mailspring-${prev.mailspring.version}";
            paths = [ prev.mailspring ];
            buildInputs = [ final.makeWrapper ];
            postBuild = ''
                wrapProgram $out/bin/mailspring \
                  --prefix LD_LIBRARY_PATH : "${final.lib.makeLibraryPath [ final.libglvnd ]}" \
                  --add-flags "--password-store=gnome-libsecret"

                # Fix .desktop files to use the wrapped binary
                if [ -d $out/share/applications ]; then
                  for f in $out/share/applications/*.desktop; do
                    rm "$f"
                    cp "${prev.mailspring}/share/applications/$(basename $f)" "$f"
                    substituteInPlace "$f" \
                      --replace-quiet "${prev.mailspring}/bin/" "$out/bin/"
                  done
                fi
            '';
        };
    })
]
