{ den, ... }: {
  den.aspects.terminal.session.herdr.fish-integration = {
    includes = [ den.aspects.terminal.shell.fish ];

    homeManager =
      { lib, pkgs, ... }:
      let
        herdrContext = pkgs.callPackage ./_scripts/package.nix { };
      in
      {
        home.packages = [ herdrContext ];

        programs.fish.interactiveShellInit = lib.mkAfter ''
          function __herdr_context_available
            status is-interactive; or return 1
            set -q HERDR_ENV; or return 1
            test "$HERDR_ENV" = 1; or return 1
            set -q HERDR_SOCKET_PATH; or return 1
            test -n "$HERDR_SOCKET_PATH"; or return 1
            set -q HERDR_PANE_ID; or return 1
            test -n "$HERDR_PANE_ID"; or return 1
          end

          function __herdr_context_next_generation
            set -g __herdr_context_generation (math "$__herdr_context_generation + 1")
          end

          function __herdr_context_refresh
            __herdr_context_available; or return

            command ${lib.getExe herdrContext} refresh >/dev/null 2>&1 &
            disown $last_pid 2>/dev/null
          end

          function __herdr_context_preexec --on-event fish_preexec
            __herdr_context_available; or return
            __herdr_context_next_generation

            set -l tokens
            printf %s "$argv[1]" | read --tokenize --list tokens
            printf '%s\0' $tokens | command ${lib.getExe herdrContext} active \
              "$__herdr_context_owner" "$__herdr_context_generation" >/dev/null 2>&1 &
            disown $last_pid 2>/dev/null
          end

          function __herdr_context_idle
            __herdr_context_available; or return
            __herdr_context_next_generation

            # Herdr tears down ordinary background children with an exiting pane.
            # Detach before returning so the final session-wide refresh survives `exit`.
            command ${lib.getExe' pkgs.util-linux "setsid"} --fork \
              ${lib.getExe herdrContext} idle \
              "$__herdr_context_owner" "$__herdr_context_generation" \
              </dev/null >/dev/null 2>&1
          end

          function __herdr_context_postexec --on-event fish_postexec
            __herdr_context_idle
          end

          function __herdr_context_pwd --on-variable PWD
            __herdr_context_refresh
          end

          set -g __herdr_context_generation 0
          set -g __herdr_context_owner "$fish_pid-"(random)"-"(random)
          __herdr_context_idle
        '';
      };
  };
}
