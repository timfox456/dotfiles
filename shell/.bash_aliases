# shellcheck shell=bash
# Personal aliases — synced via dotfiles (stow: shell package)
# Sourced automatically by Ubuntu's default ~/.bashrc

alias l='ls -CF'
alias ll='ls -alF'
alias la='ls -A'

# Add an "alert" alias for long running commands. Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# tmux sessionizer: fzf project switcher (same as M-s inside tmux)
alias s='$HOME/.local/bin/tmux-sessionizer'

# uv + user-local binaries on PATH (idempotent)
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
[[ -s "$HOME/.local/bin/env" ]] && { # shellcheck shell=sh disable=SC1091
   . "$HOME/.local/bin/env"; }

# mise (runtime versions: node) — installed by install-deps.sh into
# ~/.local/bin, which is on PATH from above.
if command -v mise >/dev/null 2>&1; then
   eval "$(mise activate bash)"
fi

# Per-machine secrets (API keys etc.) — copied from secrets.local.example,
# never synced, never committed. zerostack reads OPENROUTER_API_KEY from here.
# NOTE: must be a full if-block (not `[[ ]] &&`), so a missing file can never
# make sourcing this file fail.
if [[ -f "$HOME/.config/shell/secrets.local" ]]; then
   # shellcheck source=/dev/null
   source "$HOME/.config/shell/secrets.local"
fi
