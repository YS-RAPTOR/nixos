return {
    {
        "giuxtaposition/blink-cmp-copilot",
        enabled = false,
    },
    {
        "saghen/blink.cmp",
        dependencies = {
            "fang2hou/blink-copilot",
            "moyiz/blink-emoji.nvim",
            "Kaiser-Yang/blink-cmp-dictionary",
        },
        opts = {
            signature = { enabled = true },
            sources = {
                default = { "lsp", "path", "snippets", "buffer", "dictionary", "emoji" },
                providers = {
                    copilot = {
                        module = "blink-copilot",
                    },
                    emoji = {
                        module = "blink-emoji",
                        name = "Emoji",
                        score_offset = -1,
                        opts = { insert = true },
                    },
                    dictionary = {
                        module = "blink-cmp-dictionary",
                        name = "Dict",
                        score_offset = -1000,
                        min_keyword_length = 3,
                        opts = {
                            dictionary_files = {
                                vim.fn.expand("~/.config/nvim/spell/en.utf-8.add"),
                            },
                            dictionary_directories = {
                                vim.fn.expand("~/.config/dictionary"),
                            },
                        },
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
                ["<C-f>"] = {
                    function(cmp)
                        if vim.b[vim.api.nvim_get_current_buf()].nes_state then
                            cmp.hide()
                            return require("copilot-lsp.nes").apply_pending_nes()
                        end
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
    },
}
