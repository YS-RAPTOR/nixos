{ pkgs }:
workspace: classPattern: command:
let
    script = pkgs.writeShellScript "launch-to-workspace" ''
        ${command} &

        for i in $(seq 1 60); do
            sleep 0.5
            ADDR=$(hyprctl clients -j | jq -r '.[] | select(.initialClass | test("${classPattern}")) | .address' | head -1)
            if [ -n "$ADDR" ]; then
                hyprctl dispatch movetoworkspacesilent "name:${workspace},address:$ADDR"
                exit 0
            fi
        done

        echo "launch-to-workspace: timed out waiting for class matching ${classPattern}"
    '';
in
"${script}"
