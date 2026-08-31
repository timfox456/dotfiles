return {
  {
    "saghen/blink.cmp",
    lazy = false,
    version = "1.*",
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      keymap = { preset = "enter" },
      appearance = { nerd_font_variant = "mono" },
      completion = { documentation = { auto_show = true } },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
      signature = { enabled = true },
    },
  },
  {
    -- Codeium/Windsurf backend via neocodeium (ghost-text style, engine-independent).
    -- NOTE: Exafunction's windsurf.nvim crashes without nvim-cmp present, so we
    -- use neocodeium instead of a blink source integration.
    "monkoose/neocodeium",
    event = "InsertEnter",
    cmd = { "NeoCodeium", "CodeiumAuth", "CodeiumToggle" },
    keys = {
      { "<leader>ua", "<cmd>NeoCodeium toggle<cr>", desc = "Toggle Codeium" },
    },
    opts = {},
    config = function(_, opts)
      require("neocodeium").setup(opts)
      -- forgiving aliases (neocodeium's own command is case-sensitive "NeoCodeium")
      vim.api.nvim_create_user_command("CodeiumAuth", function()
        require("neocodeium.commands").auth()
      end, { desc = "Authenticate Codeium" })
      vim.api.nvim_create_user_command("CodeiumToggle", function()
        require("neocodeium.commands").toggle()
      end, { desc = "Toggle Codeium" })
    end,
  },
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = {
        { path = "${3rd}/luv/library", words = { "vim%.uv" } },
      },
    },
  },
}
