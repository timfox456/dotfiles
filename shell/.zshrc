# shellcheck shell=zsh
# zsh config — macOS + anywhere else zsh is used (Linux servers run bash:
# see shell/.bash_aliases). Secrets live in ~/.config/shell/secrets.local.

# typeset -U makes the path array deduplicate itself, no matter how many
# times different blocks below prepend the same directory.
typeset -U path PATH
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

# Homebrew — eval shellenv when installed (Apple Silicon first, Intel fallback)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ "$(uname -m)" == "x86_64" && -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# vi mode + search binds
bindkey -v
bindkey '^R' history-incremental-search-backward
bindkey -M vicmd '^R' history-incremental-search-backward

# === Oh My Zsh ==============================================================
export ZSH="$HOME/.oh-my-zsh"
if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  ZSH_THEME="robbyrussell"
  plugins=(git)
  source "$ZSH/oh-my-zsh.sh"
else
  # No omz (Linux boxes, or a Mac before install-deps.sh ran): keep a usable
  # prompt instead of erroring out on a missing file.
  autoload -Uz vcs_info promptinit && promptinit
  zstyle ':vcs_info:git:*' formats ' (%b)'
  precmd_vcs_info() { vcs_info }
  precmd_functions+=(precmd_vcs_info)
  setopt prompt_subst
  PROMPT='%F{green}%n@%m%f:%F{blue}%~%f%F{yellow}${vcs_info_msg_0_}%f$ '
fi

# === Editor =================================================================
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi
alias vi="nvim"

export ES_HOME="$HOME/timfox456"

# === Version managers =======================================================
# mise is the only runtime version manager (node; install-deps.sh pins it to
# ~/.local/bin). Python stays with uv. nvm/pyenv/rbenv are retired.
if [[ -x "$HOME/.local/bin/mise" ]]; then
  eval "$("$HOME/.local/bin/mise" activate zsh)"
elif command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

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

# opencode (official installer's default bin dir; `typeset -U path` above
# keeps this idempotent)
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"

# pi coding agent — nothing here is stowed: settings.json, auth.json,
# packages and tool bins stay in the agent dir and sessions/index in the
# state/cache dirs. None of it lands in git.
export PI_CODING_AGENT_DIR="$HOME/.config/pi/agent"
export PI_SESSIONS_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/pi/sessions"
export PI_EXTENSION_INDEX_PATH="${XDG_CACHE_HOME:-$HOME/.cache}/pi/extension-index"

# === pi agents (two builds share the `pi` name) ==============================
#   pir — pi_agent_rust, always.
#   pi  — TypeScript pi (@earendil-works/pi-coding-agent), the default; on
#         low-tier servers (pi-rust only) it falls back to pi-rust.
# Both honor PI_CODING_AGENT_DIR, so each build gets its own agent dir.
# Nothing in those dirs is stowed: settings.json, auth.json, sessions,
# packages and tool bins are all per-machine state — never in git.
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

# === macOS helpers ==========================================================
if [[ "$(uname -s)" == Darwin ]]; then
  # cd to the folder of the front-most Finder window
  cdf() { cd "$(osascript -e 'tell app "Finder" to POSIX path of (insertion location as alias)')" || return; }
  # Bundle ID of an app (for Karabiner/duti rules), copied to the clipboard
  bundleid() {
    local id
    id="$(osascript -e "id of app \"$1\"" 2>/dev/null)" || { echo "no app named '$1'" >&2; return 1; }
    printf '%s' "$id" | pbcopy
    echo "$id (copied)"
  }
  alias cpwd="pwd | tr -d '\n' | pbcopy"
  alias cleanupds="find . -type f -name '.DS_Store' -ls -delete"
  # Rebuild LaunchServices — fixes duplicate entries in "Open With"
  alias lscleanup="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user && killall Finder"
  alias afk="open -a ScreenSaverEngine"
  alias cpu="sysctl -n machdep.cpu.brand_string"
  alias ram="top -l 1 -s 0 | grep PhysMem"
fi

# === Secrets (always last) ==================================================
# API keys etc. — copied from shell/.config/shell/secrets.local.example.
# Per machine, mode 600, never synced or committed.
if [[ -f "$HOME/.config/shell/secrets.local" ]]; then
   # shellcheck shell=sh
   source "$HOME/.config/shell/secrets.local"
fi

# === Per-machine shell tweaks ===============================================
# Non-secret customizations that should NOT be synced (e.g. a corporate
# proxy) — copied from shell/.config/shell/zshrc.local.example.
if [[ -f "$HOME/.config/shell/zshrc.local" ]]; then
   # shellcheck source=/dev/null
   source "$HOME/.config/shell/zshrc.local"
fi
