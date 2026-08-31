return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter").setup({
      auto_install = true,
    })
    require("nvim-treesitter").install({
      "lua",
      "python",
      "regex",
      "bash",
      "markdown",
      "markdown_inline",
      "sql",
      "vimdoc",
      "javascript",
      "typescript",
      "tsx",
      "json",
      "html",
      "yaml",
    })

    -- highlight/indent modules are gone in the main-branch rewrite:
    -- highlighting is native (vim.treesitter.start) since 0.11, indent via the plugin's indentexpr
    vim.api.nvim_create_autocmd("FileType", {
      callback = function(args)
        pcall(vim.treesitter.start, args.buf)
        vim.bo[args.buf].indentexpr = 'v:lua.require"nvim-treesitter".indentexpr()'
      end,
    })
  end,
}
