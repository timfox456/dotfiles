#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Packages mirror the $HOME layout (pkg/.config/...), so everything stows to $HOME.
#
# nvim: tree-folds into a whole-dir symlink (~/.config/nvim -> repo); safe because
#       nvim state lives in ~/.local/share/nvim, not in the config dir.
# tmux: pre-create the target dir so stow file-links the configs but leaves
#       machine-local state (tpm plugins in ~/.config/tmux/plugins) alone.
mkdir -p "$HOME/.config/tmux"
stow --restow -t "$HOME" tmux-common

if [[ "${1:-}" == "--server" ]]; then
  stow --restow -t "$HOME" nvim tmux-server
  echo "Linked: nvim, tmux-common, tmux-server (prefix C-a)"
else
  stow --restow -t "$HOME" nvim tmux
  echo "Linked: nvim, tmux-common, tmux (desktop)"
fi
