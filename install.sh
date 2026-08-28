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

# Finish tpm setup now that the config (with the @plugin list) is linked.
TPM_INSTALL=""
for cand in "$HOME/.config/tmux/plugins/tpm/bin/install_plugins" \
            "$HOME/.config/tmux/plugins/tpm/bin/install_plugins.sh"; do
  [[ -x "$cand" ]] && { TPM_INSTALL="$cand"; break; }
done
if [[ -n "$TPM_INSTALL" ]]; then
  "$TPM_INSTALL" >/dev/null 2>&1 || echo "note: tpm plugin install failed — press prefix + I inside tmux"
else
  echo "note: tpm not found — run ./install-deps.sh, then prefix + I inside tmux"
fi
