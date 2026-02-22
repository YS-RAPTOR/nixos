return {
    "stevearc/conform.nvim",
    opts = {
        formatters_by_ft = {
            javascript = { "prettier" },
            javascriptreact = { "prettier" },
            typescript = { "prettier" },
            typescriptreact = { "prettier" },
        },
        formatters = {
            nixfmt = {
                append_args = { "--indent", "4" },
            },
        },
    },
}
