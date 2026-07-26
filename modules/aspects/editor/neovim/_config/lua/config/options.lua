local opt = vim.opt

-- Undo Settings
opt.swapfile = false
opt.backup = false
local undo_dir = vim.fn.stdpath("state") .. "/undo"
vim.fn.mkdir(undo_dir, "p")
opt.undodir = undo_dir

-- Increase Scroll Off
opt.scrolloff = 8

-- Mini Pairs Disabled
vim.g.minipairs_disable = true

-- Tab Options
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4

-- spelling
opt.spell = true
opt.spelllang = "en_us"
