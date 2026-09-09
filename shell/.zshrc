# shellcheck shell=zsh
# zsh config — macOS + anywhere else zsh is used (Linux servers run bash:
# see shell/.bash_aliases). Secrets live in ~/.config/shell/secrets.local.

# typeset -U makes the path array deduplicate itself, no matter how many
# times different blocks below prepend the same directory.
typeset -U path PATH
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

# vi mode + search binds
bindkey -v
bindkey '^R' history-incremental-search-backward
bindkey -M vicmd '^R' history-incremental-search-backward

# === Oh My Zsh ==============================================================
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source "$ZSH/oh-my-zsh.sh"

# === Editor =================================================================
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi
alias vi="nvim"

export ES_HOME="$HOME/timfox456"

# === Version managers =======================================================
# nvm: prefer the install-deps-managed ~/.nvm, fall back to Homebrew's.
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  . "$NVM_DIR/nvm.sh"
  [[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"
elif command -v brew >/dev/null 2>&1; then
  . "$(brew --prefix nvm)"/nvm.sh
fi

# pyenv
if command -v pyenv >/dev/null 2>&1; then
  export PYENV_ROOT="$HOME/.pyenv"
  case ":$PATH:" in
    *":$PYENV_ROOT/bin:"*) ;;
    *) export PATH="$PYENV_ROOT/bin:$PATH" ;;
  esac
  eval "$(pyenv init -)"
  # pyenv-virtualenv is an optional plugin — tolerate machines without it
  eval "$(pyenv virtualenv-init - 2>/dev/null || true)"
fi

# rbenv
command -v rbenv >/dev/null 2>&1 && eval "$(rbenv init - zsh)"

# uv (installer writes this env file)
[[ -s "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

# === Machine-local tools (guarded — no-op where not installed) ==============

# bun
if [[ -d "$HOME/.bun" ]]; then
  export BUN_INSTALL="$HOME/.bun"
  case ":$PATH:" in
    *":$BUN_INSTALL/bin:"*) ;;
    *) export PATH="$BUN_INSTALL/bin:$PATH" ;;
  esac
  [[ -s "$BUN_INSTALL/_bun" ]] && source "$BUN_INSTALL/_bun"
fi

# opencode
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"

# pi coding agent — settings.json is stowed from the repo (pi package);
# mutable state (auth.json, packages, tool bins) stays in the agent dir and
# sessions/index stay in the state/cache dirs — none of it lands in git.
export PI_CODING_AGENT_DIR="$HOME/.config/pi/agent"
export PI_SESSIONS_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pi/sessions"
export PI_EXTENSION_INDEX_PATH="${XDG_CACHE_HOME:-$HOME/.cache}/pi/extension-index"

# === pi agents (two builds share the `pi` name) ==============================
#   pir — pi_agent_rust, always.
#   pi  — TypeScript pi (@earendil-works/pi-coding-agent), the default; on
#         low-tier servers (pi-rust only) it falls back to pi-rust.
# Both honor PI_CODING_AGENT_DIR, so each build gets its own agent dir;
# settings.json for each is stowed from the repo (pi / pi-rust packages).
# auth.json, sessions, packages and tool bins stay per-machine — never in git.
pir() {
  PI_CODING_AGENT_DIR="$HOME/.config/pi-rust/agent" \
    PI_SESSIONS_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pi-rust/sessions" \
    PI_EXTENSION_INDEX_PATH="${XDG_CACHE_HOME:-$HOME/.cache}/pi-rust/extension-index" \
    command pi-rust "$@"
}
pi() {
  # whence -p (not command -v): must not match the pi() function itself
  if whence -p pi >/dev/null 2>&1; then
    PI_CODING_AGENT_DIR="$HOME/.config/pi/agent" command pi "$@"
  else
    pir "$@"
  fi
}

# OpenJDK 17 via Homebrew (macOS)
if [[ "$(uname -s)" == Darwin && -d "/opt/homebrew/opt/openjdk@17" ]]; then
  export JAVA_HOME="/opt/homebrew/opt/openjdk@17"
  export CPPFLAGS="-I$JAVA_HOME/include"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

# === Secrets (always last) ==================================================
# API keys etc. — copied from shell/.config/shell/secrets.local.example.
# Per machine, mode 600, never synced or committed.
if [[ -f "$HOME/.config/shell/secrets.local" ]]; then
   # shellcheck shell=sh
   source "$HOME/.config/shell/secrets.local"
fi

# === Per-machine shell tweaks ===============================================
# Non-secret customizations that should NOT be synced (e.g. an rbenv init
# for bash-flavored use on one machine). Create the file if you need it.
if [[ -f "$HOME/.config/shell/zshrc.local" ]]; then
   # shellcheck source=/dev/null
   source "$HOME/.config/shell/zshrc.local"
fi
