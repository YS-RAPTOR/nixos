{
    description = "Raptor local package flakes";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

        affinity-nix.url = "path:./affinity-nix";
        affinity-nix.inputs.nixpkgs.follows = "nixpkgs";

        wombat.url = "path:./wombat";
        wombat.inputs.nixpkgs.follows = "nixpkgs";

        opencode.url = "path:./opencode";
        opencode.inputs.nixpkgs.follows = "nixpkgs";

        t3code.url = "path:./t3code";
        t3code.inputs.nixpkgs.follows = "nixpkgs";

        pi.url = "path:./pi";
        pi.inputs.nixpkgs.follows = "nixpkgs";

        claude-code.url = "path:./claude-code";
        claude-code.inputs.nixpkgs.follows = "nixpkgs";

        codex.url = "path:./codex";
        codex.inputs.nixpkgs.follows = "nixpkgs";
    };

    outputs =
        inputs@{
            self,
            nixpkgs,
            affinity-nix,
            wombat,
            opencode,
            t3code,
            pi,
            claude-code,
            codex,
            ...
        }:
        let
            supportedSystems = [
                "x86_64-linux"
                "aarch64-linux"
                "x86_64-darwin"
                "aarch64-darwin"
            ];

            forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

            optionalPackage =
                input: system: sourceName: targetName:
                if
                    input ? packages
                    && builtins.hasAttr system input.packages
                    && builtins.hasAttr sourceName input.packages.${system}
                then
                    {
                        ${targetName} = input.packages.${system}.${sourceName};
                    }
                else
                    { };

            packagesFor =
                system:
                let
                    packages =
                        (optionalPackage affinity-nix system "v3" "affinity")
                        // (optionalPackage wombat system "wombat" "wombat")
                        // (optionalPackage opencode system "opencode" "opencode")
                        // (optionalPackage opencode system "opencode-desktop" "opencode-desktop")
                        // (optionalPackage t3code system "t3code" "t3code")
                        // (optionalPackage pi system "pi" "pi")
                        // (optionalPackage claude-code system "claude-code" "claude-code")
                        // (optionalPackage codex system "codex" "codex");
                in
                packages
                // {
                    default = packages.opencode;
                };
        in
        {
            packages = forAllSystems packagesFor;
        };
}
