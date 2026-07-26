{ den, ... }: {
  den.aspects.agent.opencode.includes = [
    den.aspects.shell.stylix
    ({ user, ... }: {
      name = "opencode(${user.userName})";

      homeManager = { lib, self', ... }: {
        xdg.configFile."opencode/opencode-notifier.json".text = builtins.toJSON {
          sound = false;
          notification = true;
        };

        programs.opencode = {
          enable = true;
          package = self'.packages.opencode;

          tui = {
            theme = "stylix";
            keybinds = {
              messages_half_page_down = "ctrl+d";
              messages_half_page_up = "ctrl+u";
              messages_last = "alt+g";
            };
          };

          settings = {
            autoupdate = false;
            model = "openai/gpt-5.6-sol";
            small_model = "openai/gpt-5.6-luna";

            plugin = [
              "@mohak34/opencode-notifier@latest"
              "opencode-antigravity-auth@latest"
            ];

            disabled_providers = [
              "amazon-bedrock"
              "github-models"
            ];

            permission.bash = {
              "*" = "allow";
              "git *" = lib.hm.dag.entryAfter [ "*" ] "ask";
              "git status*" = lib.hm.dag.entryAfter [ "git *" ] "allow";
              "git diff*" = lib.hm.dag.entryAfter [ "git *" ] "allow";
              "git worktree list*" = lib.hm.dag.entryAfter [ "git *" ] "allow";
              "git log*" = lib.hm.dag.entryAfter [ "git *" ] "allow";
              "git show*" = lib.hm.dag.entryAfter [ "git *" ] "allow";
              "git shortlog*" = lib.hm.dag.entryAfter [ "git *" ] "allow";
              "git reflog*" = lib.hm.dag.entryAfter [ "git *" ] "allow";
              "git blame*" = lib.hm.dag.entryAfter [ "git *" ] "allow";
              "git describe*" = lib.hm.dag.entryAfter [ "git *" ] "allow";
              "git ls-files*" = lib.hm.dag.entryAfter [ "git *" ] "allow";
              "git grep*" = lib.hm.dag.entryAfter [ "git *" ] "allow";
              "git bisect log*" = lib.hm.dag.entryAfter [ "git *" ] "allow";
            };

            agent.build-ask = {
              description = "Primary build-style agent that asks before using tools";
              mode = "primary";
              model = "openai/gpt-5.6-sol";
              permission = {
                edit = "ask";
                task = "ask";
                bash = "ask";
              };
            };

            instructions = [
              "CONTRIBUTING.md"
              "docs/guidelines.md"
              ".cursor/rules/**/*.md"
              ".github/**/*.md"
            ];
          };
        };
      };
    })
  ];
}
