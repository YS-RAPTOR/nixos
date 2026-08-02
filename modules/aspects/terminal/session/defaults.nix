{ den, ... }: {
  den.batteries.terminal.session.defaults = {
    herdr = {
      includes = [ den.aspects.terminal.session.herdr ];

      homeManager =
        {
          config,
          lib,
          pkgs,
          self',
          ...
        }:
        let
          herdr = self'.packages.herdr;
          terminalSession = pkgs.writeShellApplication {
            name = "herdr-terminal-session";
            text = ''
              session_timestamp="$(${lib.getExe' pkgs.coreutils "date"} +%s%N)"
              session="terminal-$session_timestamp-$$"
              export HERDR_SESSION="$session"

              trap '${lib.getExe herdr} session stop "$session" >/dev/null 2>&1 || true
                    ${lib.getExe herdr} session delete "$session" >/dev/null 2>&1 || true' EXIT

              set +e
              ${config.desktop.commands.terminalExec} ${lib.getExe herdr}
              status=$?
              set -e
              exit "$status"
            '';
          };
        in
        {
          assertions = [
            {
              assertion = config.desktop.commands.terminalExec != null;
              message = "A default terminal must be selected before the Herdr terminal session.";
            }
          ];
          desktop.commands.terminalSession = lib.getExe terminalSession;
        };
    };

    tmux = {
      includes = [ den.aspects.terminal.session.tmux ];

      homeManager =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          terminalSession = pkgs.writeShellApplication {
            name = "tmux-terminal-session";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.tmux
            ];
            text = ''
              directory="$1"
              is_terminal="$2"

              if [ "$is_terminal" = 1 ]; then
                  current=$(tmux display-message -p '#S' 2>/dev/null || true)
                  tmux_dir=$(tmux list-windows -t "$current" -F '#{pane_current_path}' 2>/dev/null | head -n 1)
                  [ -n "$tmux_dir" ] && directory=$tmux_dir
              fi

              session_base=$(basename "$directory")
              [ -n "$session_base" ] || session_base=tmux

              i=0
              while true; do
                  session=$(printf '%s-%03d' "$session_base" "$i")
                  tmux has-session -t "$session" >/dev/null 2>&1 || break
                  i=$((i + 1))
              done

              exec ${config.desktop.commands.terminalExec} tmux new-session -s "$session" -c "$directory"
            '';
          };
        in
        {
          assertions = [
            {
              assertion = config.desktop.commands.terminalExec != null;
              message = "A default terminal must be selected before the tmux terminal session.";
            }
          ];
          desktop.commands.terminalSession = lib.getExe terminalSession;
        };
    };
  };
}
