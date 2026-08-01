{ den, ... }: {
  den.aspects.development.agents.pi.pi.includes = [
    den.aspects.appearance.theme.stylix
    ({ user, ... }: {
      name = "pi(${user.userName})";

      homeManager =
        {
          config,
          pkgs,
          self',
          ...
        }:
        let
          colors = config.lib.stylix.colors.withHashtag;
        in
        {
          programs.pi-coding-agent = {
            enable = true;
            package = self'.packages.pi;
            extraPackages = [ pkgs.nodejs ];

            settings = {
              lastChangelogVersion = self'.packages.pi.version;
              theme = "stylix";
              defaultProvider = "openai-codex";
              defaultModel = "gpt-5.6-sol";
              defaultThinkingLevel = "high";
              editorPaddingX = 1;
              enabledModels = [ "openai-codex/gpt-5.6-*" ];
              hideThinkingBlock = false;
              showCacheMissNotices = true;
              images = {
                autoResize = true;
                blockImages = false;
              };
              outputPad = 1;
              packages = [ "npm:@ogulcancelik/pi-codex-compaction@0.1.3" ];
              terminal = {
                imageWidthCells = 60;
                showImages = true;
              };
              tuiMode = "fullscreen";
            };
          };

          home.file = {
            "${config.home.homeDirectory}/.pi/agent/settings.json".force = true;

            ".pi/agent/pi-codex-compaction.json".text = builtins.toJSON {
              autoCompact = false;
              thresholdRatio = 0.9;
            };

            ".pi/agent/themes/stylix.json".text = builtins.toJSON {
              "$schema" =
                "https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json";
              name = "stylix";
              colors = {
                accent = colors.base0D;
                border = colors.base03;
                borderAccent = colors.base0D;
                borderMuted = colors.base02;
                success = colors.base0B;
                error = colors.base08;
                warning = colors.base0A;
                muted = colors.base04;
                dim = colors.base03;
                text = "";
                thinkingText = colors.base04;

                selectedBg = colors.base02;
                userMessageBg = colors.base01;
                userMessageText = "";
                customMessageBg = colors.base01;
                customMessageText = "";
                customMessageLabel = colors.base0D;
                toolPendingBg = colors.base00;
                toolSuccessBg = colors.base01;
                toolErrorBg = colors.base01;
                toolTitle = colors.base0D;
                toolOutput = "";

                mdHeading = colors.base0E;
                mdLink = colors.base0D;
                mdLinkUrl = colors.base0C;
                mdCode = colors.base0B;
                mdCodeBlock = "";
                mdCodeBlockBorder = colors.base03;
                mdQuote = colors.base04;
                mdQuoteBorder = colors.base03;
                mdHr = colors.base03;
                mdListBullet = colors.base0C;

                toolDiffAdded = colors.base0B;
                toolDiffRemoved = colors.base08;
                toolDiffContext = colors.base04;

                syntaxComment = colors.base03;
                syntaxKeyword = colors.base0E;
                syntaxFunction = colors.base0D;
                syntaxVariable = colors.base08;
                syntaxString = colors.base0B;
                syntaxNumber = colors.base09;
                syntaxType = colors.base0A;
                syntaxOperator = colors.base0C;
                syntaxPunctuation = colors.base05;

                thinkingOff = colors.base03;
                thinkingMinimal = colors.base0D;
                thinkingLow = colors.base0C;
                thinkingMedium = colors.base0B;
                thinkingHigh = colors.base0A;
                thinkingXhigh = colors.base09;
                thinkingMax = colors.base08;

                bashMode = colors.base0A;
              };
            };
          };
        };
    })
  ];
}
