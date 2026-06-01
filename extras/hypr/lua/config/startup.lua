local context = require("lib.context")

local startup = context.startup or {}

hl.on("hyprland.start", function()
	for _, command in ipairs(startup) do
		hl.exec_cmd(command)
	end
end)
