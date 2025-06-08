return {
    "neovim/nvim-lspconfig",
    opts = {
        servers = {
            zls = {
                settings = {
                    enable_build_on_save = true,
                    build_on_save_step = "check",
                },
            },
        },
    },
}
