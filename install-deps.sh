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
NVM_VERSION="${NVM_VERSION:-v0.40.7}"
UV_VERSION="${UV_VERSION:-0.12.7}"
MIN_TS_CLI_VERSION="${MIN_TS_CLI_VERSION:-0.24.0}"
MIN_NVIM_VERSION="${MIN_NVIM_VERSION:-0.11.0}"   # vim.lsp.config / vim.lsp.enable era
MIN_TMUX_VERSION="${MIN_TMUX_VERSION:-3.4}"      # set-clipboard (OSC 52) needs >= 3.3

# Packages the setup relies on:
#   stow -> install.sh (dotfiles linking; noble ships 2.3.1, fully sufficient)
#   rg -> telescope live_grep          fzf -> tmux-fzf
#   git -> lazy.nvim, tpm              build-essential -> treesitter parser builds
#   node/npm -> mason (pyright, typescript-language-server)
#   python3/pip/venv -> mason (ruff, black, isort, mypy, pylint, debugpy)
#   unzip -> some mason packages
#   mosh -> roaming/persistent SSH sessions (pairs with tmux; needs UDP 60000-61000)
#   gh/glab -> forge CLIs
#   ruby -> mason: rubocop (gem install; noble ships 3.2 + gem)
TOOL_DEPS=(stow curl wget git mosh unzip build-essential ripgrep fzf jq htop gh glab nodejs npm python3 python3-pip python3-venv ruby)

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

# macOS: declarative brew tooling (Brewfile) BEFORE version checks, so
# freshly installed nvim/tmux satisfy the minimums and the Linux paths
# (tarball/source-build) never trigger on a Mac.
ensure_brew_bundle() {
  if [[ "$(uname -s)" != "Darwin" ]] || ! command -v brew >/dev/null 2>&1; then
    return 0
  fi
  log "ensuring macOS tooling via Brewfile"
  brew bundle --file=Brewfile --no-lock \
    || warn "brew bundle failed — install missing tools manually (see Brewfile)"
}
ensure_brew_bundle

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
  exit 0
fi

TMPDIR_BUILD="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BUILD"' EXIT

# --- editor tool dependencies ------------------------------------------------
ensure_apt_packages "${TOOL_DEPS[@]}"

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

# --- typescript-language-server (removed from mason registry; npm global) ----
ensure_npm_globals() {
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
}
ensure_npm_globals

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
  tic -x terminfo/xterm-ghostty.terminfo \
    && log "installed terminfo xterm-ghostty -> $HOME/.terminfo"
}
ensure_ghostty_terminfo

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
  command -v zerostack >/dev/null 2>&1 && \
    warn "remember: export OPENROUTER_API_KEY=\"sk-or-...\" in ~/.bashrc (per machine)"
}
ensure_zerostack

# --- nvm + uv (per-machine dev tooling; user-local, no sudo) -----------------
ensure_nvm() {
  local installed
  installed="$(bash -c '. "$HOME/.nvm/nvm.sh" && nvm --version' 2>/dev/null | head -n1)"
  if [[ -n "$installed" ]] && ver_ge "$installed" "${NVM_VERSION#v}"; then
    log "nvm: $installed (>= ${NVM_VERSION})"
  else
    log "installing nvm ${NVM_VERSION}${installed:+ (upgrading from $installed)} -> ~/.nvm"
    # Pin NVM_DIR explicitly: never inherit it from the calling environment,
    # or the installer could target the wrong home.
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" \
      | NVM_DIR="$HOME/.nvm" METHOD=git bash \
      || warn "nvm install failed — see https://github.com/nvm-sh/nvm"
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
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq google-cloud-cli \
    || warn "gcloud install failed — see https://cloud.google.com/sdk/docs/install-apt"
}
ensure_aws_cli
ensure_azure_cli
ensure_gcloud

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
