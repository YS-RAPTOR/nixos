local monitors = require("config.monitors")

hl.layer_rule({
    name = "waybar-blur",
    match = { namespace = "waybar" },
    blur = true,
})

for monitor_index = 1, monitors.max_managed do
    for key = monitors.scrolling_count + 1, monitors.workspace_count do
        local name = monitors.workspace_name(monitor_index, key)
        local selector = monitors.style_selector(name) .. " w[tv1]"

        hl.workspace_rule({ workspace = selector, gaps_out = 0, gaps_in = 0 })
        hl.window_rule({
            name = "dwindle-single-window-" .. name,
            match = { float = false, pin = false, workspace = selector },
            border_size = 0,
            rounding = 0,
        })
    end
end

for _, selector in ipairs({ "f[0]", "f[1]" }) do
    hl.workspace_rule({ workspace = selector, gaps_out = 0, gaps_in = 0 })
end

for _, state in ipairs({ 1, 2 }) do
    hl.window_rule({
        name = "fullscreen-decoration-" .. state,
        match = { fullscreen_state_internal = state },
        border_size = 0,
        rounding = 0,
    })
end

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

require("config.smart_style")
