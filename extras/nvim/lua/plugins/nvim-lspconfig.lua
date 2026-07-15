return {
    "neovim/nvim-lspconfig",
    opts = {
        servers = {
            tsgo = {
                cmd = function(dispatchers, config)
                    local cmd = "tsgo"

                    if config.root_dir then
                        local local_tsc = vim.fs.joinpath(config.root_dir, "node_modules", ".bin", "tsc")
                        if vim.fn.executable(local_tsc) == 1 then
                            cmd = local_tsc
                        end
                    end

                    return vim.lsp.rpc.start({ cmd, "--lsp", "--stdio" }, dispatchers)
                end,
            },
            zls = {
                settings = {
                    enable_build_on_save = true,
                    build_on_save_step = "check",
                },
            },
            slangd = {
                cmd = {
                    "slangd",
                    "--stdio",
                },
            },
        },
    },
}
