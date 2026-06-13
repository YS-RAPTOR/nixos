local json = require("lib.json")

local function read_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local content = file:read("*a")
	file:close()
	return content
end

local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local content = read_file(config_home .. "/nix/context.json")

if not content then
	return {
		colors = {},
		fonts = {},
		paths = {},
		user = {},
		hardware = {},
	}
end

return json.decode(content)
