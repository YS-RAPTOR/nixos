{
    pkgs,
    writeShellScriptBin,
    lib,
    wine,
    affinityPathV3,
    stdShellArgs,
    mkInstaller,
    mkGraphicalCheck,
}:
rec {
    createRunner =
        let
            installer = mkInstaller "v3";
            check = mkGraphicalCheck "v3";
        in
        writeShellScriptBin "affinity-v3" ''
            set -x
            ${stdShellArgs}

            # Force NVIDIA GPU for Prime offload systems
            export __NV_PRIME_RENDER_OFFLOAD=1
            export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            export __VK_LAYER_NV_optimus=NVIDIA_only

            if [ ! -f "${affinityPathV3}/drive_c/Program Files/Affinity/Affinity/Affinity.exe" ]; then
                ${lib.getExe installer} || exit 1
            else
                ${lib.getExe check} || exit 1
            fi

            if [ "$1" != "--verbose" ]; then
                export WINEDEBUG=-all,fixme-all
            else
              shift
            fi

            ${lib.getExe wine} "${affinityPathV3}/drive_c/Program Files/Affinity/Affinity/AffinityHook.exe" "$@"
        '';

    createPackage =
        let
            pkg = createRunner;
            desktop = pkgs.callPackage ./desktopItems.nix {
                affinity-v3 = pkg;
            };

            icons = pkgs.callPackage ./icons.nix { };
            icon-package = icons.iconPackage;
        in
        pkgs.symlinkJoin {
            name = "Affinity v3";
            pname = "affinity-v3";
            paths = [
                pkg
                desktop.affinity-v3
                icon-package
            ];
            meta = {
                description = "Affinity v3";
                homepage = "https://www.affinity.studio";
                # license = lib.licenses.unfree;
                # maintainers = with pkgs.lib.maintainers; [marshmallow];
                platforms = [ "x86_64-linux" ];
                mainProgram = "affinity-v3";
            };
        };
}
