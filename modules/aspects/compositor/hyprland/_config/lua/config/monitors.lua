local M = {
    max_managed = 3,
    preferred = "eDP-1",
    prefixes = { "N", "A", "C" },
    scrolling_count = 3,
    workspace_count = 5,
}

local ownership = {}
local ownership_monitor = {}

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = "auto",
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

return M
