{ inputs, ... }:
let
  nixIndent = 2;
  nixWidth = 120;
in
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  flake-file.inputs.treefmt-nix = {
    url = "github:numtide/treefmt-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake-file.formatter =
    pkgs:
    pkgs.writeShellApplication {
      name = "nixfmt-flake-file";
      text = ''
        exec ${pkgs.lib.getExe pkgs.nixfmt} \
            --indent ${toString nixIndent} \
            --width ${toString nixWidth} \
            --strict \
            "$@"
      '';
    };

  perSystem.treefmt = {
    projectRoot = builtins.path {
      path = ../.;
      name = "treefmt-source";
      filter = path: _: baseNameOf path != ".git";
    };
    projectRootFile = "flake.nix";
    settings.excludes = [
      "references/**"
      "**/_references/**"
    ];
    programs.nixfmt = {
      enable = true;
      indent = nixIndent;
      strict = true;
      width = nixWidth;
    };

    programs.prettier = {
      enable = true;
      includes = [ "*.json" ];
      settings = {
        tabWidth = 4;
        useTabs = false;
      };
    };

    programs.shfmt = {
      enable = true;
      indent_size = 4;
    };

    programs.stylua = {
      enable = true;
      settings = {
        column_width = 120;
        indent_type = "Spaces";
        indent_width = 4;
      };
    };
  };
}
