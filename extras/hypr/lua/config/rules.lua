hl.layer_rule({
	name = "waybar-blur",
	match = { namespace = "waybar" },
	blur = true,
})

hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "w[v1]", gaps_out = 0, gaps_in = 0, border_size = 0, no_rounding = true })
hl.workspace_rule({ workspace = "f[1]", gaps_out = 0, gaps_in = 0 })

hl.window_rule({
	name = "suppress-maximize",
	match = { class = ".*" },
	suppress_event = "maximize",
})

hl.window_rule({
	name = "xwayland-ghosts",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},
	no_focus = true,
})

hl.window_rule({
	name = "when-one-tiling-window",
	match = { float = false, workspace = "w[tv1]" },
	border_size = 0,
	rounding = 0,
})

hl.window_rule({
	name = "when-one-fullscreen-window",
	match = { float = false, workspace = "f[1]" },
	border_size = 0,
	rounding = 0,
})

local single_window_style = require("config.single_window_style")

hl.on("window.active", single_window_style.schedule)
hl.on("window.open", single_window_style.schedule)
hl.on("window.close", single_window_style.schedule)
hl.on("window.move_to_workspace", single_window_style.schedule)

single_window_style.schedule()
