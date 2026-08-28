#!/usr/bin/env bash
# Install modern neovim + tmux on Ubuntu 24.04 (and similar Debian-based systems).
#
# - Checks installed versions and only installs what's outdated/missing.
# - neovim: official GitHub release tarball (no build).
# - tmux:   built from the official GitHub release tarball (needs a few apt packages).
#
# Usage:
#   ./install-deps.sh                # upgrade what's below the minimum versions
#   ./install-deps.sh --check        # only report versions, change nothing
#   ./install-deps.sh --force        # reinstall/upgrade to pinned versions even if sufficient
#   ./install-deps.sh --user         # install to ~/.local instead of /usr/local (no root needed)
#
# Pinned versions (override via env):
#   NVIM_VERSION=0.12.4 ./install-deps.sh
#   TMUX_VERSION=3.7c ./install-deps.sh
set -euo pipefail

NVIM_VERSION="${NVIM_VERSION:-0.12.4}"
TMUX_VERSION="${TMUX_VERSION:-3.7c}"
MIN_NVIM_VERSION="${MIN_NVIM_VERSION:-0.11.0}"   # vim.lsp.config / vim.lsp.enable era
MIN_TMUX_VERSION="${MIN_TMUX_VERSION:-3.4}"      # set-clipboard (OSC 52) needs >= 3.3

# Packages the setup relies on:
#   stow -> install.sh (dotfiles linking; noble ships 2.3.1, fully sufficient)
#   rg -> telescope live_grep          fzf -> tmux-fzf
#   git -> lazy.nvim, tpm              build-essential -> treesitter parser builds
#   node/npm -> mason (pyright, typescript-language-server)
#   python3/pip/venv -> mason (ruff, black, isort, mypy, pylint, debugpy)
#   unzip -> some mason packages
TOOL_DEPS=(stow curl git unzip build-essential ripgrep fzf nodejs npm python3 python3-pip python3-venv)

MODE="install"
PREFIX="/usr/local"
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --force) FORCE=1 ;;
    --user)  PREFIX="${HOME}/.local" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (see --help)"; exit 1 ;;
  esac
done

SUDO=""
if [[ $EUID -ne 0 && $PREFIX == "/usr/local" ]]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else
    echo "ERROR: need root (or sudo) to install into $PREFIX; try --user instead" >&2
    exit 1
  fi
fi

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }

# ver_ge A B -> true if A >= B (handles nvim "0.12.4" and tmux "3.7c" styles).
# Pure bash: BSD sort -V (macOS) is unreliable, so we don't depend on it.
ver_fields() {
  local v="${1#v}"
  v="${v//[!0-9a-z.]/}"
  local letter=""
  [[ "$v" =~ ([a-z]+)$ ]] && { letter="${BASH_REMATCH[1]}"; v="${v%$letter}"; }
  v="${v%.}"
  local -a parts
  IFS='.' read -r -a parts <<< "$v"
  echo "${parts[0]:-0} ${parts[1]:-0} ${parts[2]:-0} ${letter:- }"
}

ver_ge() {
  local -a a b
  read -r -a a <<< "$(ver_fields "$1")"
  read -r -a b <<< "$(ver_fields "$2")"
  local i
  for i in 0 1 2; do
    (( ${a[i]:-0} > ${b[i]:-0} )) && return 0
    (( ${a[i]:-0} < ${b[i]:-0} )) && return 1
  done
  local la="${a[3]:- }" lb="${b[3]:- }"
  [[ "$la" == "$lb" ]] && return 0
  [[ "$la" == " "  ]] && return 1
  [[ "$lb" == " "  ]] && return 0
  [[ "$la" > "$lb" ]] && return 0 || return 1
}

# Remove apt/dpkg-owned copies of an outdated binary so they don't linger
# alongside (or shadow) the one we install. No-op if dpkg is unavailable
# (e.g. macOS) or the binary isn't owned by any package.
remove_apt_package() {
  command -v dpkg >/dev/null 2>&1 || return 0
  local path pkgs
  path="$(command -v "$1" 2>/dev/null)" || return 0
  pkgs="$(dpkg -S "$path" 2>/dev/null | cut -d: -f1 | sort -u)" || return 0
  [[ -z "$pkgs" ]] && return 0
  if [[ -z "$SUDO" && "$PREFIX" != "/usr/local" ]]; then
    warn "apt package(s) providing $path ($pkgs) left installed (no root);"
    warn "make sure $PREFIX/bin precedes /usr/bin in PATH"
    return 0
  fi
  log "removing apt-installed package(s) providing $path: $(echo "$pkgs" | tr '\n' ' ')"
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq $pkgs \
    || warn "apt-get remove failed — our install still wins via PATH (/usr/local/bin precedes /usr/bin)"
}

# Ensure apt packages are installed (no-op on systems without dpkg, e.g. macOS).
ensure_apt_packages() {
  command -v dpkg >/dev/null 2>&1 || return 0
  local missing=() pkg
  for pkg in "$@"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  ((${#missing[@]})) || return 0
  if [[ $EUID -ne 0 && -z "$SUDO" ]]; then
    warn "no root to install: ${missing[*]} — install manually or rerun without --user"
    return 0
  fi
  log "installing apt packages: ${missing[*]}"
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
}

current_nvim_version() {
  command -v nvim >/dev/null 2>&1 || return 1
  nvim --version | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

current_tmux_version() {
  command -v tmux >/dev/null 2>&1 || return 1
  tmux -V | grep -oE '[0-9]+\.[0-9]+[a-z]?' | head -n1
}

NEED_NVIM=0 NEED_TMUX=0
NVIM_CUR="$(current_nvim_version || true)"
TMUX_CUR="$(current_tmux_version || true)"

log "detected: nvim=${NVIM_CUR:-missing}, tmux=${TMUX_CUR:-missing}"
log "targets:  nvim>=${MIN_NVIM_VERSION} (install ${NVIM_VERSION}), tmux>=${MIN_TMUX_VERSION} (install ${TMUX_VERSION})"

if [[ -z "$NVIM_CUR" ]] || ! ver_ge "$NVIM_CUR" "$MIN_NVIM_VERSION"; then
  NEED_NVIM=1
fi
if [[ -z "$TMUX_CUR" ]] || ! ver_ge "$TMUX_CUR" "$MIN_TMUX_VERSION"; then
  NEED_TMUX=1
fi
if (( FORCE )); then NEED_NVIM=1 NEED_TMUX=1; fi

if [[ "$MODE" == "check" ]]; then
  (( NEED_NVIM )) && warn "nvim ${NVIM_CUR:-missing}: BELOW minimum ${MIN_NVIM_VERSION} — run without --check to install ${NVIM_VERSION}" \
                    || log "nvim ${NVIM_CUR}: OK (>= ${MIN_NVIM_VERSION})"
  (( NEED_TMUX )) && warn "tmux ${TMUX_CUR:-missing}: BELOW minimum ${MIN_TMUX_VERSION} — run without --check to install ${TMUX_VERSION}" \
                  || log "tmux ${TMUX_CUR}: OK (>= ${MIN_TMUX_VERSION})"
  if command -v dpkg >/dev/null 2>&1; then
    MISSING_DEPS=()
    for dep in "${TOOL_DEPS[@]}"; do
      dpkg -s "$dep" >/dev/null 2>&1 || MISSING_DEPS+=("$dep")
    done
    if ((${#MISSING_DEPS[@]})); then
      warn "missing tool deps: ${MISSING_DEPS[*]} — will be installed"
    else
      log "tool deps (${TOOL_DEPS[*]}): OK"
    fi
  fi
  exit 0
fi

TMPDIR_BUILD="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BUILD"' EXIT

# --- editor tool dependencies ------------------------------------------------
ensure_apt_packages "${TOOL_DEPS[@]}"

# --- tree-sitter CLI (required by nvim-treesitter main to compile parsers) ---
# Not an apt package on 24.04; install the official release binary (Linux only —
# on macOS use `brew install tree-sitter`).
ensure_tree_sitter_cli() {
  command -v tree-sitter >/dev/null 2>&1 && {
    log "tree-sitter CLI: $(tree-sitter --version | head -n1)"
    return 0
  }
  if [[ "$(uname -s)" != "Linux" ]]; then
    warn "tree-sitter CLI missing — install via 'brew install tree-sitter' (macOS)"
    return 0
  fi
  local arch
  case "$(uname -m)" in
    x86_64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "ERROR: unsupported arch $(uname -m)" >&2; return 1 ;;
  esac
  log "installing tree-sitter CLI -> ${PREFIX}/bin"
  curl -fsSL -o "$TMPDIR_BUILD/tree-sitter.gz" \
    "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-${arch}.gz"
  gunzip -f "$TMPDIR_BUILD/tree-sitter.gz"
  $SUDO install -m 0755 "$TMPDIR_BUILD/tree-sitter" "${PREFIX}/bin/tree-sitter"
  log "tree-sitter CLI: $(tree-sitter --version | head -n1)"
}
ensure_tree_sitter_cli

# --- neovim: official release tarball ---------------------------------------
if (( NEED_NVIM )); then
  command -v nvim >/dev/null 2>&1 && remove_apt_package nvim
  case "$(uname -m)" in
    x86_64)          NVIM_ARCH="x86_64" ;;
    aarch64|arm64)   NVIM_ARCH="aarch64" ;;
    *) echo "ERROR: unsupported arch $(uname -m)" >&2; exit 1 ;;
  esac
  log "installing neovim ${NVIM_VERSION} (${NVIM_ARCH}) -> ${PREFIX}"
  curl -fsSL -o "$TMPDIR_BUILD/nvim.tar.gz" \
    "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-${NVIM_ARCH}.tar.gz"
  $SUDO rm -rf "${PREFIX}/opt/nvim-linux-${NVIM_ARCH}"
  $SUDO mkdir -p "${PREFIX}/opt" "${PREFIX}/bin"
  $SUDO tar -C "${PREFIX}/opt" -xzf "$TMPDIR_BUILD/nvim.tar.gz"
  $SUDO ln -sfn "${PREFIX}/opt/nvim-linux-${NVIM_ARCH}/bin/nvim" "${PREFIX}/bin/nvim"
else
  log "nvim ${NVIM_CUR}: up to date, skipping"
fi

# --- tmux: build from official release tarball ------------------------------
if (( NEED_TMUX )); then
  command -v tmux >/dev/null 2>&1 && remove_apt_package tmux
  log "building tmux ${TMUX_VERSION} -> ${PREFIX}"
  ensure_apt_packages libevent-dev libncurses-dev bison
  curl -fsSL -o "$TMPDIR_BUILD/tmux.tar.gz" \
    "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz"
  tar -C "$TMPDIR_BUILD" -xzf "$TMPDIR_BUILD/tmux.tar.gz"
  (
    cd "$TMPDIR_BUILD/tmux-${TMUX_VERSION}"
    ./configure --prefix="$PREFIX"
    make -j"$(nproc)"
    $SUDO make install
  )
else
  log "tmux ${TMUX_CUR}: up to date, skipping"
fi

# --- tpm: tmux plugin manager (must live at ~/.config/tmux/plugins/tpm) -----
TPM_DIR="$HOME/.config/tmux/plugins/tpm"
LEGACY_TPM_DIR="$HOME/.tmux/plugins/tpm"

if command -v git >/dev/null 2>&1; then
  if [[ -d "$TPM_DIR/.git" ]]; then
    log "updating tpm at $TPM_DIR"
    git -C "$TPM_DIR" pull --ff-only -q || warn "tpm update failed (non-fatal)"
  elif [[ -d "$LEGACY_TPM_DIR/.git" ]]; then
    log "migrating legacy tpm: ~/.tmux/plugins -> ~/.config/tmux/plugins"
    mkdir -p "$HOME/.config/tmux/plugins"
    mv "$HOME/.tmux/plugins/"* "$HOME/.config/tmux/plugins/" || true
    rmdir "$HOME/.tmux/plugins" "$HOME/.tmux" 2>/dev/null || true
    git -C "$TPM_DIR" pull --ff-only -q 2>/dev/null || true
  else
    log "installing tpm -> $TPM_DIR"
    git clone -q https://github.com/tmux-plugins/tpm "$TPM_DIR" || warn "tpm clone failed"
  fi
  # modern tpm ships bin/install_plugins; older versions bin/install_plugins.sh
  TPM_INSTALL=""
  for cand in "$TPM_DIR/bin/install_plugins" "$TPM_DIR/bin/install_plugins.sh"; do
    [[ -x "$cand" ]] && { TPM_INSTALL="$cand"; break; }
  done
  if [[ -n "$TPM_INSTALL" ]]; then
    log "installing tmux plugins (non-interactive)"
    "$TPM_INSTALL" >/dev/null 2>&1 \
      || warn "plugin install failed — run 'prefix + I' inside tmux"
  else
    warn "tpm unavailable — run 'prefix + I' inside tmux to install plugins"
  fi
else
  warn "git not found — skipping tpm setup (clone tpm or run 'prefix + I' later)"
fi

# --- verify -----------------------------------------------------------------
NVIM_NEW="$(current_nvim_version || true)"
TMUX_NEW="$(current_tmux_version || true)"
log "done: nvim=${NVIM_NEW:-missing}, tmux=${TMUX_NEW:-missing}"

report_tool() {
  command -v "$1" >/dev/null 2>&1 || { warn "$1: NOT FOUND"; return; }
  log "$1: $("$1" --version 2>&1 | head -n1)"
}
report_tool python3
report_tool node
report_tool npm
report_tool rg
report_tool fzf
report_tool stow
report_tool git

if [[ "$PREFIX" == "${HOME}/.local" ]]; then
  warn "make sure ${HOME}/.local/bin is on your PATH"
fi
if pgrep -x tmux >/dev/null 2>&1; then
  warn "a tmux server is already running on the old binary — 'tmux kill-server' when sessions allow"
fi
