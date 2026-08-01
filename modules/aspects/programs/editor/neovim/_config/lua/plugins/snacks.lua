return {
    "snacks.nvim",
    keys = {
        { "<leader>/", false },
        { "<leader><space>", false },
        { "<leader>fc", false },
        { "<leader>ff", false },
        { "<leader>fF", false },
        { "<leader>sg", false },
        { "<leader>sG", false },
        { "<leader>sw", false, mode = { "n", "x" } },
        { "<leader>sW", false, mode = { "n", "x" } },
    },
    opts = {
        scroll = { enabled = false },
        image = {},
        picker = {
            sources = {
                explorer = {
                    hidden = true,
                    ignored = false,
                    win = {
                        list = {
                            keys = {
                                ["<leader>/"] = false,
                                ["I"] = "toggle_ignored",
                            },
                        },
                    },
                },
            },
        },
    },
}
