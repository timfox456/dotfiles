return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  config = function()
    local config = require("nvim-treesitter.configs")
    config.setup({
      auto_install = true,
      ensure_installed = { 'lua', 'python', 'regex', 'bash', 'markdown', 'markdown_inline', 'sql', 'vimdoc', 'javascript', 'typescript', 'tsx', 'json', 'html', 'yaml' },
      highlight = {enable = true},
      indent = {enable = true},
    })
  end
}
