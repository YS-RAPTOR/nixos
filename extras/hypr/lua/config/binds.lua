local commands = require("lib.commands")
local context = require("lib.context")
local monitors = require("config.monitors")
local single_window_style = require("config.single_window_style")

local main = "SUPER"
local menu = "wofi --show drun"
local browser = "vivaldi"
local file_manager = "nautilus"

local function open_terminal()
	local window = hl.get_active_window()
	local initial_title = window and window.initial_title or ""
	local directory = context.user.homeDir or os.getenv("HOME") or "."
	local is_ghostty = initial_title == "Ghostty" and "1" or "0"
	local script = [[
directory=$1
is_ghostty=$2

if [ "$is_ghostty" = 1 ]; then
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

exec ghostty -e tmux new-session -s "$session" -c "$directory"
]]

	hl.exec_cmd(
		"bash -lc "
			.. commands.quote(script)
			.. " -- "
			.. commands.quote(directory)
			.. " "
			.. commands.quote(is_ghostty)
	)
end

local function scroll_or_default(scroll_dispatcher, default_dispatcher)
	local workspace = hl.get_active_workspace()
	if workspace and workspace.tiled_layout == "scrolling" then
		hl.dispatch(scroll_dispatcher)
	elseif default_dispatcher then
		hl.dispatch(default_dispatcher)
	end
end

local function toggle_scroll_colsize()
	local workspace = hl.get_active_workspace()
	if not workspace or workspace.tiled_layout ~= "scrolling" then
		hl.dispatch(hl.dsp.window.fullscreen())
		single_window_style.schedule()
		return
	end

	local window = hl.get_active_window()
	local monitor = hl.get_active_monitor()
	if not window or not monitor then
		return
	end

	local monitor_width = math.floor(monitor.width / monitor.scale)
	local window_width = window.size and window.size.x or 0

	if window_width * 100 >= monitor_width * 75 then
		hl.dispatch(hl.dsp.layout("colresize 0.5"))
	else
		hl.dispatch(hl.dsp.layout("colresize 1.0"))
	end
	single_window_style.schedule()
end

local function restore_scroll_colsize()
	hl.dispatch(hl.dsp.layout("colresize +conf"))
	single_window_style.schedule()
end

local function brightness(action)
	local parts = {}
	for _, device in ipairs((context.hardware or {}).backlights or {}) do
		table.insert(parts, "brightnessctl -e -d " .. commands.quote(device) .. " set " .. commands.quote(action))
	end
	return table.concat(parts, " && ")
end

local function focus_workspace(monitor_index, key)
	monitors.apply_workspace_rules(monitors.ordered())
	hl.dispatch(hl.dsp.focus({ workspace = "name:" .. monitors.workspace_name(monitor_index, key) }))
end

local function move_to_workspace(monitor_index, key)
	monitors.apply_workspace_rules(monitors.ordered())
	hl.dispatch(hl.dsp.window.move({ workspace = "name:" .. monitors.workspace_name(monitor_index, key) }))
end

local function bind_workspace_group(monitor_index, modifier)
	local prefix = modifier == "" and main or (main .. " + " .. modifier)
	for key = 1, monitors.workspace_count do
		hl.bind(prefix .. " + " .. key, function()
			focus_workspace(monitor_index, key)
		end)
		hl.bind(prefix .. " + SHIFT + " .. key, function()
			move_to_workspace(monitor_index, key)
		end)
	end
end

hl.bind(main .. " + W", hl.dsp.window.close())
hl.bind(main .. " + Q", open_terminal)
hl.bind(main .. " + E", hl.dsp.exec_cmd(file_manager))
hl.bind(main .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(main .. " + D", hl.dsp.exec_cmd(browser))
hl.bind(main .. " + SHIFT + D", hl.dsp.exec_cmd(browser .. " -incognito"))

hl.bind(main .. " + SHIFT + P", hl.dsp.window.pseudo())
hl.bind(main .. " + SHIFT + A", hl.dsp.layout("togglesplit"))

hl.bind(main .. " + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(main .. " + F", toggle_scroll_colsize)
hl.bind(main .. " + A", hl.dsp.window.fullscreen())
hl.bind(main .. " + G", restore_scroll_colsize)
hl.bind(main .. " + P", hl.dsp.layout("promote"))
hl.bind(main .. " + SHIFT + M", monitors.cycle_layout, { description = "Cycle monitor layout" })

hl.bind(main .. " + SHIFT + S", hl.dsp.exec_cmd("hyprshot -z -m output"))
hl.bind("Print", hl.dsp.exec_cmd("hyprshot -z -m output"))
hl.bind("CONTROL + Print", hl.dsp.exec_cmd("hyprshot -z -m window"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("hyprshot -z -m region"))

hl.bind(main .. " + H", function()
	scroll_or_default(hl.dsp.layout("focus l"), hl.dsp.focus({ direction = "l" }))
end)
hl.bind(main .. " + L", function()
	scroll_or_default(hl.dsp.layout("focus r"), hl.dsp.focus({ direction = "r" }))
end)
hl.bind(main .. " + K", function()
	scroll_or_default(hl.dsp.layout("focus u"), hl.dsp.focus({ direction = "u" }))
end)
hl.bind(main .. " + J", function()
	scroll_or_default(hl.dsp.layout("focus d"), hl.dsp.focus({ direction = "d" }))
end)

hl.bind(main .. " + SHIFT + H", function()
	scroll_or_default(hl.dsp.layout("swapcol l"), hl.dsp.window.swap({ direction = "l" }))
end)
hl.bind(main .. " + SHIFT + L", function()
	scroll_or_default(hl.dsp.layout("swapcol r"), hl.dsp.window.swap({ direction = "r" }))
end)
hl.bind(main .. " + SHIFT + K", hl.dsp.window.swap({ direction = "u" }))
hl.bind(main .. " + SHIFT + J", hl.dsp.window.swap({ direction = "d" }))

hl.bind(main .. " + CONTROL + H", hl.dsp.window.resize({ x = -10, y = 0, relative = true }), { repeating = true })
hl.bind(main .. " + CONTROL + L", hl.dsp.window.resize({ x = 10, y = 0, relative = true }), { repeating = true })
hl.bind(main .. " + CONTROL + K", hl.dsp.window.resize({ x = 0, y = -10, relative = true }), { repeating = true })
hl.bind(main .. " + CONTROL + J", hl.dsp.window.resize({ x = 0, y = 10, relative = true }), { repeating = true })

hl.bind(main .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(main .. " + CONTROL + S", hl.dsp.window.move({ workspace = "special:magic" }))

bind_workspace_group(1, "")
bind_workspace_group(2, "ALT")
bind_workspace_group(3, "CTRL")

hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioMute",
	hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioMicMute",
	hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
	{ locked = true, repeating = true }
)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(brightness("5%+")), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(brightness("5%-")), { locked = true, repeating = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

hl.bind(main .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(main .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
