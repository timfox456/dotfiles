#!/usr/bin/env bash
# Optional LaTeX toolchain — deliberately NOT part of the default setup
# (TeX distributions are several GB; servers and Office-having Macs don't
# need one). Run on machines that actually compile .tex.
#
# - macOS: Homebrew cask — default `mactex-no-gui` (full scheme, no GUI
#   apps), --full same, --basic `basictex` (small; packages added later
#   via `sudo tlmgr install <pkg>`).
# - Linux (Debian/Ubuntu, primary target): apt metapackages — default a
#   balanced subset (~1.5GB, no docs), --full `texlive-full` (~5GB),
#   --basic `texlive-latex-recommended` only.
# - Ghostscript is installed explicitly everywhere: the TeX engines need
#   it for image/EPS conversions (epstopdf etc.), and it is only pulled in
#   automatically by texlive-full/mactex, not by the smaller selections.
# - Config is NOT stowed here: the tiny `latex/` package (latexmkrc +
#   TEXMFHOME seed) is linked by `./install.sh` like every other package.
#
# Usage:
#   ./install-tex.sh           # balanced install (default)
#   ./install-tex.sh --full    # everything (texlive-full / full MacTeX)
#   ./install-tex.sh --basic   # small footprint, add packages via tlmgr
#   ./install-tex.sh --check   # report what's present, change nothing
set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }

MODE="install"   # install | check
SIZE="balanced"  # basic | balanced | full
for arg in "$@"; do
  case "$arg" in
    --full)  SIZE="full" ;;
    --basic) SIZE="basic" ;;
    --check) MODE="check" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (see --help)" >&2; exit 1 ;;
  esac
done

SUDO=""
if [[ $EUID -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
fi

# --- macOS -------------------------------------------------------------------
install_macos() {
  local cask="mactex-no-gui"
  [[ "$SIZE" == "basic" ]] && cask="basictex"
  # --full uses the same cask as balanced: mactex-no-gui IS the full scheme,
  # plain `mactex` only adds GUI applications.
  if [[ "$MODE" == "check" ]]; then
    if [[ -x /Library/TeX/texbin/pdflatex ]]; then
      log "TeX: $(/Library/TeX/texbin/pdflatex --version | head -n1 | awk '{print $2}') (cask: $cask)"
    else
      warn "TeX: missing — run without --check to install $cask"
    fi
    return 0
  fi
  command -v brew >/dev/null 2>&1 || { warn "brew missing — run install-deps.sh first"; exit 1; }
  log "installing $cask (multi-GB download, be patient)"
  brew install --cask "$cask"
  # ghostscript CLI: MacTeX ships its own Ghostscript.app, but the brew
  # formula guarantees `gs` on PATH for scripts and pandoc.
  command -v gs >/dev/null 2>&1 || brew install ghostscript
}

# --- Linux (Debian/Ubuntu) ---------------------------------------------------
install_linux() {
  command -v apt-get >/dev/null 2>&1 || {
    warn "non-Debian/Ubuntu system — install texlive by hand, e.g."
    warn "  fedora: dnf install texlive-scheme-medium pandoc ghostscript latexmk"
    warn "  arch:   pacman -S texlive-basic texlive-latexextra pandoc ghostscript"
    exit 1
  }
  local -a pkgs=(texlive-latex-recommended texlive-latex-extra \
                 texlive-fonts-recommended texlive-xetex texlive-luatex \
                 texlive-bibtex-extra biber latexmk ghostscript pandoc)
  [[ "$SIZE" == "basic" ]] && \
    pkgs=(texlive-latex-recommended latexmk ghostscript pandoc)
  [[ "$SIZE" == "full" ]] && pkgs=(texlive-full pandoc)

  if [[ "$MODE" == "check" ]]; then
    local -a missing=() pkg
    for pkg in "${pkgs[@]}"; do
      dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
      warn "TeX: missing ${missing[*]} — run without --check to install"
    else
      log "TeX: all ${#pkgs[@]} packages present"
    fi
    return 0
  fi

  log "installing apt packages: ${pkgs[*]}"
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  # --no-install-recommends: skips the -doc packages (100s of MB) and the
  # fonts/lang extras that pull most of the texlive-full bulk into the
  # balanced selection. fonts-recommended is listed explicitly above.
  if ! $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y -qq "${pkgs[@]}"; then
    warn "batch install failed — retrying per-package (older releases lack some metapackages)"
    local pkg
    for pkg in "${pkgs[@]}"; do
      $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y -qq "$pkg" \
        || warn "unavailable on this release: $pkg (skipped)"
    done
  fi
}

case "$(uname -s)" in
  Darwin) install_macos ;;
  Linux)  install_linux ;;
  *) warn "unsupported OS: $(uname -s)"; exit 1 ;;
esac

log "done. Next: ./install.sh links the latex/ config (latexmkrc + ~/texmf)."
