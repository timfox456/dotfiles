return {
  "vim-test/vim-test",
  dependencies = {
    "preservim/vimux",
  },
  config = function()
    vim.keymap.set("n", "<leader>t", ":TestNearest<CR>", {})
    vim.keymap.set("n", "<leader>T", ":TestFile<CR>", {})
    vim.keymap.set("n", "<leader>a", ":TestSuite<CR>", {})
    vim.keymap.set("n", "<leader>l", ":TestLast<CR>", {})
    -- <leader>v, not <leader>g: a bare <leader>g is a prefix of the
    -- <leader>gd/gr (LSP) and <leader>gp/gt (gitsigns) maps, which stalled
    -- all four behind 'timeoutlen'. (<leader>t* is taken by TestNearest.)
    vim.keymap.set("n", "<leader>v", ":TestVisit<CR>", {})
    vim.cmd("let test#strategy = 'vimux'")
  end,
}
