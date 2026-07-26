local M = {
    max_managed = 3,
    preferred = "eDP-1",
    prefixes = { "N", "A", "C" },
    scrolling_count = 3,
    workspace_count = 5,
}

local ownership = {}
local ownership_monitor = {}
local monitor_rules = {}
local monitor_scales = {}

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

function M.workspace_name(monitor_index, key)
    return M.prefixes[monitor_index] .. "-" .. key
end

function M.exact_selector(name)
    return "n[s:" .. name .. "] n[e:" .. name .. "]"
end

function M.style_selector(name)
    return "n[e:" .. name .. "] n[s:" .. name .. "]"
end

for monitor_index = 1, M.max_managed do
    for key = 1, M.workspace_count do
        local name = M.workspace_name(monitor_index, key)
        hl.workspace_rule({
            workspace = M.exact_selector(name),
            layout = key <= M.scrolling_count and "scrolling" or "dwindle",
        })
    end
end

local function is_internal(monitor)
    return monitor.name:match("^eDP") or monitor.name:match("^LVDS") or monitor.name:match("^DSI")
end

local function copy_monitors()
    local monitors = {}
    for _, monitor in ipairs(hl.get_monitors()) do
        if not monitor.is_mirror then
            table.insert(monitors, monitor)
        end
    end
    return monitors
end

local function scale_for(monitor)
    return monitor.height > 1440 and 1.6 or 1
end

local function apply_monitor_scales(monitors)
    local connected = {}

    for _, monitor in ipairs(monitors) do
        local scale = scale_for(monitor)
        connected[monitor.name] = true

        if monitor_scales[monitor.name] ~= scale then
            if monitor_rules[monitor.name] then
                monitor_rules[monitor.name]:set_enabled(false)
            end

            monitor_rules[monitor.name] = hl.monitor({
                output = monitor.name,
                mode = "preferred",
                position = "auto",
                scale = scale,
            })
            monitor_scales[monitor.name] = scale
        end
    end

    for name, rule in pairs(monitor_rules) do
        if not connected[name] then
            rule:set_enabled(false)
            monitor_rules[name] = nil
            monitor_scales[name] = nil
        end
    end
end

function M.ordered()
    local monitors = copy_monitors()
    table.sort(monitors, function(a, b)
        if a.name == M.preferred then
            return true
        end
        if b.name == M.preferred then
            return false
        end

        local a_internal = is_internal(a)
        local b_internal = is_internal(b)
        if a_internal ~= b_internal then
            return a_internal ~= nil
        end

        return a.name < b.name
    end)
    return monitors
end

local function apply_workspace_ownership()
    local monitors = M.ordered()
    apply_monitor_scales(monitors)

    for monitor_index = 1, M.max_managed do
        local monitor = monitors[monitor_index]
        local desired_monitor = monitor and monitor.name or nil

        for key = 1, M.workspace_count do
            local name = M.workspace_name(monitor_index, key)
            if ownership_monitor[name] ~= desired_monitor then
                if ownership[name] then
                    ownership[name]:set_enabled(false)
                end

                ownership[name] = nil
                ownership_monitor[name] = desired_monitor

                if desired_monitor then
                    ownership[name] = hl.workspace_rule({
                        workspace = "name:" .. name,
                        monitor = desired_monitor,
                        default = key == 1,
                        persistent = true,
                    })
                end
            end
        end
    end
end

local topology_timer

local function schedule_topology_update()
    if not topology_timer then
        return
    end

    topology_timer:set_enabled(false)
    topology_timer:set_timeout(200)
    topology_timer:set_enabled(true)
end

hl.on("hyprland.start", function()
    topology_timer = hl.timer(function()
        topology_timer:set_enabled(false)
        apply_workspace_ownership()
    end, { timeout = 200, type = "repeat" })
end)
hl.on("monitor.added", schedule_topology_update)
hl.on("monitor.removed", schedule_topology_update)
hl.on("monitor.layout_changed", schedule_topology_update)

apply_workspace_ownership()

return M
