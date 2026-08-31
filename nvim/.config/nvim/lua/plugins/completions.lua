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
    cmd = "NeoCodeium",
    keys = {
      { "<leader>ua", "<cmd>NeoCodeium toggle<cr>", desc = "Toggle Codeium" },
    },
    opts = {},
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
