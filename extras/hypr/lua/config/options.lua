local context = require("lib.context")
local colors = context.colors or {}

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")

hl.config({
	general = {
		border_size = 2,
		gaps_in = 4,
		gaps_out = 4,
		col = {
			active_border = colors.base0B or "#41a6b5",
		},
		resize_on_border = false,
		allow_tearing = false,
		layout = "dwindle",
	},

	group = {
		col = {
			border_active = colors.base0B or "#41a6b5",
		},
		groupbar = {
			col = {
				active = colors.base0B or "#41a6b5",
			},
		},
	},

	decoration = {
		rounding = 1,
		rounding_power = 4,
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		shadow = {
			enabled = true,
			range = 4,
			render_power = 3,
		},
		blur = {
			enabled = true,
			size = 5,
			passes = 2,
			vibrancy = 0.1696,
		},
	},

	dwindle = {
		preserve_split = true,
	},

	master = {
		new_status = "master",
	},

	scrolling = {
		fullscreen_on_one_column = true,
	},

	misc = {
		force_default_wallpaper = -1,
		disable_hyprland_logo = false,
	},

	xwayland = {
		force_zero_scaling = true,
	},
})
