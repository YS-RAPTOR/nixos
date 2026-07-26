return {
    "saghen/blink.cmp",
    dependencies = {
        "moyiz/blink-emoji.nvim",
    },
    opts = {
        signature = { enabled = true },
        sources = {
            default = { "lsp", "path", "snippets", "buffer", "emoji" },
            providers = {
                emoji = {
                    module = "blink-emoji",
                    name = "Emoji",
                    score_offset = -1,
                    opts = { insert = true },
                },
            },
        },
        keymap = {
            preset = "default",
            ["<C-e>"] = {
                function(cmp)
                    if cmp.is_visible() then
                        cmp.hide_documentation()
                        cmp.hide()
                    else
                        cmp.show()
                        cmp.show_documentation()
                    end
                end,
            },
            ["<C-a>"] = {
                LazyVim.cmp.map({ "ai_nes" }, "<C-a>"),
            },
            ["<M-a>"] = {
                function()
                    local Nes = require("sidekick.nes")

                    if Nes.have() then
                        Nes.clear()
                    else
                        Nes.update()
                    end
                end,
            },
            ["<C-f>"] = {
                function(cmp)
                    if cmp.snippet_active() then
                        return cmp.accept()
                    else
                        return cmp.select_and_accept()
                    end
                end,
                "snippet_forward",
                "fallback",
            },
            ["<S-Tab>"] = { "select_prev", "fallback" },
            ["<Tab>"] = { "select_next", "fallback" },
            ["<C-u>"] = { "scroll_documentation_up", "fallback" },
            ["<C-d>"] = { "scroll_documentation_down", "fallback" },
        },
    },
}
