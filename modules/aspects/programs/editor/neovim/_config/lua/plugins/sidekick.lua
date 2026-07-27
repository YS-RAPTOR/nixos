return {
    "folke/sidekick.nvim",
    keys = {
        {
            "<tab>",
            "<tab>",
            mode = { "n" },
            expr = true,
        },
        {
            "<C-a>",
            LazyVim.cmp.map({ "ai_nes" }, "<C-a>"),
            mode = { "n" },
            expr = true,
        },
        {
            "<M-a>",
            function()
                local Nes = require("sidekick.nes")

                if Nes.have() then
                    Nes.clear()
                else
                    Nes.update()
                end
            end,
            mode = { "n" },
            expr = true,
        },
    },
}
