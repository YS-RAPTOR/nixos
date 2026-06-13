local M = {}
local waybar = require("config.waybar")

M.layout = "pyramid-center"
M.max_managed = 3
M.workspace_count = 5
M.primary = "eDP-1"

M.layouts = {
    "pyramid-left",
    "pyramid-center",
    "pyramid-right",
    "line-left",
    "line-center-left",
    "line-center-right",
    "line-right",
}

local workspace_prefixes = { "N", "A", "C" }

local function logical_size(monitor)
    local scale = monitor.height > 1440 and 1.6 or 1
    return {
        width = math.floor(monitor.width / scale),
        height = math.floor(monitor.height / scale),
    }
end

local function scale_for(monitor)
    return monitor.height > 1440 and 1.6 or 1
end

local function position(x, y)
    return string.format("%dx%d", math.floor(x), math.floor(y))
end

local function copy_monitors(monitors)
    local out = {}
    for _, monitor in ipairs(monitors) do
        table.insert(out, monitor)
    end
    return out
end

local function sort_monitors(monitors)
    table.sort(monitors, function(a, b)
        if a.name == M.primary then
            return true
        end
        if b.name == M.primary then
            return false
        end

        local a_internal = a.name:match("^eDP") or a.name:match("^LVDS")
        local b_internal = b.name:match("^eDP") or b.name:match("^LVDS")
        if a_internal ~= b_internal then
            return a_internal ~= nil
        end

        return a.name < b.name
    end)
    return monitors
end

function M.ordered()
    local monitors = sort_monitors(copy_monitors(hl.get_monitors()))
    local out = {}
    for index, monitor in ipairs(monitors) do
        if index <= M.max_managed then
            table.insert(out, monitor)
        end
    end
    return out
end

local function pyramid_positions(monitors, variant)
    local primary = monitors[1]
    local primary_size = logical_size(primary)
    local result = {
        [primary.name] = { x = 0, y = 0 },
    }

    local top = {}
    if #monitors == 2 then
        top = { variant == "right" and "right" or variant == "center" and "center" or "left" }
    else
        if variant == "right" then
            top = { "right", "left" }
        else
            top = { "left", "right" }
        end
    end

    local max_top_height = 0
    for index = 2, #monitors do
        max_top_height = math.max(max_top_height, logical_size(monitors[index]).height)
    end

    result[primary.name].y = max_top_height

    local slot_monitor = {}
    for index = 2, #monitors do
        slot_monitor[top[index - 1]] = monitors[index]
    end

    local top_order = #monitors == 2 and top or { "left", "right" }
    local top_width = 0
    for _, slot in ipairs(top_order) do
        top_width = top_width + logical_size(slot_monitor[slot]).width
    end

    local row_x = 0
    if variant == "center" then
        row_x = (primary_size.width - top_width) / 2
    elseif variant == "right" then
        row_x = primary_size.width - top_width
    end

    local slot_x = {}
    for _, slot in ipairs(top_order) do
        local monitor = slot_monitor[slot]
        slot_x[slot] = row_x
        row_x = row_x + logical_size(monitor).width
    end

    for index = 2, #monitors do
        local monitor = monitors[index]
        local size = logical_size(monitor)
        local slot = top[index - 1]

        result[monitor.name] = { x = slot_x[slot], y = max_top_height - size.height }
    end

    return result
end

local function line_positions(monitors, variant)
    local result = {}
    local primary = monitors[1]
    local primary_size = logical_size(primary)

    if variant == "left" then
        local x = 0
        for index = #monitors, 2, -1 do
            local monitor = monitors[index]
            local size = logical_size(monitor)
            result[monitor.name] = { x = x, y = 0 }
            x = x + size.width
        end
        result[primary.name] = { x = x, y = 0 }
        return result
    end

    if variant == "right" then
        local x = primary_size.width
        result[primary.name] = { x = 0, y = 0 }
        for index = 2, #monitors do
            local monitor = monitors[index]
            result[monitor.name] = { x = x, y = 0 }
            x = x + logical_size(monitor).width
        end
        return result
    end

    local next_side = variant == "center-left" and "left" or "right"
    local left_edge = 0
    local right_edge = primary_size.width
    result[primary.name] = { x = 0, y = 0 }

    for index = 2, #monitors do
        local monitor = monitors[index]
        local size = logical_size(monitor)

        if next_side == "left" then
            left_edge = left_edge - size.width
            result[monitor.name] = { x = left_edge, y = 0 }
            next_side = "right"
        else
            result[monitor.name] = { x = right_edge, y = 0 }
            right_edge = right_edge + size.width
            next_side = "left"
        end
    end

    return result
end

local function positions_for(monitors)
    local family, variant = M.layout:match("^(pyramid)%-(.+)$")
    if family == "pyramid" then
        return pyramid_positions(monitors, variant)
    end

    family, variant = M.layout:match("^(line)%-(.+)$")
    if family == "line" then
        return line_positions(monitors, variant)
    end

    return line_positions(monitors, "right")
end

function M.workspace_name(monitor_index, key)
    local prefix = workspace_prefixes[monitor_index] or ("M" .. monitor_index)
    return prefix .. "-" .. key
end

function M.apply_workspace_rules(monitors)
	for monitor_index, monitor in ipairs(monitors) do
		for key = 1, M.workspace_count do
			hl.workspace_rule({
				workspace = "name:" .. M.workspace_name(monitor_index, key),
				monitor = monitor.name,
				default = key == 1,
				persistent = true,
				layout = key <= 3 and "scrolling" or "dwindle",
			})
		end
	end
end

local function apply_default_workspaces(monitors)
	for monitor_index, monitor in ipairs(monitors) do
		local workspace = monitor.active_workspace
		if workspace and not workspace.is_persistent then
			hl.dispatch(hl.dsp.focus({ workspace = "name:" .. M.workspace_name(monitor_index, 1) }))
		end
	end
end

function M.apply()
    hl.monitor({ output = "", mode = "highres", position = "auto", scale = 1 })

    local monitors = M.ordered()
    if #monitors == 0 then
        return
    end

    local placements = positions_for(monitors)
    for _, monitor in ipairs(monitors) do
        local placement = placements[monitor.name]
        hl.monitor({
            output = monitor.name,
            mode = "highres",
            position = position(placement.x, placement.y),
            scale = scale_for(monitor),
        })
    end

    M.apply_workspace_rules(monitors)
    apply_default_workspaces(monitors)
    waybar.write_workspaces(monitors, M.workspace_name, M.workspace_count)
    waybar.reload()
end

function M.cycle_layout()
    for index, layout in ipairs(M.layouts) do
        if layout == M.layout then
            M.layout = M.layouts[(index % #M.layouts) + 1]
            M.apply()
            return
        end
    end

    M.layout = M.layouts[1]
    M.apply()
end

local function schedule_apply()
    hl.timer(function()
        M.apply()
    end, { timeout = 500, type = "oneshot" })
end

hl.on("hyprland.start", schedule_apply)
hl.on("monitor.added", schedule_apply)
hl.on("monitor.removed", schedule_apply)

M.apply()

return M
