#!/usr/bin/env bash
# One-liner bootstrap for fresh machines:
#   curl -fsSL https://raw.githubusercontent.com/timfox456/dotfiles/main/bootstrap.sh | bash -s -- [--server]
# Clones the repo (if missing), updates it, installs tooling, links configs.
set -euo pipefail

REPO_DIR="${DOTFILES_DIR:-$HOME/timfox456/dotfiles}"
REPO_URL="${DOTFILES_URL:-https://github.com/timfox456/dotfiles}"

if [[ ! -d "$REPO_DIR/.git" ]]; then
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
else
  cd "$REPO_DIR"
  git pull --ff-only 2>/dev/null || echo "note: pull skipped (local changes?)"
fi

cd "$REPO_DIR"
./install-deps.sh
./install.sh "$@"   # pass --server for headless machines

echo
echo "bootstrap done. remaining manual steps:"
echo "  - secrets:  cp ~/.config/shell/secrets.local.example ~/.config/shell/secrets.local (chmod 600, edit)"
echo "  - git id:   work machines — cp ~/.config/git/gitconfig.local.example ~/.config/git/gitconfig.local (edit)"
echo "  - gmail:    see README 'Gmail via aerc' (OAuth client + one-time authorize)"
echo "  - tmux:     prefix + I if plugins are missing"
