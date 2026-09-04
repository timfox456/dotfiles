#!/usr/bin/env bash
# Dotfiles installer — stows every package to $HOME.
#
# Usage:
#   ./install.sh             # variant autodetected: macOS/Linux-desktop = desktop,
#                            # headless Linux (no DISPLAY) = server
#   ./install.sh --server    # force server variant (tmux prefix C-a)
#   ./install.sh --desktop   # force desktop variant (tmux prefix C-b, i3 on Linux)
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
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

mkdir -p "$HOME/.config/tmux" "$HOME/.config/ghostty" "$HOME/.config/opencode" \
         "$HOME/.config/zerostack" "$HOME/.config/git" "$HOME/.config/shell" \
         "$HOME/.config/aerc" "$HOME/.local/bin" "$HOME/.local/share/aerc" \
         "$HOME/.local/state/nvim"

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
  local round target resolved owner bak
  local -a targets
  for round in 1 2 3 4 5; do
    targets=()
    # stow reports each conflict TWICE (CONFLICT line + target line) with
    # version-dependent formats — extract the path, then dedup (sort -u):
    #   variant links (2.3.x/2.4.x): "... stowed to a different package: P => Q"
    #   2.4.x real files: "CONFLICT when stowing pkg: ... over existing target P since ..."
    #   2.3.x real files: "  * existing target is neither a link nor a directory: P"
    # Case order matters: the greedy-colon fallback must stay LAST and narrowed
    # to "neither", or it matches the 2.4 CONFLICT line and produces garbage.
    while IFS= read -r target; do
      [[ -z "$target" ]] && continue
      targets+=("$target")
    done < <(stow -n -t "$HOME" -v 2 "$@" 2>&1 \
      | grep -E "existing target" \
      | sed -E '
          s/.*stowed to a different package:[[:space:]]*([^[:space:]]*).*/\1/; t
          s/.*over existing target[[:space:]]+//; t
          s/.*existing target is neither a link nor a directory:[[:space:]]*//
        ' | sort -u || true)
    ((${#targets[@]})) || return 0

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
  done
  echo "ERROR: stow conflicts persist after $round rounds — resolve manually" >&2
  return 1
}

# --- variant selection -------------------------------------------------------
# --server / --desktop force it. Otherwise: macOS is always a desktop, and
# Linux autodetects headless via DISPLAY (servers have none).
VARIANT=""
for arg in "$@"; do
  case "$arg" in
    --server)  VARIANT="server" ;;
    --desktop) VARIANT="desktop" ;;
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

STOW_PKGS=(tmux-common ghostty opencode zerostack git shell bin aerc nvim)
if [[ "$VARIANT" == "server" ]]; then
  STOW_PKGS+=(tmux-server)
else
  STOW_PKGS+=(tmux)
  [[ "$(uname -s)" == "Linux" ]] && STOW_PKGS+=(i3)
fi

resolve_stow_conflicts "${STOW_PKGS[@]}"
stow --restow -t "$HOME" "${STOW_PKGS[@]}"
echo "Linked (${VARIANT}): ${STOW_PKGS[*]}"

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

[[ "${1:-}" == "--server" ]] && \
  echo "note: server variant linked. remaining manual steps are in the README (secrets, git identity, ssh, gmail)." || true
