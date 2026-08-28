return {
  {
    "williamboman/mason.nvim",
    lazy = false,
    config = function()
      require("mason").setup()
    end
  },
  {
    "williamboman/mason-lspconfig.nvim",
    lazy = false,
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      -- NOTE: ts_ls is NOT here — typescript-language-server was removed from the
      -- mason registry; it's installed globally via npm in install-deps.sh instead.
      require("mason-lspconfig").setup({
        ensure_installed = { "lua_ls", "pyright", "ruff" }
      })
    end
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    lazy = false,
    config = function()
      -- ruff (lsp) covers black/isort/flake8; conform + nvim-lint use the rest
      require("mason-tool-installer").setup({
        ensure_installed = {
          'stylua',
          'prettierd',
          'eslint_d',
          'rubocop',
          'debugpy',
          'mypy',
          'pylint',
        },
      })
    end
  },
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    dependencies = { "saghen/blink.cmp" },
    config = function()
      local capabilities = require("blink.cmp").get_lsp_capabilities()

      -- Native 0.11+ LSP API (require('lspconfig') framework is deprecated)
      vim.lsp.config("*", { capabilities = capabilities })

      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            runtime = { version = "LuaJIT" },
            diagnostics = { globals = { "vim" } },
            workspace = { checkThirdParty = false },
          },
        },
      })

      -- typescript-language-server (v5+) no longer falls back to the global
      -- typescript package — point tsserver.path at npm's global install.
      vim.lsp.config("ts_ls", {
        init_options = {
          tsserver = {
            path = (function()
              local npm_root = vim.fn.trim(vim.fn.system("npm root -g 2>/dev/null"))
              if vim.v.shell_error == 0 and npm_root ~= "" then
                local p = npm_root .. "/typescript/lib/tsserver.js"
                if vim.uv.fs_stat(p) then
                  return p
                end
              end
              return nil
            end)(),
          },
        },
      })

      vim.lsp.enable({ "lua_ls", "ts_ls", "pyright", "ruff" })

      vim.keymap.set('n', 'K', vim.lsp.buf.hover, {})
      vim.keymap.set('n', '<leader>gd', vim.lsp.buf.definition, {})
      vim.keymap.set('n', '<leader>gr', vim.lsp.buf.references, {})
      vim.keymap.set({'n', 'v'}, '<leader>ca', vim.lsp.buf.code_action, {})
    end
  }
}
