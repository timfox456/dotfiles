#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Packages mirror the $HOME layout (pkg/.config/...), so everything stows to $HOME.
#
# nvim:  tree-folds into a whole-dir symlink; state lives in ~/.local/share/nvim
# tmux:  pre-created dir -> file-links configs, tpm plugins stay machine-local
# ghostty/opencode: same file-link pattern; opencode keeps node_modules etc.
#        machine-local in ~/.config/opencode
# i3:    Linux desktops only (--server skips it)

mkdir -p "$HOME/.config/tmux" "$HOME/.config/ghostty" "$HOME/.config/opencode" "$HOME/.config/zerostack" "$HOME/.config/git" "$HOME/.config/shell" "$HOME/.config/aerc" "$HOME/.local/bin" "$HOME/.local/share/aerc"

# Stow refuses to clobber real files/dirs — back up anything in the way.
backup_if_real() {
  if [[ -e "$1" && ! -L "$1" ]]; then
    local bak="$1.bak"
    [[ -e "$bak" ]] && bak="$1.bak.$(date +%Y%m%d%H%M%S)"
    mv "$1" "$bak"
    echo "backed up: $1 -> $bak"
  fi
}
backup_if_real "$HOME/.config/nvim"
backup_if_real "$HOME/.config/tmux/tmux.conf"
backup_if_real "$HOME/.config/tmux/common.conf"
backup_if_real "$HOME/.config/ghostty/config"
backup_if_real "$HOME/.config/opencode/opencode.json"
backup_if_real "$HOME/.config/zerostack/config.toml"
backup_if_real "$HOME/.config/git/ignore"
backup_if_real "$HOME/.gitconfig"
backup_if_real "$HOME/.config/aerc/accounts.conf"
backup_if_real "$HOME/.config/i3/config"
backup_if_real "$HOME/.zshrc"

stow --restow -t "$HOME" tmux-common ghostty opencode zerostack git shell bin aerc

if [[ "${1:-}" == "--server" ]]; then
  stow --restow -t "$HOME" nvim tmux-server
  echo "Linked: nvim, tmux-common, tmux-server, ghostty, opencode, git, shell, zerostack, aerc (prefix C-a)"
else
  stow --restow -t "$HOME" nvim tmux
  if [[ "$(uname -s)" == "Linux" ]]; then
    mkdir -p "$HOME/.config/i3"
    stow --restow -t "$HOME" i3
    echo "Linked: nvim, tmux-common, tmux, ghostty, opencode, git, shell, zerostack, aerc, i3 (desktop)"
  else
    echo "Linked: nvim, tmux-common, tmux, ghostty, opencode, git, shell, zerostack, aerc (desktop)"
  fi
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
