return {
  'lervag/vimtex',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  init = function()
    if vim.loop.os_uname().sysname == "Darwin" then
      vim.g.vimtex_view_method = "skim"
    else --Linux
      vim.g.vimtex_view_method = "zathura"
    end
  end
}
