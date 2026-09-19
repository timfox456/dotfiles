#!/usr/bin/env bash
# One-liner bootstrap for fresh machines:
#   curl -fsSL https://raw.githubusercontent.com/timfox456/dotfiles/main/bootstrap.sh | bash -s -- [--server]
# Clones the repo (if missing), updates it, installs tooling, links configs.
set -euo pipefail

REPO_DIR="${DOTFILES_DIR:-$HOME/timfox456/dotfiles}"
REPO_URL="${DOTFILES_URL:-https://github.com/timfox456/dotfiles}"

# Fresh Macs may have neither git nor Homebrew — the Homebrew installer
# also pulls the Xcode Command Line Tools (which provide git), so it has
# to happen BEFORE the clone. Idempotent; skipped on Linux (apt git in
# install-deps.sh) and wherever git already exists.
if [[ "$(uname -s)" == "Darwin" ]] && ! command -v git >/dev/null 2>&1; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "==> bootstrapping Homebrew (this also installs the Xcode Command Line Tools)"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || { echo "ERROR: Homebrew install failed — install it from https://brew.sh and rerun" >&2; exit 1; }
  fi
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
fi

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
echo "  - ssh keys: see README 'SSH keys — GitHub / GitLab' (generate, publish, ~/.ssh/config)"
echo "  - gmail:    see README 'Gmail via aerc' (OAuth client + one-time authorize)"
echo "  - tmux:     prefix + I if plugins are missing"
