vim.filetype.add({
    pattern = {
        [".*%.md%.hbs"] = "markdown.handlebars",
    },
})

return {
    {
        "nvim-treesitter/nvim-treesitter",
        opts = function()
            vim.treesitter.language.register("markdown", "markdown.handlebars")
        end,
    },
    {
        "nvim-mini/mini.icons",
        opts = {
            extension = {
                ["md.hbs"] = { glyph = "󰌞", hl = "MiniIconsGreen" },
            },
            filetype = {
                ["markdown.handlebars"] = { glyph = "󰌞", hl = "MiniIconsGreen" },
            },
        },
    },
}
