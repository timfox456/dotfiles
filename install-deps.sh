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
  exit 0
fi

TMPDIR_BUILD="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BUILD"' EXIT

# --- neovim: official release tarball ---------------------------------------
if (( NEED_NVIM )); then
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
  log "building tmux ${TMUX_VERSION} -> ${PREFIX}"
  DEPS=(build-essential libevent-dev libncurses-dev bison pkg-config curl)
  MISSING=()
  for dep in "${DEPS[@]}"; do
    dpkg -s "$dep" >/dev/null 2>&1 || MISSING+=("$dep")
  done
  if ((${#MISSING[@]})); then
    log "installing build deps: ${MISSING[*]}"
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -qq
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${MISSING[@]}"
  fi
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

# --- verify -----------------------------------------------------------------
NVIM_NEW="$(current_nvim_version || true)"
TMUX_NEW="$(current_tmux_version || true)"
log "done: nvim=${NVIM_NEW:-missing}, tmux=${TMUX_NEW:-missing}"
if [[ "$PREFIX" == "${HOME}/.local" ]]; then
  warn "make sure ${HOME}/.local/bin is on your PATH"
fi
if pgrep -x tmux >/dev/null 2>&1; then
  warn "a tmux server is already running on the old binary — 'tmux kill-server' when sessions allow"
fi
