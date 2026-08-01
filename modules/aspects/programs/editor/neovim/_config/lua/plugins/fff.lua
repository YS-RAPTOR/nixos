local function state_path(name)
    local state_home = vim.env.XDG_STATE_HOME or vim.fs.joinpath(vim.env.HOME, ".local", "state")
    return vim.fs.joinpath(state_home, "fff", name)
end

local function cwd()
    return vim.uv.cwd() or vim.fn.getcwd()
end

return {
    "dmtrKovalenko/fff.nvim",
    build = "nix run .#release",
    lazy = false,
    opts = {
        lazy_sync = false,
        frecency = {
            enabled = true,
            db_path = vim.env.FFF_FRECENCY_DB or state_path("frecency"),
        },
        history = {
            enabled = true,
            db_path = vim.env.FFF_HISTORY_DB or state_path("history"),
        },
        keymaps = {
            move_up = "<C-k>",
            move_down = "<C-j>",
            cycle_previous_query = "<A-k>",
            cycle_forward_query = "<A-j>",
        },
    },
    keys = {
        {
            "<leader><space>",
            function()
                require("fff").find_files({ cwd = LazyVim.root() })
            end,
            desc = "Find Files (Root Dir)",
        },
        {
            "<leader>ff",
            function()
                require("fff").find_files({ cwd = LazyVim.root() })
            end,
            desc = "Find Files (Root Dir)",
        },
        {
            "<leader>fF",
            function()
                require("fff").find_files({ cwd = cwd() })
            end,
            desc = "Find Files (cwd)",
        },
        {
            "<leader>fc",
            function()
                require("fff").find_files({ cwd = vim.fn.stdpath("config") })
            end,
            desc = "Find Config File",
        },
        {
            "<leader>/",
            function()
                require("fff").live_grep({ cwd = LazyVim.root() })
            end,
            desc = "Grep (Root Dir)",
        },
        {
            "<leader>sg",
            function()
                require("fff").live_grep({ cwd = LazyVim.root() })
            end,
            desc = "Grep (Root Dir)",
        },
        {
            "<leader>sG",
            function()
                require("fff").live_grep({ cwd = cwd() })
            end,
            desc = "Grep (cwd)",
        },
        {
            "<leader>sw",
            function()
                require("fff").live_grep_under_cursor({ cwd = LazyVim.root() })
            end,
            mode = { "n", "x" },
            desc = "Search Word/Selection (Root Dir)",
        },
        {
            "<leader>sW",
            function()
                require("fff").live_grep_under_cursor({ cwd = cwd() })
            end,
            mode = { "n", "x" },
            desc = "Search Word/Selection (cwd)",
        },
    },
}
