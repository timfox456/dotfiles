# macOS tooling for the dotfiles setup — installed via `brew bundle`.
# Linux equivalents live in TOOL_DEPS in install-deps.sh.

# Core
brew "stow"
brew "git"
brew "gh"
brew "ripgrep"
brew "fzf"
brew "mosh"
brew "fd"
brew "tree"
brew "lazygit"
brew "pass"
brew "pandoc"
brew "poppler"

# Editors / agents
brew "neovim"
brew "tmux"
brew "tree-sitter-cli"
brew "aerc"

# Forge & cloud CLIs (Linux: apt/installer — see install-deps.sh)
brew "glab"
brew "awscli"
brew "azure-cli"
# renamed from google-cloud-sdk; the old cask name redirects but warns
cask "gcloud-cli"

# Apps & corporate tooling (macOS only — this Brewfile never runs on Linux)
tap "databricks/tap"
brew "databricks/tap/databricks"
cask "google-chrome"
cask "visual-studio-code"

# Dev tooling
brew "shellcheck"
brew "actionlint"
brew "lua"
brew "ruby"

# System monitoring / info
brew "btop"
brew "fastfetch"
brew "macmon"

# Apps
cask "ghostty"
# Nerd Fonts (nvim icons). ghostty's config uses "JetBrainsMono Nerd Font Mono".
cask "font-hack-nerd-font"
cask "font-jetbrains-mono-nerd-font"
cask "obsidian"
cask "libreoffice"
# ChatGPT is deliberately NOT here — many corporate Macs forbid it. It's a
# manual step on personal machines (README → Manual steps).
# Caps Lock = Esc (tap) / Control (hold) — config in karabiner/. First launch
# needs manual approval: System Settings → Privacy & Security (driver
# extension) and Input Monitoring for karabiner_grabber.
cask "karabiner-elements"
