-- Keep Cursor in Location same Location
vim.keymap.set("n", "J", "mzJ`z")

-- Keep Cursor Centered when doing Half Page Jumps
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")

-- Yank/Delete to system clipboard
vim.keymap.set("x", "<leader>p", [["_dP]], { desc = "Void Paste" })
vim.keymap.set({ "n", "v" }, "<leader>D", [["_d]], { desc = "Void Delete" })

vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]], { desc = "System Yank" })
vim.keymap.set("n", "<leader>Y", [["+Y]], { desc = "System Yank till End" })

-- Remove Q keybind
vim.keymap.set("n", "Q", "@qj")
vim.keymap.set("v", "Q", ":norm @q<CR>")

-- Replace Instances of Current Word
vim.keymap.set(
    "n",
    "gW",
    [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
    { desc = "Replace Word Under Cursor" }
)

-- Remove LazyTerminal Keymaps
vim.keymap.set("n", "<C-_>", "<nop>")
