return {
  {
    "vinnymeller/swagger-preview.nvim",
    build = "npm install -g swagger-ui-watcher",
    cmd = { "SwaggerPreview", "SwaggerPreviewStop", "SwaggerPreviewToggle" },
    -- gated: don't install/run (or its global npm build) unless npm exists
    cond = function() return vim.fn.executable("npm") == 1 end,
    config = true,
  },
}
