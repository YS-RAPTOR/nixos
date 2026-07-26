return {
    "snacks.nvim",
    opts = {
        scroll = { enabled = false },
        image = {},
        picker = {
            sources = {
                explorer = {
                    hidden = true,
                    ignored = false,
                    win = {
                        list = {
                            keys = {
                                ["I"] = "toggle_ignored",
                            },
                        },
                    },
                },
            },
        },
    },
}
