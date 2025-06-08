return {
    "folke/tokyonight.nvim",
    opts = {
        style = "night",
        transparent = true,
        styles = {
            sidebars = "transparent",
            -- floats = "transparent",
        },
        on_colors = function(colors)
            colors.bg_statusline = "None"
        end,
    },
}
