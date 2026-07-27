{ lib, ... }:
let
  commandType = lib.types.addCheck (lib.types.listOf lib.types.str) (command: command != [ ]);
in
{
  den.schema.user.options.startup = lib.mkOption {
    default = [ ];
    description = "Applications started with the graphical session.";
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          argv = lib.mkOption {
            type = commandType;
            description = "Executable and arguments used to start the application.";
          };

          workspaceByMonitorCount = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            description = "Target workspace selected by connected monitor count.";
          };
        };
      }
    );
  };
}
