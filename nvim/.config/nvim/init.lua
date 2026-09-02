-- My init.lua file
--
--

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("vim-options")
-- Lockfile lives in the state dir (machine-local), NOT in this stowed config:
-- lazy's install/update passes would otherwise rewrite the public repo's
-- lazy-lock.json on every machine. install.sh copies the repo's canonical
-- lockfile into the state dir; `lazy-lock-sync` copies deliberate updates back.
require("lazy").setup("plugins", {
  lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
})

