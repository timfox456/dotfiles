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
  eval "$(pyenv virtualenv-init -)"
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

# Antigravity (per-machine app)
[[ -d "$HOME/.antigravity/antigravity/bin" ]] && \
  export PATH="$HOME/.antigravity/antigravity/bin:$PATH"

# opencode
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"

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
