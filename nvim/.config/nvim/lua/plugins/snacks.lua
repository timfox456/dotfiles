return {
  {
    "folke/snacks.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      dashboard = { enabled = true },
      notifier = { enabled = true },
      lazygit = { enabled = true },
      terminal = { enabled = true },
      indent = { enabled = true },
      bigfile = { enabled = true },
      quickfile = { enabled = true },
    },
    keys = {
      { "<C-/>", function() require("snacks").terminal() end, mode = { "n", "t" }, desc = "Terminal" },
      { "<leader>ug", function() require("snacks").lazygit() end, desc = "Lazygit" },
    },
  },
}
