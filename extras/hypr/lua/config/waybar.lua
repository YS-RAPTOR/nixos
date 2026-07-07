local M = {}

local config_home = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")
local output_path = config_home .. "/waybar/hyprland-workspaces.json"
local workspace_icon = ""

local function quote_json(value)
	return '"' .. tostring(value):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

local function write_line(lines, indent, value)
	table.insert(lines, string.rep("  ", indent) .. value)
end

local function workspace_names(monitors, workspace_name, workspace_count)
	local names = {}
	for monitor_index, _ in ipairs(monitors) do
		for key = 1, workspace_count do
			table.insert(names, workspace_name(monitor_index, key))
		end
	end
	return names
end

function M.write_workspaces(monitors, workspace_name, workspace_count)
	local lines = {}
	local names = workspace_names(monitors, workspace_name, workspace_count)

	write_line(lines, 0, "{")
	write_line(lines, 1, quote_json("hyprland/workspaces") .. ": {")
	write_line(lines, 2, quote_json("format") .. ": " .. quote_json("{icon}") .. ",")
	write_line(lines, 2, quote_json("format-icons") .. ": {")
	for _, name in ipairs(names) do
		write_line(lines, 3, quote_json(name) .. ": " .. quote_json(workspace_icon) .. ",")
	end
	write_line(lines, 3, quote_json("active") .. ": " .. quote_json("") .. ",")
	write_line(lines, 3, quote_json("default") .. ": " .. quote_json(workspace_icon))
	write_line(lines, 2, "}")
	write_line(lines, 1, "}")
	write_line(lines, 0, "}")

	local file = io.open(output_path, "w")
	if not file then
		return
	end
	file:write(table.concat(lines, "\n"), "\n")
	file:close()
end

function M.reload()
	hl.exec_cmd("pkill -SIGUSR2 waybar >/dev/null 2>&1 || true")
end

return M
