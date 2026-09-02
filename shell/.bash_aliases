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

# nvm (node version manager) — loaded only on machines where install-deps.sh
# put it (~/.nvm exists). Lazy-free but costs ~50ms per shell; remove here
# and lazy-load via an alias if shell startup ever feels slow.
if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
   # shellcheck source=/dev/null
   . "$HOME/.nvm/nvm.sh"
fi

# Per-machine secrets (API keys etc.) — copied from secrets.local.example,
# never synced, never committed. zerostack reads OPENROUTER_API_KEY from here.
# NOTE: must be a full if-block (not `[[ ]] &&`), so a missing file can never
# make sourcing this file fail.
if [[ -f "$HOME/.config/shell/secrets.local" ]]; then
   # shellcheck source=/dev/null
   source "$HOME/.config/shell/secrets.local"
fi
