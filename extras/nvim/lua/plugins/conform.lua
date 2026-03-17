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
                append_args = function(_, ctx)
                    local indent = vim.bo[ctx.buf].shiftwidth
                    if indent == 0 then
                        indent = vim.bo[ctx.buf].tabstop
                    end
                    return { "--indent", tostring(indent) }
                end,
            },
        },
    },
}
