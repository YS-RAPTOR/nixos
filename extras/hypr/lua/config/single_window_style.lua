local M = {}

local function value_at(value, key, index)
	if type(value) ~= "table" then
		return 0
	end
	return value[key] or value[index] or 0
end

local function workspace_selector(workspace)
	return "n[s:" .. workspace.name .. "]n[e:" .. workspace.name .. "]"
end

local function apply_single_window_style(selector, enabled)
		hl.workspace_rule({
		workspace = selector,
		gaps_out = enabled and 0 or 4,
		gaps_in = enabled and 0 or 4,
		border_size = enabled and 0 or 2,
		no_rounding = enabled,
	})
end

local function update_single_window_style()
	local workspace = hl.get_active_workspace()
	local window = hl.get_active_window()
	local monitor = hl.get_active_monitor()
	if not workspace or not window or not monitor then
		return
	end

	local selector = workspace_selector(workspace)
	local scale = monitor.scale or 1
	local monitor_width = math.floor(monitor.width / scale)
	local monitor_height = math.floor(monitor.height / scale)
	local window_width = value_at(window.size, "x", 1)
	local window_height = value_at(window.size, "y", 2)
	local fills_monitor = window_width >= monitor_width * 0.95 and window_height >= monitor_height * 0.9
	local enabled = workspace.tiled_layout == "scrolling" and not window.floating and fills_monitor

	apply_single_window_style(selector, enabled)
end

function M.schedule()
	hl.timer(update_single_window_style, { timeout = 50, type = "oneshot" })
end

return M
