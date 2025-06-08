--- TODO: Undo tree/telescope undo alternative
return {
    "debugloop/telescope-undo.nvim",
    dependencies = {
        {
            "nvim-telescope/telescope.nvim",
            dependencies = { "nvim-lua/plenary.nvim" },
        },
    },
    keys = {
        {
            "<leader>t",
            "<cmd>Telescope undo<cr>",
            desc = "Undo History",
        },
    },
    opts = {
        extensions = {
            undo = {},
        },
    },
    config = function(_, opts)
        require("telescope").setup(opts)
        require("telescope").load_extension("undo")
    end,
}
