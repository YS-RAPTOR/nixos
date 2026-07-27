local commands = require("lib.commands")
local monitors = require("config.monitors")
local runtime = require("runtime")

local main = "SUPER"

local function open_terminal()
    local window = hl.get_active_window()
    local initial_title = window and window.initial_title or ""
    local directory = os.getenv("HOME") or "."
    local is_terminal = initial_title == runtime.terminal_window_title and "1" or "0"

    hl.exec_cmd(runtime.terminal_session .. " " .. commands.quote(directory) .. " " .. commands.quote(is_terminal))
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
        return
    end

    local window = hl.get_active_window()
    local layout = window and window.layout or nil
    local column = layout and layout.name == "scrolling" and layout.column or nil
    local width = column and type(column.width) == "number" and column.width or 0

    hl.dispatch(hl.dsp.layout(width >= 0.75 and "colresize 0.5" or "colresize 1.0"))
end

local function focus_workspace(monitor_index, key)
    hl.dispatch(hl.dsp.focus({ workspace = "name:" .. monitors.workspace_name(monitor_index, key) }))
end

local function move_to_workspace(monitor_index, key)
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
hl.bind(main .. " + E", hl.dsp.exec_cmd(runtime.file_manager))
hl.bind(main .. " + R", hl.dsp.exec_cmd(runtime.launcher))
hl.bind(main .. " + D", hl.dsp.exec_cmd(runtime.browser))
hl.bind(main .. " + SHIFT + D", hl.dsp.exec_cmd(runtime.private_browser))

hl.bind(main .. " + SHIFT + P", hl.dsp.window.pseudo())
hl.bind(main .. " + SHIFT + A", hl.dsp.layout("togglesplit"))

hl.bind(main .. " + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(main .. " + F", toggle_scroll_colsize)
hl.bind(main .. " + A", hl.dsp.window.fullscreen())
hl.bind(main .. " + G", hl.dsp.layout("colresize +conf"))
hl.bind(main .. " + P", hl.dsp.layout("promote"))

hl.bind(main .. " + SHIFT + S", hl.dsp.exec_cmd(runtime.hyprshot .. " -z -m output"))
hl.bind("Print", hl.dsp.exec_cmd(runtime.hyprshot .. " -z -m output"))
hl.bind("CONTROL + Print", hl.dsp.exec_cmd(runtime.hyprshot .. " -z -m window"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(runtime.hyprshot .. " -z -m region"))

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
    hl.dsp.exec_cmd(runtime.wpctl .. " set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioLowerVolume",
    hl.dsp.exec_cmd(runtime.wpctl .. " set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioMute",
    hl.dsp.exec_cmd(runtime.wpctl .. " set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    { locked = true, repeating = true }
)
hl.bind(
    "XF86AudioMicMute",
    hl.dsp.exec_cmd(runtime.wpctl .. " set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
    { locked = true, repeating = true }
)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("display-brightness up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("display-brightness down"), { locked = true, repeating = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd(runtime.playerctl .. " next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(runtime.playerctl .. " play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(runtime.playerctl .. " play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(runtime.playerctl .. " previous"), { locked = true })

hl.bind(main .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(main .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
