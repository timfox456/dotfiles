-- Low-memory profile: computed once at spec-load, shared by all config blocks
local is_tiny = require("lowmem").tiny()

return {
  {
    "williamboman/mason.nvim",
    lazy = false,
    config = function()
      require("mason").setup()
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    lazy = false,
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      -- NOTE: ts_ls is NOT here — typescript-language-server was removed from the
      -- mason registry; it's installed globally via npm in install-deps.sh instead.
      -- automatic_enable: mason-lspconfig auto-enables all INSTALLED servers —
      -- restrict it on tiny instances so pyright (installed on other machines)
      -- never attaches.
      require("mason-lspconfig").setup({
        ensure_installed = is_tiny and { "lua_ls", "ruff" } or { "lua_ls", "pyright", "ruff" },
        automatic_enable = is_tiny and { "lua_ls", "ruff" } or true,
      })
    end,
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    lazy = false,
    config = function()
      -- ruff (lsp) covers black/isort/flake8; conform + nvim-lint use the rest
      require("mason-tool-installer").setup({
        -- ruff (lsp) covers black/isort/flake8; conform + nvim-lint use the rest.
        -- tiny instances: stylua only — skip the node/python tool installs.
        ensure_installed = is_tiny and { "stylua" } or {
          "stylua",
          "prettierd",
          "eslint_d",
          "rubocop",
          "debugpy",
          "mypy",
          "pylint",
        },
      })
    end,
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

      -- pyright/ts_ls are node processes (100-500MB on real projects): only
      -- enable on machines that can afford them. ruff (Rust) is cheap enough
      -- for tiny instances and covers python diagnostics/formatting.
      vim.lsp.enable(is_tiny and { "lua_ls", "ruff" } or { "lua_ls", "ts_ls", "pyright", "ruff" })

      if is_tiny then
        vim.schedule(function()
          vim.notify("nvim: low-memory profile active (pyright/ts_ls off)", vim.log.levels.INFO)
        end)
      end

      vim.keymap.set("n", "K", vim.lsp.buf.hover, {})
      vim.keymap.set("n", "<leader>gd", vim.lsp.buf.definition, {})
      vim.keymap.set("n", "<leader>gr", vim.lsp.buf.references, {})
      vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, {})
    end,
  },
}
