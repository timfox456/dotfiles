vim.cmd("set expandtab")
vim.cmd("set tabstop=2")
vim.cmd("set softtabstop=2")
vim.cmd("set shiftwidth=2")
vim.g.mapleader = " "

vim.opt.swapfile = false
vim.opt.undofile = true
vim.opt.undodir = vim.fn.stdpath("state") .. "/undo"
vim.fn.mkdir(vim.fn.stdpath("state") .. "/undo", "p")

vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = { border = "rounded", source = "if_many" },
})

-- NOTE: <C-hjkl> pane navigation lives in plugins/nvim-tmux-navigation.lua
-- (it seamlessly crosses into tmux panes). Plain :wincmd maps here would be
-- silently overwritten by it at plugin-config time.

vim.keymap.set("n", "<leader>h", ":nohlsearch<CR>")
vim.opt.number = true
vim.opt.relativenumber = true -- relative line numbers (window-global default)

-- yank to OS clipboard
vim.keymap.set({ "n", "v" }, "<leader>y", '"+y')
vim.keymap.set({ "n", "v" }, "<leader>Y", '"+Y')
vim.keymap.set({ "n", "v" }, "<leader>yy", '"+yy')

vim.keymap.set({ "n", "v" }, "<leader>p", '"+p')
vim.keymap.set({ "n", "v" }, "<leader>P", '"+P')
vim.keymap.set("i", "jj", "<ESC>", { silent = true })
