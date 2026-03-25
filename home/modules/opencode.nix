{ settings, ... }:
{
    xdg.configFile."opencode/opencode-notifier.json".text = builtins.toJSON {
        sound = false;
        notification = true;
    };

    programs.opencode = {
        enable = true;
        settings = {
            theme = "stylix";
            autoupdate = true;
            plugin = [
                "@mohak34/opencode-notifier@latest"
                "opencode-antigravity-auth@latest"
            ];
            disabled_providers = [
                "amazon-bedrock"
                "github-models"
            ];
            model = settings.ai.default;
            small_model = settings.ai.defaultSmall;
            permission = {
                bash = {
                    "git status" = "allow";
                    "git diff" = "allow";
                    "git worktree list" = "allow";
                    "git log" = "allow";
                    "git show" = "allow";
                    "git shortlog" = "allow";
                    "git reflog" = "allow";
                    "git blame" = "allow";
                    "git describe" = "allow";
                    "git ls-files" = "allow";
                    "git grep" = "allow";
                    "git bisect log" = "allow";
                    "git " = "ask";
                    "" = "allow";
                };
            };
            agent = {
                build-ask = {
                    description = "Primary build-style agent that asks before using tools";
                    mode = "primary";
                    model = settings.ai.default;
                    permission = {
                        edit = "ask";
                        task = {
                            "*" = "ask";
                        };
                        bash = {
                            "*" = "ask";
                        };
                    };
                };
            };
            keybinds = {
                messages_half_page_down = "ctrl+d";
                messages_half_page_up = "ctrl+u";
                messages_last = "alt+g";
            };
            instructions = [
                "CONTRIBUTING.md"
                "docs/guidelines.md"
                ".cursor/rules/.md"
                ".github/**/.md"
            ];
        };
    };
}
