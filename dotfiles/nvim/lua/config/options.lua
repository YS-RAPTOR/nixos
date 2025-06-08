vim.g.maplocalleader = " "

local opt = vim.opt

opt.breakindent = true

-- Set undo settings
opt.swapfile = false
opt.backup = false

if vim.loop.os_uname().sysname == "Linux" then
    opt.undodir = vim.env.HOME .. "/.programs/nvim/undodir"
end

if vim.loop.os_uname().sysname == "Windows_NT" then
    opt.undodir = "E:/nvim/undodir"
end

-- Increase Scroll Off
opt.scrolloff = 8

-- Turn on Incremental Search
opt.hlsearch = false
opt.incsearch = true

-- Mini Pairs Disabled
vim.g.minipairs_disable = true

-- Misc
opt.pumblend = 0
opt.colorcolumn = ""
opt.list = false

opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4

-- spelling
opt.spell = true
opt.spelllang = "en_us"
