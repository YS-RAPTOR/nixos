hl.config({
	input = {
		kb_layout = "us",
		kb_variant = "",
		kb_model = "",
		kb_options = "",
		kb_rules = "",
		follow_mouse = 1,
		numlock_by_default = true,
		sensitivity = 0,
		accel_profile = "flat",
		touchpad = {
			natural_scroll = true,
			disable_while_typing = true,
		},
	},
})

hl.gesture({ fingers = 3, direction = "vertical", action = "workspace" })
hl.gesture({ fingers = 3, direction = "horizontal", action = "scroll_move" })
hl.gesture({ fingers = 4, direction = "horizontal", action = "move" })

hl.device({
	name = "epic-mouse-v1",
	sensitivity = -0.5,
})
