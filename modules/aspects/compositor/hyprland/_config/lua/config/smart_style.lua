local monitors = require("config.monitors")

local M = {}
local scrolling_rules = {}

local function create_scrolling_rules()
    for monitor_index = 1, monitors.max_managed do
        for key = 1, monitors.scrolling_count do
            local name = monitors.workspace_name(monitor_index, key)
            local selector = monitors.style_selector(name)

            scrolling_rules[name] = {
                enabled = false,
                gaps = hl.workspace_rule({
                    workspace = selector,
                    enabled = false,
                    gaps_in = 0,
                    gaps_out = 0,
                }),
                decorations = hl.window_rule({
                    name = "scrolling-full-width-" .. name,
                    enabled = false,
                    match = {
                        workspace = selector,
                        float = false,
                        pin = false,
                    },
                    border_size = 0,
                    rounding = 0,
                }),
            }
        end
    end
end

local function set_override(name, enabled)
    local state = scrolling_rules[name]
    if not state or state.enabled == enabled then
        return
    end

    state.enabled = enabled
    if enabled then
        state.gaps:set_enabled(true)
        state.decorations:set_enabled(true)
    else
        state.decorations:set_enabled(false)
        state.gaps:set_enabled(false)
    end
end

local function monitor_workarea(monitor)
    local reserved = monitor.reserved or {}
    local pixel_width = monitor.transform % 2 == 1 and monitor.height or monitor.width
    local logical_width = math.floor(pixel_width / monitor.scale + 0.5)
    local left = monitor.x + (reserved.left or 0)
    local right = monitor.x + logical_width - (reserved.right or 0)
    return left, right
end

local function qualifies(workspace)
    if workspace.tiled_layout ~= "scrolling" or not workspace.visible or not workspace.monitor then
        return false
    end

    local work_left, work_right = monitor_workarea(workspace.monitor)
    local columns = {}
    local total_columns = 0

    for _, window in ipairs(hl.get_windows({ workspace = workspace, mapped = true, floating = false })) do
        if not window.pinned then
            local layout = window.layout
            local column = layout and layout.name == "scrolling" and layout.column or nil
            if column then
                local state = columns[column.index]
                if not state then
                    state = {
                        left = math.huge,
                        right = -math.huge,
                        width = column.width,
                    }
                    columns[column.index] = state
                    total_columns = total_columns + 1
                end

                state.left = math.min(state.left, window.at.x)
                state.right = math.max(state.right, window.at.x + window.size.x)
            end
        end
    end

    local visible_column
    local visible_overlap = 0
    for _, column in pairs(columns) do
        local overlap = math.max(0, math.min(column.right, work_right) - math.max(column.left, work_left))
        if overlap > visible_overlap then
            visible_column = column
            visible_overlap = overlap
        end
    end

    local work_width = work_right - work_left
    if not visible_column or visible_overlap < work_width * 0.95 then
        return false
    end

    local width = type(visible_column.width) == "number" and visible_column.width or 0
    if total_columns ~= 1 and math.abs(width - 1) > 0.001 then
        return false
    end

    local work_center = (work_left + work_right) / 2
    local column_center = (visible_column.left + visible_column.right) / 2
    return math.abs(column_center - work_center) <= work_width * 0.05
end

function M.evaluate()
    local seen = {}
    for _, workspace in ipairs(hl.get_workspaces()) do
        if scrolling_rules[workspace.name] then
            seen[workspace.name] = true
            set_override(workspace.name, qualifies(workspace))
        end
    end

    for name in pairs(scrolling_rules) do
        if not seen[name] then
            set_override(name, false)
        end
    end
end

create_scrolling_rules()

local evaluation_timer

function M.schedule()
    if not evaluation_timer then
        return
    end

    evaluation_timer:set_timeout(50)
    evaluation_timer:set_enabled(true)
end

for _, event in ipairs({
    "monitor.added",
    "monitor.removed",
    "monitor.layout_changed",
    "window.open",
    "window.close",
    "window.destroy",
    "window.pin",
    "window.fullscreen",
    "window.update_rules",
    "window.move_to_workspace",
    "workspace.active",
    "workspace.special_active",
    "workspace.created",
    "workspace.removed",
    "workspace.move_to_monitor",
}) do
    hl.on(event, M.schedule)
end

local function start_evaluation_timer()
    if evaluation_timer then
        return
    end

    evaluation_timer = hl.timer(function()
        M.evaluate()
        evaluation_timer:set_timeout(250)
    end, { timeout = 50, type = "repeat" })
end

hl.on("hyprland.start", start_evaluation_timer)

if #hl.get_monitors() > 0 then
    start_evaluation_timer()
end

M.evaluate()

return M
