{ config, ... }:
let
    colors = config.lib.stylix.colors;
in
{
    programs.oh-my-posh = {
        enable = true;
        enableFishIntegration = true;
        settings = builtins.fromJSON ''
            {
              "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
              "blocks": [
                {
                  "type": "prompt",
                  "alignment": "left",
                  "segments": [
                    {
                      "properties": {
                        "cache_duration": "none",
                        "style": "full"
                      },
                      "template": "[{{.Path}}]",
                      "foreground": "#${colors.base09}",
                      "type": "path",
                      "style": "plain"
                    },
                    {
                      "properties": {
                        "branch_icon": "\ue725 ",
                        "cache_duration": "none",
                        "fetch_stash_count": true,
                        "fetch_status": true,
                        "fetch_upstream_icon": true,
                        "fetch_worktree_count": true
                      },
                      "template": "[{{ .UpstreamIcon }}{{ .HEAD }}{{if .BranchStatus }} {{ .BranchStatus }}{{ end }}{{ if .Working.Changed }} \uf044 {{ .Working.String }}{{ end }}{{ if and (.Working.Changed) (.Staging.Changed) }} |{{ end }}{{ if .Staging.Changed }}<#2d3f76> \uf046 {{ .Staging.String }}</>{{ end }}{{ if gt .StashCount 0 }} \ueb4b {{ .StashCount }}{{ end }}]",
                      "foreground": "#${colors.base03}",
                      "type": "git",
                      "style": "plain",
                      "foreground_templates": [
                        "{{ if or (.Working.Changed) (.Staging.Changed) }}#${colors.base0D}{{ end }}",
                        "{{ if and (gt .Ahead 0) (gt .Behind 0) }}#${colors.base0D}{{ end }}",
                        "{{ if gt .Ahead 0 }}#${colors.base0E}{{ end }}",
                        "{{ if gt .Behind 0 }}#${colors.base0E}{{ end }}"
                      ]
                    },
                    {
                      "properties": {
                        "cache_duration": "none"
                      },
                      "template": "{{ if .Venv }}[\ue235 {{ .Venv }}]{{ end }}",
                      "foreground": "#${colors.base0F}",
                      "type": "python",
                      "style": "plain"
                    }
                  ]
                },
                {
                  "type": "rprompt",
                  "alignment": "right",
                  "segments": [
                    {
                      "properties": {
                        "always_enabled": true,
                        "cache_duration": "none",
                        "style": "austin",
                        "threshold": 500
                      },
                      "template": " {{ .FormattedMs }} ",
                      "foreground": "#${colors.base05}",
                      "type": "executiontime",
                      "style": "plain"
                    },
                    {
                      "properties": {
                        "always_enabled": true,
                        "cache_duration": "none"
                      },
                      "template": " {{ if gt .Code 0 }}\uea76{{else}}\uf42e{{ end }} ",
                      "foreground": "#${colors.base0C}",
                      "type": "status",
                      "style": "plain",
                      "foreground_templates": [
                        "{{ if gt .Code 0 }}#${colors.base08}{{ end }}"
                      ]
                    }
                  ]
                },
                {
                  "type": "prompt",
                  "alignment": "left",
                  "segments": [
                    {
                      "properties": {
                        "cache_duration": "none"
                      },
                      "template": " \u2514❯",
                      "foreground": "#${colors.base0B}",
                      "type": "text",
                      "style": "plain"
                    }
                  ],
                  "newline": true
                }
              ],
              "version": 3,
              "final_space": true
            }
        '';
    };
}
