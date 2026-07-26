{ den, ... }: {
  den.aspects.yashan.includes = [
    den.batteries.primary-user
    (den.batteries.user-shell "fish")
    (den.batteries.editor.default { command = [ "nvim" ]; })
    (den.batteries.pager.default {
      command = [
        "bat"
        "--paging=always"
      ];
    })
    (den.batteries.terminal.default {
      command = [ "ghostty" ];
      execArgs = [ "-e" ];
      windowTitle = "Ghostty";
    })
    (den.batteries.browser.default {
      command = [ "vivaldi" ];
      privateCommand = [
        "vivaldi"
        "-incognito"
      ];
      desktopFile = "vivaldi-stable.desktop";
    })
    (den.batteries.file-manager.default { command = [ "nautilus" ]; })
    (den.batteries.launcher.default {
      command = [
        "wofi"
        "--show"
        "drun"
      ];
    })
    den.aspects.services.docker
    den.aspects.system.user
    den.aspects.services.credentials
    den.aspects.services.removable-media
    den.aspects.shell.stylix
    den.aspects.compositor.hyprland
    den.aspects.shell.wallpaper
    den.aspects.shell.lock
    den.aspects.shell.idle
    den.aspects.shell.notifications
    den.aspects.shell.polkit
    den.aspects.shell.startup
    den.aspects.shell.waybar
    den.aspects.shell.file-manager
    den.aspects.shell.launcher
    den.aspects.shell.user-dirs
    den.aspects.terminal.fish
    den.aspects.terminal.prompt
    den.aspects.terminal.tmux
    den.aspects.terminal.ghostty
    den.aspects.terminal.kitty
    den.aspects.browser.firefox
    den.aspects.browser.vivaldi
    den.aspects.applications.freeoffice
    den.aspects.applications.slack
    den.aspects.applications.teams
    den.aspects.editor.neovim
    den.aspects.editor.vscode
    den.aspects.tooling.cli
    den.aspects.tooling.navigation
    den.aspects.tooling.pager
    den.aspects.tooling.direnv
    den.aspects.tooling.git
    den.aspects.tooling.docs
    den.aspects.tooling.toolchains
    den.aspects.tooling.swift
    den.aspects.tooling.kotlin
    den.aspects.tooling.devops
    den.aspects.tooling.android
    den.aspects.agent.packages
    den.aspects.agent.opencode
    den.aspects.operations.raptor
    den.aspects.operations.auto-update
  ];
}
