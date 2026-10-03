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
#   ./install-deps.sh --docker       # also install container tier (macOS: colima)
#   ./install-deps.sh --low          # low tier: skip TypeScript pi (node >= 22.19)
#   ./install-deps.sh --high         # force high tier (default on desktops and >= 2GB servers)
#
# Pinned versions (override via env):
#   NVIM_VERSION=0.12.4 ./install-deps.sh
#   TMUX_VERSION=3.7c ./install-deps.sh
#
# keyd (Mac-style Super+C/V on Linux desktops) is installed only on Linux with
# a graphical session (DISPLAY/WAYLAND_DISPLAY). KEYD=1 forces it (e.g. over
# ssh), KEYD=0 skips it.
set -euo pipefail

# Brewfile, Brewfile.docker and terminfo/ are read by relative path — this
# script must run from the repo root no matter where it was invoked from.
cd "$(dirname "$0")"

NVIM_VERSION="${NVIM_VERSION:-0.12.4}"
TMUX_VERSION="${TMUX_VERSION:-3.7c}"
NVM_VERSION="${NVM_VERSION:-v0.40.7}"
UV_VERSION="${UV_VERSION:-0.12.7}"
KEYD_VERSION="${KEYD_VERSION:-2.6.0}"
KEYD="${KEYD:-auto}"
GHOSTTY_VERSION="${GHOSTTY_VERSION:-1.3.1}"
MIN_TS_CLI_VERSION="${MIN_TS_CLI_VERSION:-0.24.0}"
MIN_NVIM_VERSION="${MIN_NVIM_VERSION:-0.11.0}"   # vim.lsp.config / vim.lsp.enable era
MIN_TMUX_VERSION="${MIN_TMUX_VERSION:-3.4}"      # set-clipboard (OSC 52) needs >= 3.3

# --- third-party git dependency pins -----------------------------------------
# tpm, oh-my-zsh and the tmux plugins were the only deps with NO pinning at
# all: cloned at HEAD and `git pull`ed, so two machines set up a month apart
# got different code. They are pinned by COMMIT, not tag: every one of these
# projects stopped tagging years ago (tpm's newest tag is 3 years behind its
# HEAD, tmux-sensible's is from 2015), so a tag pin would be a silent
# multi-year downgrade.
#
# To bump one deliberately: update the SHA here, rerun this script, smoke-test,
# then commit. `TPM_REF=<sha> ./install-deps.sh` overrides for a one-off test.
TPM_REF="${TPM_REF:-e261deb1b47614eed3400089ce7197dc68acc4eb}"          # 2026-05-17
OMZ_REF="${OMZ_REF:-74965c96098134b192f00084f966b4b02438a739}"          # 2026-09-22
# "<plugin dir name> <commit>" — dirs are created by tpm under $TPM_DIR
TMUX_PLUGIN_PINS=(
  "tmux-sensible      25cb91f42d020f675bb0a2ce3fbd3a5d96119efa"
  "tmux-fzf           e91c1ae55389f2b34480ea23df77682bdd51d735"
  "vim-tmux-navigator 412c474e97468e7934b9c217064025ea7a69e05e"
  "catppuccin-tmux    b4e0715356f820fc72ea8e8baf34f0f60e891718"
  "tmux-resurrect     cff343cf9e81983d3da0c8562b01616f12e8d548"
  "tmux-continuum     0698e8f4b17d6454c71bf5212895ec055c578da0"
  "tmux-yank          acfd36e4fcba99f8310a7dfb432111c242fe7392"
)

# Check out a git repo at an exact commit. Idempotent, and never fatal: an
# unreachable pin leaves the checkout alone and warns.
pin_git_ref() {
  local dir="$1" ref="$2" label cur
  label="${dir##*/}"
  [[ -d "$dir/.git" ]] || { warn "$label: not a git checkout — cannot pin"; return 0; }
  cur="$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)"
  [[ "$cur" == "$ref" ]] && return 0
  # The pin is usually already local (it is an ancestor of the cloned branch);
  # fetch only when it is not, e.g. tpm's --single-branch clones on a machine
  # whose branch tip has moved past the pin.
  if ! git -C "$dir" cat-file -e "${ref}^{commit}" 2>/dev/null; then
    git -C "$dir" fetch -q --depth 1 origin "$ref" 2>/dev/null \
      || git -C "$dir" fetch -q origin 2>/dev/null || true
  fi
  if git -C "$dir" checkout -q --detach "$ref" 2>/dev/null; then
    log "$label pinned -> ${ref:0:8}"
  else
    warn "$label: could not check out pin ${ref:0:8} (left at ${cur:0:8})"
  fi
}

# Packages the setup relies on:
#   stow -> install.sh (dotfiles linking; noble ships 2.3.1, fully sufficient)
#   rg -> telescope live_grep          fzf -> tmux-fzf
#   git -> lazy.nvim, tpm              build-essential -> treesitter parser builds
#   node/npm -> NOT apt-installed: nvm provides node LTS (see ensure_nvm);
#              mason + npm-globals use it. apt nodejs/npm only as a fallback
#              if nvm is broken (handled in ensure_npm_globals).
#   python3/pip/venv -> mason (ruff, black, isort, mypy, pylint, debugpy)
#   unzip -> some mason packages
#   mosh -> roaming/persistent SSH sessions (pairs with tmux; needs UDP 60000-61000)
#   pass -> unix password manager (pulls gnupg; store is per-machine, never synced)
#   gh/glab -> forge CLIs
#   ruby -> mason: rubocop (gem install; noble ships 3.2 + gem)
#   fd-find -> telescope/nvim find_files (Ubuntu names the binary fdfind —
#              symlinked to fd below); tree -> directory listing
#   poppler-utils -> pdftotext/pdfinfo/pdffonts (macOS: brew formula poppler)
#   pandoc -> document converter (PDF output needs a TeX engine — install-tex.sh)
TOOL_DEPS=(stow curl wget git mosh unzip build-essential ripgrep fzf jq htop btop fastfetch gh glab aerc fd-find tree pass python3 python3-pip python3-venv ruby pandoc poppler-utils)

MODE="install"
PREFIX="/usr/local"
FORCE=0
DOCKER=0
TIER=""
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --force) FORCE=1 ;;
    --user)  PREFIX="${HOME}/.local" ;;
    --docker) DOCKER=1 ;;
    --low)   TIER="low" ;;
    --high)  TIER="high" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (see --help)" >&2; exit 1 ;;
  esac
done

# Tier (mirrors install.sh): low = zerostack + pi-rust only. --low/--high
# force it; otherwise autodetected on Linux servers from total RAM (< 2GB,
# same threshold as nvim's lowmem gate). macOS is always high.
if [[ -z "$TIER" ]]; then
  TIER="high"
  if [[ "$(uname -s)" == "Linux" ]]; then
    mem_kb="$(awk '/^MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || true)"
    [[ -n "$mem_kb" && "$mem_kb" -lt 2097152 ]] && TIER="low"
  fi
fi

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
      [[ "$v" =~ ([a-z]+)$ ]] && { letter="${BASH_REMATCH[1]}"; v="${v%"$letter"}"; }
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
  # $pkgs is intentionally word-split: multiple package names, one per line
  # shellcheck disable=SC2086
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq $pkgs \
    || warn "apt-get remove failed — our install still wins via PATH (/usr/local/bin precedes /usr/bin)"
}

# Ensure apt packages are installed (no-op on systems without dpkg, e.g. macOS).
# Batch-first for speed; if the batch fails (one package unavailable on an older
# release — e.g. glab missing from bookworm), retry per-package so a single
# gap never blocks the rest of the toolchain.
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
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y -qq "${missing[@]}" && return 0
  warn "batch install failed — retrying per-package (older releases lack some tools)"
  for pkg in "${missing[@]}"; do
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y -qq "$pkg" \
      || warn "unavailable on this release: $pkg (skipped)"
  done
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

# --- Homebrew bootstrap (macOS, only when brew is missing) -------------------
# Homebrew's official installer also handles the Xcode Command Line Tools
# (which provide git); afterwards the Brewfile stage installs git + the rest.
ensure_homebrew() {
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  command -v brew >/dev/null 2>&1 && return 0
  # --check is documented as "report only, change nothing" — installing
  # Homebrew (and the Xcode CLT with it) is emphatically a change.
  [[ "$MODE" == "check" ]] && { warn "Homebrew: NOT INSTALLED (run without --check to install)"; return 0; }
  log "Homebrew not found — installing it (also installs the Xcode Command Line Tools; this can take a while)"
  # NONINTERACTIVE=1 makes the installer use `sudo -n`: on a normal Mac it
  # aborts instead of prompting for the password (same bug as bootstrap.sh).
  # Interactive when a TTY is reachable, non-interactive (passwordless sudo,
  # e.g. CI) only when no TTY exists.
  local hb_installer
  hb_installer="$(mktemp)"
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$hb_installer"
  if [[ -t 0 ]]; then
    /bin/bash "$hb_installer"
  elif /bin/bash -c ':' </dev/tty 2>/dev/null; then
    /bin/bash "$hb_installer" </dev/tty
  else
    warn "no TTY — non-interactive install (requires passwordless sudo)"
    NONINTERACTIVE=1 /bin/bash "$hb_installer"
  fi || { warn "Homebrew install failed — install it from https://brew.sh and rerun"; return 0; }
  rm -f "$hb_installer"
  # Make brew visible to the rest of this run regardless of arch/path.
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew: $(brew --version | head -n1)"
  fi
}
ensure_homebrew

# macOS: declarative brew tooling (Brewfile) BEFORE version checks, so
# freshly installed nvim/tmux satisfy the minimums and the Linux paths
# (tarball/source-build) never trigger on a Mac.
BREW_SOURCE_FILE="" BREW_SOURCE_LOG=""
ensure_brew_bundle() {
  if [[ "$(uname -s)" != "Darwin" ]] || ! command -v brew >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$MODE" == "check" ]]; then
    log "Brewfile status (--check: nothing is installed)"
    brew bundle check --file=Brewfile --verbose \
      || true   # non-zero simply means "some entries are missing"
    return 0
  fi
  # Homebrew >= 7 refuses to load formulae from third-party taps unless they
  # are explicitly trusted ("refusing to load formula ... from untrusted tap").
  # `brew trust` is idempotent and works non-interactively; taps listed in our
  # Brewfile are trusted by definition.
  local tap
  while IFS= read -r tap; do
    [[ "$tap" == homebrew/* ]] && continue
    brew trust --tap "$tap" >/dev/null 2>&1 \
      || warn "could not trust tap '$tap' — run 'brew trust --tap $tap' manually"
  done < <(sed -n 's/^[[:space:]]*tap[[:space:]]*"\([^"]*\)".*/\1/p' Brewfile)
  if [[ "$(uname -m)" == "arm64" ]]; then
    log "ensuring macOS tooling via Brewfile"
    # NOTE: no --no-lock — older brew versions reject it. The generated
    # Brewfile.lock.json is gitignored instead.
    brew bundle --file=Brewfile \
      || warn "brew bundle failed — install missing tools manually (see Brewfile)"
    return 0
  fi
  ensure_brew_bundle_intel
}

# Intel Macs: Homebrew only bottles the three newest macOS releases and
# publishes no x86 bottles for many formulas at all, so a plain `brew
# bundle` can block this script behind from-source compiles for hours or
# days. Split it: taps + casks + formulas WITH a bottle install
# synchronously; the from-source remainder is written to
# $BREW_SOURCE_FILE and spawned as a detached job at the very end of the
# run (start_brew_source_build) — install-deps.sh never waits on a compiler.
ensure_brew_bundle_intel() {
  local cache fast slow_count
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
  mkdir -p "$cache"
  BREW_SOURCE_LOG="$cache/brew-source-build.log"
  fast="$(mktemp)"
  # Must be a real path before the python split runs: it writes the deferred
  # from-source Brewfile here, and start_brew_source_build reads it at the end
  # of the run. It outlives this function, so it is NOT the $fast temp file.
  BREW_SOURCE_FILE="$cache/Brewfile.from-source"
  log "Intel Mac: splitting Brewfile (bottled + casks now, from-source later)"
  if command -v python3 >/dev/null 2>&1; then
    slow_count="$(python3 - "$fast" "$BREW_SOURCE_FILE" <<'PY'
import json, re, subprocess, sys
fast_path, slow_path = sys.argv[1], sys.argv[2]
lines = open("Brewfile").read().splitlines()
specs, kept = [], []
for line in lines:
    m = re.match(r'^brew\s+"([^"]+)"', line)
    if m:
        specs.append(m.group(1))
    kept.append((line, bool(m)))

macos_tag = None
try:
    ver = subprocess.run(["sw_vers", "-productVersion"], capture_output=True,
                         text=True).stdout.strip()
    macos_tag = {26: "tahoe", 15: "sequoia", 14: "sonoma", 13: "ventura",
                 12: "monterey", 11: "big_sur"}.get(int(ver.split(".")[0]))
except Exception:
    pass

bottled = set()
if specs:
    try:
        out = subprocess.run(["brew", "info", "--json=v2", "--formula", *specs],
                             capture_output=True, text=True, timeout=180).stdout
        data = json.loads(out or "{}")
        for f in data.get("formulae", []):
            name = f.get("full_name") or f.get("name")
            files = (((f.get("bottle") or {}).get("stable") or {}).get("files")) or {}
            ok = bool(files) if macos_tag is None else macos_tag in files
            if ok:
                bottled.add(name)
    except Exception:
        bottled = set(specs)  # fail open: old behavior, nothing deferred

with open(fast_path, "w") as fh:
    for line, is_brew in kept:
        if is_brew and re.match(r'^brew\s+"([^"]+)"', line).group(1) not in bottled:
            continue
        fh.write(line + "\n")
slow = 0
with open(slow_path, "w") as fh:
    for line, is_brew in kept:
        m = re.match(r'^brew\s+"([^"]+)"', line)
        if is_brew and m.group(1) not in bottled:
            fh.write(line + "\n")
            slow += 1
        elif not is_brew and re.match(r'^tap\s', line):
            fh.write(line + "\n")
print(slow)
PY
)" || slow_count=""
  else
    slow_count=""
  fi
  if [[ -n "${slow_count:-}" && "$slow_count" -gt 0 ]]; then
    log "Intel Mac: casks + bottled formulas first — from-source formulas deferred to a background job"
    brew bundle --file="$fast" \
      || warn "brew bundle (fast pass) failed — install missing tools manually (see Brewfile)"
    echo "note: $slow_count formula(s) have no bottle for this macOS — they will build from"
    echo "      source in the background after this script finishes (log: $BREW_SOURCE_LOG)"
  else
    log "ensuring macOS tooling via Brewfile (no from-source formulas detected)"
    brew bundle --file="$fast" \
      || warn "brew bundle failed — install missing tools manually (see Brewfile)"
    BREW_SOURCE_FILE=""
  fi
  rm -f "$fast"
}
ensure_brew_bundle

# Opt-in container tier (macOS only): colima + docker + compose, on-demand VM.
# Docker Desktop and default docker-on-servers are deliberately avoided —
# see Brewfile.docker and the README.
ensure_brew_bundle_docker() {
  (( DOCKER )) || return 0
  [[ "$MODE" == "check" ]] && { log "--check: skipping container tier install"; return 0; }
  if [[ "$(uname -s)" != "Darwin" ]]; then
    warn "--docker is macOS-only (servers deliberately get no docker)"
    return 0
  fi
  log "ensuring container tier (colima + docker + compose) via Brewfile.docker"
  brew bundle --file=Brewfile.docker \
    || warn "docker tier install failed — see Brewfile.docker"
  if command -v colima >/dev/null 2>&1; then
    echo "container tier ready. start the VM with: colima start   (stop: colima stop)"
  fi
}
ensure_brew_bundle_docker

log "detected: nvim=${NVIM_CUR:-missing}, tmux=${TMUX_CUR:-missing}"
if [[ -r /etc/os-release ]]; then
  # shellcheck source=/dev/null
  . /etc/os-release
  log "distro: ${NAME} ${VERSION_ID:-} ${VERSION_CODENAME:-}"
  unset NAME VERSION_ID VERSION_CODENAME
fi
log "targets:  nvim>=${MIN_NVIM_VERSION} (install ${NVIM_VERSION}), tmux>=${MIN_TMUX_VERSION} (install ${TMUX_VERSION})"

if [[ -z "$NVIM_CUR" ]] || ! ver_ge "$NVIM_CUR" "$MIN_NVIM_VERSION"; then
  NEED_NVIM=1
fi
if [[ -z "$TMUX_CUR" ]] || ! ver_ge "$TMUX_CUR" "$MIN_TMUX_VERSION"; then
  NEED_TMUX=1
fi
if (( FORCE )); then NEED_NVIM=1 NEED_TMUX=1; fi

if [[ "$MODE" == "check" ]]; then
  if (( NEED_NVIM )); then
    warn "nvim ${NVIM_CUR:-missing}: BELOW minimum ${MIN_NVIM_VERSION} — run without --check to install ${NVIM_VERSION}"
  else
    log "nvim ${NVIM_CUR}: OK (>= ${MIN_NVIM_VERSION})"
  fi
  if (( NEED_TMUX )); then
    warn "tmux ${TMUX_CUR:-missing}: BELOW minimum ${MIN_TMUX_VERSION} — run without --check to install ${TMUX_VERSION}"
  else
    log "tmux ${TMUX_CUR}: OK (>= ${MIN_TMUX_VERSION})"
  fi
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
  if [[ "$(uname -s)" == "Linux" ]]; then
    if command -v keyd >/dev/null 2>&1; then
      log "keyd: $(keyd --version 2>&1 | head -n1) (pin ${KEYD_VERSION})"
    else
      log "keyd: not installed (desktops only; pin ${KEYD_VERSION})"
    fi
    if command -v ghostty >/dev/null 2>&1; then
      log "ghostty: $(ghostty --version 2>/dev/null | head -n1) (pin ${GHOSTTY_VERSION})"
    else
      log "ghostty: not installed (desktops only; pin ${GHOSTTY_VERSION})"
    fi
  fi
  exit 0
fi

TMPDIR_BUILD="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BUILD"' EXIT

# --- editor tool dependencies ------------------------------------------------
ensure_apt_packages "${TOOL_DEPS[@]}"

# fd-find's binary is `fdfind` on Ubuntu — nvim/telescope expect `fd`.
# User-local symlink (no sudo); ~/.local/bin is on PATH via .bash_aliases.
if [[ "$(uname -s)" != "Darwin" ]] && command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  log "symlinked fdfind -> ~/.local/bin/fd"
fi

# --- tree-sitter CLI (required by nvim-treesitter main to compile parsers) ---
# Linux: official release binary. macOS: brew formula `tree-sitter-cli`
# (NOT `tree-sitter`, which is only the parser library).
ensure_tree_sitter_cli() {
  if command -v tree-sitter >/dev/null 2>&1; then
    local cur
    cur="$(tree-sitter --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"
    if [[ -n "$cur" ]] && ver_ge "$cur" "${MIN_TS_CLI_VERSION}"; then
      log "tree-sitter CLI: $cur (>= ${MIN_TS_CLI_VERSION})"
      return 0
    fi
    log "tree-sitter CLI $cur: below minimum ${MIN_TS_CLI_VERSION} — reinstalling"
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      log "installing tree-sitter CLI via Homebrew"
      brew install tree-sitter-cli || warn "brew install failed — try 'npm install -g tree-sitter-cli'"
    else
      warn "tree-sitter CLI missing — install Homebrew, or 'npm install -g tree-sitter-cli'"
    fi
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

# --- nvm + uv (per-machine dev tooling; user-local, no sudo) -----------------
ensure_nvm() {
  # env -u PREFIX: nvm refuses to run when PREFIX is set (the script sets it),
  # so the probe would always fail and force a reinstall on every run.
  local installed
  # shellcheck disable=SC2016  # intentional: ${HOME} must expand inside the subshell, after nvm.sh loads
  installed="$(env -u PREFIX bash -c '. "$HOME/.nvm/nvm.sh" && nvm --version' 2>/dev/null | head -n1 || true)"
  if [[ -n "$installed" ]] && ver_ge "$installed" "${NVM_VERSION#v}"; then
    log "nvm: $installed (>= ${NVM_VERSION})"
  else
    log "installing nvm ${NVM_VERSION}${installed:+ (upgrading from $installed)} -> ~/.nvm"
    # Pre-create NVM_DIR: the installer only auto-creates it when it matches
    # its default ($HOME/.nvm, or $XDG_CONFIG_HOME/nvm if that var is set) —
    # a preset-but-missing dir on an XDG machine would be refused.
    mkdir -p "$HOME/.nvm"
    # Pin NVM_DIR explicitly: never inherit it from the calling environment,
    # or the installer could target the wrong home.
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" \
      | NVM_DIR="$HOME/.nvm" METHOD=git bash \
      || warn "nvm install failed — see https://github.com/nvm-sh/nvm"
  fi
  # Provide an actual node runtime through nvm: nvm alone gives no node/npm,
  # and Mason's npm-based LSP servers (pyright, prettierd, eslint_d) need one.
  # Skipped when the user already manages their own node versions.
  # (System apt nodejs remains the non-interactive fallback for scripts.)
  # PREFIX is unset inside a subshell — nvm refuses to run with it set, but
  # the global PREFIX (/usr/local) is needed later by the nvim/tmux installers.
  if [[ -z "$(find "$HOME/.nvm/versions/node" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]]; then
    log "installing node LTS via nvm (+ default alias)"
    (
      unset PREFIX
      export NVM_DIR="$HOME/.nvm"
      # shellcheck source=/dev/null
      . "$NVM_DIR/nvm.sh"
      nvm install --lts
      nvm alias default 'lts/*'
    ) || warn "node LTS install failed — run 'nvm install --lts' manually"
  fi
}

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    local cur
    cur="$(uv --version 2>&1 | awk '{print $2}')"
    if [[ "$cur" == "$UV_VERSION" ]]; then
      log "uv: $cur"
      return 0
    fi
    log "uv: upgrading $cur -> ${UV_VERSION}"
  else
    log "installing uv ${UV_VERSION} -> ~/.local/bin"
  fi
  curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh \
    || warn "uv install failed — see https://docs.astral.sh/uv/"
}
ensure_nvm
ensure_uv

# --- typescript-language-server (removed from mason registry; npm global) ----
ensure_npm_globals() {
  # Runs in a subshell with PREFIX unset: nvm refuses to operate when it is
  # set, and nothing here needs the installer's global PREFIX. node/npm come
  # from nvm (LTS installed above); apt nodejs+npm is only a fallback if nvm
  # is missing/broken — keeps the apt footprint lean.
  (
    unset PREFIX
    if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
      # shellcheck source=/dev/null
      . "$HOME/.nvm/nvm.sh"
    fi
    if ! command -v npm >/dev/null 2>&1; then
      warn "npm still missing — falling back to apt nodejs+npm"
      ensure_apt_packages nodejs npm
    fi
    command -v npm >/dev/null 2>&1 || { warn "npm not found — skipping typescript-language-server install"; return 0; }
    # npm -g install is idempotent: upgrades when newer exists, quick no-op when
    # current. This also repairs bad installs (e.g. typescript@7 alongside a
    # typescript-language-server that requires typescript@5).
    log "ensuring typescript@5 + typescript-language-server (npm global)"
    if [[ -w "$(npm config get prefix)/lib" || -w "$(npm config get prefix)" ]]; then
      npm install -g -q "typescript@5" typescript-language-server \
        || warn "npm install failed — run 'npm i -g typescript@5 typescript-language-server' manually"
    else
      log "npm prefix not writable — using sudo"
      $SUDO env npm install -g -q "typescript@5" typescript-language-server \
        || warn "npm install failed — run 'sudo npm i -g typescript@5 typescript-language-server' manually"
    fi
    command -v typescript-language-server >/dev/null 2>&1 && \
      log "typescript-language-server: $(typescript-language-server --version 2>&1 | head -n1)"
  ) || warn "npm globals stage failed"
}
ensure_npm_globals

# --- opencode + Claude Code (high tier only) --------------------------------
# Official self-updating install scripts -> ~/.local/bin. Cross-platform
# (macOS + Linux); skipped on the low tier like the TypeScript pi above.
ensure_opencode() {
  [[ "$TIER" == "low" ]] && { log "tier low — skipping opencode"; return 0; }
  if command -v opencode >/dev/null 2>&1; then
    log "opencode: $(opencode --version 2>&1 | head -n1) (already installed)"
    return 0
  fi
  log "installing opencode -> ~/.local/bin"
  curl -fsSL https://opencode.ai/install | bash \
    || warn "opencode install failed — see https://opencode.ai/docs"
  # if-block, not `command -v X && log ...`: as a function's LAST command
  # that returns 1 when X is absent, which `set -e` turns into a fatal
  # error at the call site. This is what aborted the Linux CI dogfood:
  # the opencode installer puts the binary on PATH for FUTURE shells,
  # so the probe failed in the current one and killed the whole run.
  if command -v opencode >/dev/null 2>&1; then
    log "opencode: $(opencode --version 2>&1 | head -n1)"
  else
    log "opencode installed — not yet on PATH in this shell (new shells will see it)"
  fi
}
ensure_opencode

ensure_claude() {
  [[ "$TIER" == "low" ]] && { log "tier low — skipping Claude Code"; return 0; }
  if command -v claude >/dev/null 2>&1; then
    log "claude: $(claude --version 2>&1 | head -n1) (already installed)"
    return 0
  fi
  log "installing Claude Code -> ~/.local/bin"
  # Save to temp file first: the claude binary's `install` step needs a TTY,
  # which is unavailable when piped (stdin is the pipe content).
  local claude_installer
  claude_installer="$(mktemp)"
  # Bail out on download failure: an empty/partial file would otherwise be
  # executed by bash below (bash exits 0 on an empty script).
  curl -fsSL https://claude.ai/install.sh -o "$claude_installer" \
    || { rm -f "$claude_installer"; warn "claude installer download failed — see https://docs.anthropic.com/en/docs/claude-code"; return 0; }
  if [[ -t 0 ]]; then
    /bin/bash "$claude_installer"
  elif /bin/bash -c ':' </dev/tty 2>/dev/null; then
    /bin/bash "$claude_installer" </dev/tty
  else
    warn "no TTY — non-interactive claude install may fail"
    /bin/bash "$claude_installer"
  fi || warn "claude install failed — see https://docs.anthropic.com/en/docs/claude-code"
  rm -f "$claude_installer"
  if command -v claude >/dev/null 2>&1; then
    log "claude: $(claude --version 2>&1 | head -n1)"
  else
    log "claude installed — not yet on PATH in this shell (new shells will see it)"
  fi
}
ensure_claude

# --- ghostty terminfo (so TERM=xterm-ghostty works on servers) ---------------
# Vendored terminfo source; installs user-local to ~/.terminfo (no sudo).
ensure_ghostty_terminfo() {
  if infocmp -x xterm-ghostty >/dev/null 2>&1; then
    log "terminfo xterm-ghostty: present"
    return 0
  fi
  command -v tic >/dev/null 2>&1 || { warn "tic not found — skipping ghostty terminfo install"; return 0; }
  if [[ ! -f terminfo/xterm-ghostty.terminfo ]]; then
    warn "terminfo/xterm-ghostty.terminfo missing from repo — skipping"
    return 0
  fi
  if tic -x terminfo/xterm-ghostty.terminfo; then
    log "installed terminfo xterm-ghostty -> $HOME/.terminfo"
  else
    warn "tic failed to compile the ghostty terminfo (non-fatal)"
  fi
}
ensure_ghostty_terminfo

# --- keyd: Mac-style Super shortcuts (Linux desktops only) ----------------------
# keyd is a root daemon that remaps at the evdev level, so it works in every
# app and under X11 or Wayland. Built from the pinned release tag (Ubuntu 24.04
# has no package). Its config is system-wide and NOT stowed: etc/keyd/
# default.conf is copied to /etc/keyd/. The per-window half (~/.config/keyd/
# app.conf, run by keyd-application-mapper from the i3 config) is stowed by
# install.sh as the keyd package.
ensure_keyd() {
  [[ "$(uname -s)" == "Linux" ]] || return 0
  case "$KEYD" in
    0) return 0 ;;
    1) ;;
    *) [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || return 0 ;;
  esac
  if [[ $EUID -ne 0 && -z "$SUDO" ]]; then
    warn "keyd needs root (system daemon + /etc/keyd) — skipped in --user mode"
    return 0
  fi
  # python3-xlib: keyd-application-mapper's X11 backend (i3)
  ensure_apt_packages python3-xlib

  local cur built=0
  cur="$(keyd --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
  if (( FORCE )) || [[ -z "$cur" ]] || ! ver_ge "$cur" "$KEYD_VERSION"; then
    [[ -n "$cur" ]] && remove_apt_package keyd
    log "building keyd ${KEYD_VERSION} -> /usr/local"
    curl -fsSL -o "$TMPDIR_BUILD/keyd.tar.gz" \
      "https://github.com/rvaiya/keyd/archive/refs/tags/v${KEYD_VERSION}.tar.gz"
    tar -C "$TMPDIR_BUILD" -xzf "$TMPDIR_BUILD/keyd.tar.gz"
    (
      cd "$TMPDIR_BUILD/keyd-${KEYD_VERSION}"
      make -j"$(nproc)"
      $SUDO make install PREFIX=/usr/local
    )
    built=1
  else
    log "keyd ${cur}: OK (>= ${KEYD_VERSION})"
  fi

  # Never clobber a hand-written config silently: anything that isn't
  # already ours is kept aside (a *.bak.* name, so keyd won't load it).
  local conf=/etc/keyd/default.conf changed=0
  if ! cmp -s etc/keyd/default.conf "$conf"; then
    if [[ -f "$conf" ]]; then
      $SUDO cp "$conf" "$conf.bak.$(date +%Y%m%d%H%M%S)"
      log "backed up existing $conf"
    fi
    $SUDO install -Dm644 etc/keyd/default.conf "$conf"
    log "installed $conf"
    changed=1
  fi

  if [[ -d /run/systemd/system ]]; then
    (( built )) && $SUDO systemctl daemon-reload
    $SUDO systemctl enable --now keyd
    if (( built )); then
      $SUDO systemctl restart keyd
    elif (( changed )); then
      $SUDO keyd reload || warn "keyd reload failed — check: sudo journalctl -u keyd"
    fi
  else
    warn "no systemd — start keyd from your init system (config: $conf)"
  fi

  # keyd-application-mapper talks to /var/run/keyd.socket, group keyd only.
  if [[ -n "${USER:-}" && $EUID -ne 0 ]] && ! id -nG "$USER" | tr ' ' '\n' | grep -qx keyd; then
    $SUDO usermod -aG keyd "$USER"
    warn "added $USER to group keyd — log out and back in for keyd-application-mapper to work"
  fi
}
ensure_keyd

# --- ghostty: GPU-accelerated terminal (Linux desktops only) -----------------
# macOS: handled by Brewfile. Linux servers: don't need a GUI terminal.
# Install priority: apt (Ubuntu 26.04+, Debian trixie+), community .deb
# (mkasberg/ghostty-ubuntu), snap (any distro with snapd).
ensure_ghostty() {
  [[ "$(uname -s)" == "Linux" ]] || return 0
  [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || return 0

  if command -v ghostty >/dev/null 2>&1; then
    log "ghostty: $(ghostty --version 2>/dev/null | head -n1)"
    return 0
  fi

  # 1) Try apt (Ubuntu 26.04+, Debian trixie+)
  if apt-cache show ghostty >/dev/null 2>&1; then
    log "installing ghostty via apt"
    ensure_apt_packages ghostty && return 0
  fi

  # 2) Try community .deb (Ubuntu 24.04/26.04, Debian trixie/forky, and derivatives)
  log "trying community .deb from mkasberg/ghostty-ubuntu"
  if curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh | bash; then
    log "ghostty: $(ghostty --version 2>/dev/null | head -n1)"
    return 0
  fi
  warn "community .deb install failed or unsupported distro"

  # 3) Try snap (works on any distro with snapd)
  if command -v snap >/dev/null 2>&1; then
    log "installing ghostty via snap"
    $SUDO snap install ghostty --classic 2>&1 && return 0
    warn "snap install failed"
  fi

  warn "ghostty: no install method available — install manually or build from source"
}
ensure_ghostty

# --- zerostack (tiny Rust coding agent — fits 1GB instances) -----------------
# Official install script (prebuilt binary, near-instant even on small vCPUs).
ensure_zerostack() {
  if command -v zerostack >/dev/null 2>&1; then
    log "zerostack: $(zerostack --version 2>/dev/null | head -n1)"
  else
    log "installing zerostack (official install script)"
    curl -fsSL https://raw.githubusercontent.com/gi-dellav/zerostack/main/install.sh | bash \
      || warn "zerostack install failed — see https://github.com/gi-dellav/zerostack#installation"
  fi
  # Config comes from install.sh (stowed ~/.config/zerostack/config.toml —
  # secret-free; the API key resolves from OPENROUTER_API_KEY at runtime).
  if command -v zerostack >/dev/null 2>&1; then
    echo "note: put OPENROUTER_API_KEY in ~/.config/shell/secrets.local (per machine — never in shell rc files or this repo)"
  fi
}
ensure_zerostack


# --- pi (pi_agent_rust — Rust port of Mario Zechner's Pi Agent) --------------
# Single-binary coding agent; complements zerostack on servers and works on
# Macs. Auth: provider env keys (OPENROUTER_API_KEY etc. from secrets.local).
# NOTE: the official installer may append PATH lines to shell rc files — our
# stowed rc files already export ~/.local/bin, so its check should no-op.
ensure_pi_agent() {
  # The official installer is idempotent (state in ~/.local/state/pi-agent-rust)
  # and handles the name collision with the TypeScript original itself: installs
  # as `pi` on fresh machines, as `pi-rust` when a TS pi already exists. Always
  # invoke it — it no-ops quickly when current.
  log "ensuring pi (pi_agent_rust official installer)"
  curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/pi_agent_rust/main/install.sh" \
    | bash -s -- --yes \
    || warn "pi install failed — see https://github.com/Dicklesworthstone/pi_agent_rust#installation"

  # Name normalization: the rust build must always be `pi-rust` — `pi` is
  # reserved for the TypeScript pi. The rust installer writes to whichever
  # bin dir contains the existing pi (often the nvm node bin, not
  # ~/.local/bin), so check all candidate paths.
  local rust_src=""
  local candidate
  # The nvm path must stay UNQUOTED so the version glob expands (a quoted
  # "*" matched nothing, which defeated the whole normalization step).
  # shellcheck disable=SC2231
  for candidate in \
    "$HOME/.local/bin/pi" \
    $HOME/.nvm/versions/node/*/bin/pi \
    "/usr/local/bin/pi"; do
    # glob may expand to nothing (stays literal) — -x filters that out
    [[ -x "$candidate" ]] || continue
    if "$candidate" --version 2>/dev/null | grep -qE '\([0-9a-f]{6,} 20[0-9]{2}-[0-9]{2}-'; then
      rust_src="$candidate"
      break
    fi
  done
  if [[ -n "$rust_src" && "$rust_src" != "$HOME/.local/bin/pi-rust" ]]; then
    mkdir -p "$HOME/.local/bin"
    cp -f "$rust_src" "$HOME/.local/bin/pi-rust"
    chmod +x "$HOME/.local/bin/pi-rust"
    log "copied rust pi binary -> ~/.local/bin/pi-rust (from $rust_src)"
  fi

  if command -v pi-rust >/dev/null 2>&1; then
    log "pi-rust: $(pi-rust --version 2>&1 | head -n1)"
  fi
  if command -v pi >/dev/null 2>&1; then
    log "pi (TypeScript): $(pi --version 2>&1 | head -n1)"
  fi
  echo "note: both pi builds read provider keys from the environment (OPENROUTER_API_KEY etc. — see secrets.local)"
}
ensure_pi_agent

# --- pi (TypeScript — @earendil-works/pi-coding-agent) -----------------------
# The full-featured coding agent from the pi-mono repo (the Rust port is
# pi_agent_rust above). High tier only: needs node >= 22.19. Runs AFTER the
# rust installer so that npm reinstalls the TS binary as `pi`, overwriting
# any copy the rust installer left in the nvm node bin path.
PI_MIN_NODE_VERSION="${PI_MIN_NODE_VERSION:-22.19.0}"
ensure_pi_ts() {
  [[ "$TIER" == "low" ]] && { log "tier low — skipping TypeScript pi (uses pi-rust instead)"; return 0; }
  (
    unset PREFIX
    if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
      # shellcheck source=/dev/null
      . "$HOME/.nvm/nvm.sh"
    fi
    command -v npm >/dev/null 2>&1 || { warn "npm not found — skipping TypeScript pi install"; return 0; }
    # TS pi requires node >= 22.19: refresh the nvm LTS when the active node
    # is older (idempotent — `nvm install --lts` resolves to the newest LTS).
    local node_cur node_min
    node_cur="$(node --version 2>/dev/null | sed 's/^v//')"
    node_min="${PI_MIN_NODE_VERSION#v}"
    if [[ -z "$node_cur" ]] || ! ver_ge "$node_cur" "$node_min"; then
      log "node ${node_cur:-missing}: below TypeScript pi minimum ${node_min} — installing latest LTS"
      nvm install --lts && nvm alias default 'lts/*' \
        || { warn "node LTS install failed — skipping TypeScript pi"; return 0; }
      hash -r
    fi
    log "ensuring @earendil-works/pi-coding-agent (npm global)"
    npm install -g -q @earendil-works/pi-coding-agent \
      || warn "TS pi install failed — run 'npm i -g @earendil-works/pi-coding-agent' manually"
    command -v pi >/dev/null 2>&1 && \
      log "pi (TypeScript): $(pi --version 2>&1 | head -n1)"
  ) || warn "TypeScript pi stage failed"
}
ensure_pi_ts

# --- oh-my-zsh (macOS only — Linux servers run bash) -------------------------
ensure_omz() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return 0
  fi
  if [[ -d "$HOME/.oh-my-zsh/.git" ]]; then
    log "oh-my-zsh: converging on pin ${OMZ_REF:0:8}"
  else
    log "installing oh-my-zsh -> ~/.oh-my-zsh (pinned ${OMZ_REF:0:8})"
    # No --depth=1: a shallow clone of the branch tip usually will not contain
    # the pinned commit. blob:none keeps it cheap anyway.
    git clone -q --filter=blob:none https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" \
      || warn "oh-my-zsh install failed — see https://ohmyz.sh"
  fi
  pin_git_ref "$HOME/.oh-my-zsh" "$OMZ_REF"
}
ensure_omz

# --- cloud & forge CLIs ------------------------------------------------------
# gh/glab come from apt via TOOL_DEPS. aws/az/gcloud have no current distro
# packages, so each uses its vendor installer below. macOS gets all of them
# from the Brewfile instead. Credentials are per-machine (~/.aws, ~/.azure,
# ~/.config/gcloud) — authenticate with `aws sso login` / `az login` /
# `gcloud auth login`; never in this repo.

ensure_aws_cli() {
  if command -v aws >/dev/null 2>&1; then
    log "aws: $(aws --version 2>&1 | head -n1)"
    return 0
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    warn "aws CLI missing — install via Brewfile (brew install awscli)"
    return 0
  fi
  local arch
  case "$(uname -m)" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) echo "ERROR: unsupported arch $(uname -m)" >&2; return 1 ;;
  esac
  log "installing AWS CLI v2 (latest) -> ${PREFIX}"
  curl -fsSL -o "$TMPDIR_BUILD/awscliv2.zip" \
    "https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip"
  unzip -oq "$TMPDIR_BUILD/awscliv2.zip" -d "$TMPDIR_BUILD"
  $SUDO "$TMPDIR_BUILD/aws/install" --update
  log "aws: $(aws --version 2>&1 | head -n1)"
}

ensure_azure_cli() {
  if command -v az >/dev/null 2>&1; then
    log "az: $(az version --output tsv 2>/dev/null | head -n1)"
    return 0
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    warn "az CLI missing — install via Brewfile (brew install azure-cli)"
    return 0
  fi
  log "installing Azure CLI (aka.ms script — adds Microsoft apt repo)"
  # arm64: MS publishes arm64 debs for recent Ubuntu releases; on unsupported
  # arches this fails and the warn below is the signal.
  curl -sL https://aka.ms/InstallAzureCLIDeb | $SUDO bash \
    || warn "azure cli install failed — see https://learn.microsoft.com/cli/azure/install-azure-cli-linux"
}

ensure_gcloud() {
  if command -v gcloud >/dev/null 2>&1; then
    log "gcloud: $(gcloud --version 2>&1 | head -n1)"
    return 0
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    warn "gcloud missing — install via Brewfile (brew install --cask google-cloud-sdk)"
    return 0
  fi
  log "installing Google Cloud SDK (Google apt repo)"
  ensure_apt_packages gnupg
  $SUDO install -d /usr/share/keyrings
  curl -fsSL "https://packages.cloud.google.com/apt/doc/apt-key.gpg" \
    | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/cloud.google.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | $SUDO tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  $SUDO apt-get update -qq
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y -qq google-cloud-cli \
    || warn "gcloud install failed — see https://cloud.google.com/sdk/docs/install-apt"
}
ensure_aws_cli
ensure_azure_cli
ensure_gcloud

# --- lazygit (snacks.lazygit / <leader>ug needs the binary) ------------------
# Not in noble's apt repos — install from GitHub releases, user-local.
ensure_lazygit() {
  if command -v lazygit >/dev/null 2>&1; then
    log "lazygit: $(lazygit --version 2>&1 | head -n1)"
    return 0
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    warn "lazygit missing — install via Brewfile (brew install lazygit)"
    return 0
  fi
  local arch version url
  case "$(uname -m)" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "ERROR: unsupported arch $(uname -m)" >&2; return 1 ;;
  esac
  version="$(curl -sS "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" \
    | grep -oE '"tag_name": *"[^"]*"' | head -n1 | cut -d '"' -f4 | sed 's/^v//' || true)"
  if [[ -z "$version" ]]; then
    warn "could not determine lazygit latest version — skipping"
    return 0
  fi
  url="https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_${arch}.tar.gz"
  log "installing lazygit v${version} -> ~/.local/bin"
  mkdir -p "$HOME/.local/bin"
  curl -fsSL -o "$TMPDIR_BUILD/lazygit.tar.gz" "$url"
  tar -C "$TMPDIR_BUILD" -xzf "$TMPDIR_BUILD/lazygit.tar.gz" lazygit
  install -m 0755 "$TMPDIR_BUILD/lazygit" "$HOME/.local/bin/lazygit"
  log "lazygit: $(lazygit --version 2>&1 | head -n1)"
}
ensure_lazygit

# --- neovim: official release tarball (Linux) / Homebrew (macOS) ------------
if (( NEED_NVIM )); then
  command -v nvim >/dev/null 2>&1 && remove_apt_package nvim
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      log "installing neovim via Homebrew"
      brew install neovim || echo "ERROR: brew install neovim failed" >&2
    else
      echo "ERROR: macOS without Homebrew — install neovim manually (>= ${MIN_NVIM_VERSION})" >&2
      exit 1
    fi
  else
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
  fi
else
  log "nvim ${NVIM_CUR}: up to date, skipping"
fi

# --- tmux: Homebrew (macOS) / build from release tarball (Linux) -------------
if (( NEED_TMUX )); then
  command -v tmux >/dev/null 2>&1 && remove_apt_package tmux
  if [[ "$(uname -s)" == "Darwin" ]]; then
    log "installing tmux via Homebrew"
    brew install tmux
  else
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
  fi
else
  log "tmux ${TMUX_CUR}: up to date, skipping"
fi

# --- tpm: tmux plugin manager (must live at ~/.config/tmux/plugins/tpm) -----
TPM_DIR="$HOME/.config/tmux/plugins/tpm"
PLUGIN_ROOT="$HOME/.config/tmux/plugins"
LEGACY_TPM_DIR="$HOME/.tmux/plugins/tpm"

if command -v git >/dev/null 2>&1; then
  if [[ -d "$TPM_DIR/.git" ]]; then
    log "tpm at $TPM_DIR: converging on pin ${TPM_REF:0:8}"
  elif [[ -d "$LEGACY_TPM_DIR/.git" ]]; then
    log "migrating legacy tpm: ~/.tmux/plugins -> ~/.config/tmux/plugins"
    mkdir -p "$HOME/.config/tmux/plugins"
    mv "$HOME/.tmux/plugins/"* "$HOME/.config/tmux/plugins/" || true
    rmdir "$HOME/.tmux/plugins" "$HOME/.tmux" 2>/dev/null || true
  else
    log "installing tpm -> $TPM_DIR"
    mkdir -p "$HOME/.config/tmux/plugins"
    git clone -q https://github.com/tmux-plugins/tpm "$TPM_DIR" || warn "tpm clone failed"
  fi
  pin_git_ref "$TPM_DIR" "$TPM_REF"
  # modern tpm ships bin/install_plugins; older versions bin/install_plugins.sh
  TPM_INSTALL=""
  for cand in "$TPM_DIR/bin/install_plugins" "$TPM_DIR/bin/install_plugins.sh"; do
    [[ -x "$cand" ]] && { TPM_INSTALL="$cand"; break; }
  done
  if [[ -n "$TPM_INSTALL" ]]; then
    log "installing tmux plugins (non-interactive)"
    "$TPM_INSTALL" >/dev/null 2>&1 \
      || warn "plugin install failed — run 'prefix + I' inside tmux"
    # tpm clones each plugin at its default branch (its `@plugin ... #ref`
    # syntax feeds `git clone -b`, which takes only a branch or tag — and
    # these projects have no usable tags). Pin the checkouts afterwards.
    for pin in "${TMUX_PLUGIN_PINS[@]}"; do
      read -r pin_dir pin_sha <<< "$pin"
      [[ -d "$PLUGIN_ROOT/$pin_dir" ]] && pin_git_ref "$PLUGIN_ROOT/$pin_dir" "$pin_sha"
    done
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

# --- Intel Mac only: from-source brew builds (MUST stay last) ----------------
# Spawned detached + niced so the script can exit; the build survives the
# exit (nohup) and logs to $BREW_SOURCE_LOG. Reruns skip what's installed.
start_brew_source_build() {
  [[ -n "$BREW_SOURCE_FILE" && -s "$BREW_SOURCE_FILE" ]] || return 0
  if pgrep -f "brew bundle --file=$BREW_SOURCE_FILE" >/dev/null 2>&1; then
    log "from-source brew build already running in the background (log: $BREW_SOURCE_LOG)"
    return 0
  fi
  : > "$BREW_SOURCE_LOG"
  nohup nice -n 10 brew bundle --file="$BREW_SOURCE_FILE" \
    >>"$BREW_SOURCE_LOG" 2>&1 </dev/null &
  log "from-source brew build running in the background (pid $!) — progress: tail -f $BREW_SOURCE_LOG"
}
start_brew_source_build

if [[ "$PREFIX" == "${HOME}/.local" ]]; then
  warn "make sure ${HOME}/.local/bin is on your PATH"
fi
if pgrep -x tmux >/dev/null 2>&1; then
  warn "a tmux server is already running on the old binary — 'tmux kill-server' when sessions allow"
fi
