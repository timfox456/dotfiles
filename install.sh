#!/usr/bin/env bash
# Dotfiles installer — stows every package to $HOME.
#
# Usage:
#   ./install.sh             # variant autodetected: macOS/Linux-desktop = desktop,
#                            # headless Linux (no DISPLAY) = server
#   ./install.sh --server    # force server variant (tmux prefix C-a)
#   ./install.sh --desktop   # force desktop variant (tmux prefix C-b, i3 on Linux)
#   ./install.sh --low       # force low tier: no opencode config
#                            # (`pi` falls back to pi-rust via the shell wrappers)
#   ./install.sh --high      # force high tier (default on desktops and >= 2GB servers)
#   ./install.sh --help
#
# Packages mirror the $HOME layout (pkg/.config/...). Stow conflicts are
# resolved automatically: targets owned by another of our packages are
# unstowed (tmux variant swaps), anything else is backed up aside. Secrets
# never enter this repo — they are per-machine files we only chmod.

set -euo pipefail
cd "$(dirname "$0")"
REPO_DIR="$PWD"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

mkdir -p "$HOME/.config/tmux" "$HOME/.config/ghostty" \
         "$HOME/.config/zerostack" "$HOME/.config/git" "$HOME/.config/shell" \
         "$HOME/.config/aerc" "$HOME/.local/bin" "$HOME/.local/share/aerc" \
         "$HOME/.local/state/nvim" \
         "$HOME/.config/latexmk" "$HOME/texmf/tex/latex/tim"

# Guardrail: the secrets file must never be group/world readable.
[[ -f "$HOME/.config/shell/secrets.local" ]] && chmod 600 "$HOME/.config/shell/secrets.local"

# --- stow conflict resolution ------------------------------------------------
# Before the real stow, simulate it and resolve every "existing target"
# complaint: if the conflicting target belongs to another of OUR packages
# (tmux <-> tmux-server variant swaps), unstow that package; anything else
# (a pre-existing real file/dir or a foreign symlink) is moved aside with a
# timestamped backup. Never uses stow --adopt: adopting would pull machine
# files into this public repo.
resolve_stow_conflicts() {
  local round target resolved owner bak resolved_any
  local -a targets
  for round in 1 2 3 4 5; do
    targets=()
    # stow reports each conflict TWICE (CONFLICT line + target line) with
    # version-dependent formats — extract the path, then dedup (sort -u):
    #   variant links (2.3.x/2.4.x): "... stowed to a different package: P => Q"
    #   2.4.x real files: "CONFLICT ...: cannot stow PKGFILE over existing
    #                     target P since neither a link nor a directory
    #                     and --adopt not specified"
    #   2.3.x real files: "  * existing target is neither a link nor a directory: P"
    # Case order matters: the greedy-colon fallback must stay LAST and narrowed
    # to "neither", or it matches the 2.4 CONFLICT line and produces garbage.
    # The 2.4 "over existing target" case must capture ONLY the path token —
    # the line continues with " since neither ..." prose (this bug bit on
    # stow 2.4.1: mv got handed the whole message as a backup path).
    while IFS= read -r target; do
      [[ -z "$target" ]] && continue
      targets+=("$target")
    done < <(stow -n -t "$HOME" -v 2 "$@" 2>&1 \
      | grep -E "existing target" \
      | sed -E '
          s/.*stowed to a different package:[[:space:]]*([^[:space:]]*).*/\1/; t
          s/.*over existing target[[:space:]]+([^[:space:]]+).*/\1/; t
          s/.*existing target is neither a link nor a directory:[[:space:]]*//
        ' | sort -u || true)
    ((${#targets[@]})) || return 0

    resolved_any=0
    for target in "${targets[@]}"; do
      [[ -z "$target" ]] && continue
      resolved="$(readlink -f "$HOME/$target" 2>/dev/null || echo "$HOME/$target")"
      owner=""
      # Ownership scan covers ALL repo packages (not just this run's list) —
      # the opposite tmux variant is never in the current run's list, yet its
      # conflicts must be unstowed, not backed up.
      for dir in "$REPO_DIR"/*/; do
        pkg="$(basename "$dir")"
        [[ "$resolved" == "$dir"* || "$resolved" == "${dir%/}" ]] && { owner="$pkg"; break; }
      done
      resolved_any=1
      if [[ -n "$owner" ]]; then
        echo "unstowing conflicting package: $owner (owns $target)"
        stow -D -t "$HOME" "$owner" 2>/dev/null || true
      else
        bak="$HOME/${target}.bak.$(date +%Y%m%d%H%M%S)"
        mkdir -p "$(dirname "$bak")"
        mv "$HOME/$target" "$bak"
        echo "backed up: $HOME/$target -> $bak"
      fi
    done
    # Every reported target was unparseable (empty after the sed): there is
    # nothing we can act on, so stop instead of burning the remaining rounds.
    ((resolved_any)) || return 0
  done
  # The last round may have fixed everything — re-simulate before failing.
  stow -n -t "$HOME" "$@" >/dev/null 2>&1 && return 0
  echo "ERROR: stow conflicts persist after $round rounds — resolve manually" >&2
  return 1
}

# --- variant selection -------------------------------------------------------
# --server / --desktop force it. Otherwise: macOS is always a desktop, and
# Linux autodetects headless via DISPLAY (servers have none).
VARIANT=""
TIER=""
for arg in "$@"; do
  case "$arg" in
    --server)  VARIANT="server" ;;
    --desktop) VARIANT="desktop" ;;
    --low)     TIER="low" ;;
    --high)    TIER="high" ;;
    -h|--help) usage ;;
    *) echo "unknown option: $arg (see --help)" >&2; exit 1 ;;
  esac
done
if [[ -z "$VARIANT" ]]; then
  if [[ "$(uname -s)" == "Linux" && -z "${DISPLAY:-}" ]]; then
    VARIANT="server"
    echo "variant: server (headless autodetected — no DISPLAY)"
  else
    VARIANT="desktop"
    echo "variant: desktop"
  fi
fi

# --- tier selection -----------------------------------------------------------
# Low tier: 1GB boxes get no opencode (Bun-based, too heavy) and no
# TypeScript pi (needs node >= 22) — install-deps.sh skips installing both,
# and this script skips stowing opencode's config. Forced via --low/--high;
# otherwise autodetected on Linux servers from total RAM (< 2GB = low), same
# threshold as nvim's lowmem gate. Desktops and macOS are always high.
if [[ -z "$TIER" ]]; then
  TIER="high"
  if [[ "$VARIANT" == "server" && "$(uname -s)" == "Linux" ]]; then
    mem_kb="$(awk '/^MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || true)"
    [[ -n "$mem_kb" && "$mem_kb" -lt 2097152 ]] && TIER="low"
  fi
fi
if [[ "$TIER" == "low" ]]; then
  echo "tier: low (no opencode config)"
else
  echo "tier: high (opencode config included)"
fi

# latex/ is tiny config (latexmkrc + TEXMFHOME seed) — stowed even on machines
# that haven't run install-tex.sh yet; the dirs above are pre-created so the
# ~/texmf tree gets file-level links instead of a repo-folding ~/texmf symlink.
STOW_PKGS=(tmux-common ghostty zerostack git shell bin aerc nvim btop fastfetch latex)
if [[ "$TIER" == "high" ]]; then
  STOW_PKGS+=(opencode)
fi
if [[ "$VARIANT" == "server" ]]; then
  STOW_PKGS+=(tmux-server)
else
  STOW_PKGS+=(tmux)
  [[ "$(uname -s)" == "Linux" ]] && STOW_PKGS+=(i3)
fi

# Tier downgrade: stow --restow never touches unlisted packages, so dropping
# a machine to the low tier must explicitly unstow the high-tier ones.
# (pi needs two checks: a file-level settings link or a tree-folded
# ~/.config/pi symlink — see the stow-folding footgun in AGENTS.md.)
if [[ "$TIER" == "low" ]]; then
  [[ -L "$HOME/.config/opencode/opencode.json" ]] && \
    { stow -D -t "$HOME" opencode && echo "unstowed: opencode (low tier)"; } || true
fi

# Migration: the pi / pi-rust agent settings.json used to be stowed from this
# repo. It only ever held machine state (lastChangelogVersion), so the packages
# are gone and both agent dirs are plain machine-local dirs now. Clear out the
# dangling links the old layout left behind so each agent can write its own.
# ~/lazy-lock-sync is the same kind of leftover: bin/lazy-lock-sync used to
# sit at the package root, so stow linked it into $HOME directly. It lives at
# bin/.local/bin/ now (i.e. ~/.local/bin/lazy-lock-sync).
for stale in "$HOME/.config/pi/agent/settings.json" \
             "$HOME/.config/pi-rust/agent/settings.json" \
             "$HOME/lazy-lock-sync"; do
  if [[ -L "$stale" && ! -e "$stale" ]] && \
     [[ "$(readlink "$stale")" == *"$(basename "$REPO_DIR")"/* ]]; then
    rm -f "$stale"
    echo "removed dangling link from the old layout: $stale"
  fi
done

# --- package sanity guard -----------------------------------------------------
# Two classes of bug have bitten this repo before, both mechanically checkable:
#   1. a package listed here but missing from the repo (stow aborts the whole
#      run — this happened when the pi packages were deleted);
#   2. a package file at the package ROOT, which stow links straight into
#      $HOME (~/config instead of ~/.config/i3/config — happened with i3/).
# Also refuses to stow well-known machine-state names: a stow-dir-root
# .stow-local-ignore does NOT apply to packages (stow only reads
# <package>/.stow-local-ignore), so this is the guardrail, not that file.
LEAK_NAMES=(auth.json gitconfig.local .DS_Store node_modules tool-output-artifacts)
check_packages() {
  local pkg f base problems=0
  for pkg in "$@"; do
    if [[ ! -d "$REPO_DIR/$pkg" ]]; then
      echo "ERROR: package '$pkg' is listed for stowing but does not exist in $REPO_DIR" >&2
      problems=1
      continue
    fi
    # A NON-dot file at the package root is the bug (~/config, ~/lazy-lock-sync).
    # Dotfiles there are correct — shell/.zshrc -> ~/.zshrc — and so are root
    # directories that mirror a real $HOME dir (latex/texmf -> ~/texmf).
    while IFS= read -r f; do
      echo "ERROR: $pkg/$(basename "$f") is a non-dot file at the package root —" >&2
      echo "       stow links it straight into \$HOME. Move it under" >&2
      echo "       $pkg/.config/<app>/ or $pkg/.local/bin/." >&2
      problems=1
    done < <(find "$REPO_DIR/$pkg" -mindepth 1 -maxdepth 1 -type f ! -name '.*' -print)
    for base in "${LEAK_NAMES[@]}"; do
      while IFS= read -r f; do
        echo "ERROR: machine-local state in the repo: ${f#"$REPO_DIR"/}" >&2
        echo "       this must never be stowed from (or committed to) a public repo." >&2
        problems=1
      done < <(find "$REPO_DIR/$pkg" -name "$base" -print)
    done
  done
  ((problems)) && return 1
  return 0
}
check_packages "${STOW_PKGS[@]}"

resolve_stow_conflicts "${STOW_PKGS[@]}"
stow --restow -t "$HOME" "${STOW_PKGS[@]}"
echo "Linked (${VARIANT}, ${TIER}): ${STOW_PKGS[*]}"

# Informational: an existing opencode install on a downgraded/low-tier machine
# is never deleted automatically — remove it manually if desired.
if [[ "$TIER" == "low" && ( -d "$HOME/.local/share/opencode" || -d "$HOME/.opencode" ) ]]; then
  echo "note: opencode is not linked on the low tier. To remove the old install:"
  echo "  rm -rf ~/.opencode ~/.local/share/opencode ~/.cache/opencode ~/.config/opencode"
fi

# --- post-stow: lazy lockfile convergence ------------------------------------
# lazy writes its lockfile to the state dir (machine-local); the repo copy
# only changes via bin/lazy-lock-sync after deliberate plugin updates.
if [[ -f "$HOME/.config/nvim/lazy-lock.json" ]]; then
  mkdir -p "$HOME/.local/state/nvim"
  cp "$HOME/.config/nvim/lazy-lock.json" "$HOME/.local/state/nvim/lazy-lock.json"
fi

# --- tpm ---------------------------------------------------------------------
TPM_INSTALL=""
for cand in "$HOME/.config/tmux/plugins/tpm/bin/install_plugins" \
            "$HOME/.config/tmux/plugins/tpm/bin/install_plugins.sh"; do
  [[ -x "$cand" ]] && { TPM_INSTALL="$cand"; break; }
done
if [[ -n "$TPM_INSTALL" ]]; then
  "$TPM_INSTALL" >/dev/null 2>&1 || echo "note: tpm plugin install failed — press prefix + I inside tmux"
else
  echo "note: tpm not found — run ./install-deps.sh, then prefix + I inside tmux"
fi

# Migration hint (informational only — never move keys automatically)
if compgen -G "$HOME/.zshrc.bak*" >/dev/null || compgen -G "$HOME/.bashrc.bak*" >/dev/null; then
  echo
  echo "hint: old rc backups detected — migrate API keys into secrets.local manually (one-time):"
  echo "  grep -hE '^(export )?[A-Z0-9_]+_(KEY|TOKEN)=' ~/.zshrc.bak ~/.bashrc.bak 2>/dev/null >> ~/.config/shell/secrets.local"
  echo "  sort -u ~/.config/shell/secrets.local -o ~/.config/shell/secrets.local && chmod 600 ~/.config/shell/secrets.local"
fi

[[ "$VARIANT" == "server" ]] && \
  echo "note: server variant linked. remaining manual steps are in the README (secrets, git identity, ssh, gmail)." || true
