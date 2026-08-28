#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# nvim: safe to symlink the whole dir (plugin/state data lives in ~/.local/share/nvim)
stow --restow -t "$HOME/.config" nvim

# tmux: pre-create the target dir so stow file-links configs but leaves
#       machine-local state (tpm plugins in ~/.config/tmux/plugins) alone
mkdir -p "$HOME/.config/tmux"
stow --restow -t "$HOME/.config/tmux" tmux-common

if [[ "${1:-}" == "--server" ]]; then
  stow --restow -t "$HOME/.config/tmux" tmux-server
  echo "Linked: nvim, tmux-common, tmux-server (prefix C-a)"
else
  stow --restow -t "$HOME/.config/tmux" tmux
  echo "Linked: nvim, tmux-common, tmux (desktop)"
fi
