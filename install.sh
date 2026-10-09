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

# Pre-creating a target dir is what forces stow to make FILE-level links
# inside it. Without it stow "tree-folds": ~/.config/btop becomes one symlink
# to btop/.config/btop IN THIS REPO, and the app then writes its runtime state
# into the working tree (btop rewrites btop.conf on every exit; opencode keeps
# state next to its config). Every stowed ~/.config/<app> dir belongs here —
# the deliberate exceptions are ~/.config/nvim (lazy writes to the state dir,
# never to the config dir) and ~/.config/karabiner (Karabiner only notices
# config changes when the DIRECTORY is the symlink, not karabiner.json — its
# automatic_backups/ are gitignored), which are folded symlinks.
mkdir -p "$HOME/.config/tmux" "$HOME/.config/ghostty" \
         "$HOME/.config/zerostack" "$HOME/.config/git" "$HOME/.config/shell" \
         "$HOME/.config/aerc" "$HOME/.local/bin" "$HOME/.local/share/aerc" \
         "$HOME/.local/state/nvim" \
         "$HOME/.config/opencode" "$HOME/.config/btop" "$HOME/.config/fastfetch" \
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
  # keyd: only app.conf is stowed. keyd-application-mapper -d writes app.log
  # next to it, so the dir is pre-created (file link, not a repo fold). The
  # system half (/etc/keyd/default.conf) is copied by install-deps.sh.
  if [[ "$(uname -s)" == "Linux" ]]; then
    STOW_PKGS+=(i3 keyd)
    mkdir -p "$HOME/.config/keyd"
  fi
  [[ "$(uname -s)" == "Darwin" ]] && STOW_PKGS+=(karabiner)
fi

# Tier downgrade: stow --restow never touches unlisted packages, so dropping
# a machine to the low tier must explicitly unstow the high-tier ones.
# (pi needs two checks: a file-level settings link or a tree-folded
# ~/.config/pi symlink — see the stow-folding footgun in AGENTS.md.)
if [[ "$TIER" == "low" ]]; then
  # An if-block, not `A && B || true`: that pattern trips SC2015, and the
  # linter on the CI runner (older than the local one) exits non-zero even on
  # info-level findings.
  if [[ -L "$HOME/.config/opencode/opencode.json" ]]; then
    stow -D -t "$HOME" opencode && echo "unstowed: opencode (low tier)"
  fi
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

# Machines set up before the mkdir list above gained these entries already
# have the folded symlink — and anything the app wrote through it is sitting in
# the repo. Unfold it so the restow below makes file-level links instead.
for folded in opencode btop fastfetch; do
  folded_link="$HOME/.config/$folded"
  if [[ -L "$folded_link" && "$(readlink "$folded_link")" == *"$(basename "$REPO_DIR")"/* ]]; then
    stow -D -t "$HOME" "$folded" 2>/dev/null || true
    rm -f "$folded_link"
    mkdir -p "$folded_link"
    echo "unfolded ~/.config/$folded (was a single symlink into the repo)"
  fi
  # Evacuate what the app wrote through the fold (opencode's npm install:
  # node_modules, package.json, ...) to the now-real dir, so it keeps working
  # and check_packages doesn't refuse the stow. Only git-IGNORED paths move —
  # tracked config stays put. Runs whenever the target is a real dir, so a run
  # that died after unfolding recovers on the next one.
  pkg_dir="$folded/.config/$folded"
  if [[ -d "$folded_link" && ! -L "$folded_link" ]] && \
     git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    while IFS= read -r -d '' rel; do
      rel="${rel%/}"
      src="$REPO_DIR/$rel" dst="$folded_link/${rel#"$pkg_dir"/}"
      if [[ -e "$dst" || -L "$dst" ]]; then
        echo "WARNING: not moving $rel — $dst already exists; remove one of them" >&2
        continue
      fi
      mkdir -p "$(dirname "$dst")"
      mv "$src" "$dst"
      echo "moved machine-local $rel -> ~${dst#"$HOME"}"
    done < <(git -C "$REPO_DIR" ls-files -z --others --ignored --exclude-standard --directory -- "$pkg_dir")
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

# --- rc drift: installer edits to the stowed shell rc files -------------------
# Installers (Homebrew, uv, rustup, conda, SDKs, ...) append to ~/.zshrc etc.
# Here those are symlinks into this PUBLIC repo, so the edit lands in the
# working tree — or the installer replaces the symlink with a real file and
# stow then backs it up. Either way the added lines are moved to the
# machine-local file (secret-looking ones to secrets.local) and the repo copy
# is restored. Every move is printed, and a reverted diff is saved as a patch.
# ~/.zprofile, ~/.zshenv, ~/.profile, ~/.bash_profile aren't stowed, so they
# are machine-local already and stay untouched.
RC_SECRET_RE='^[[:space:]]*(export[[:space:]]+)?[A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|PASSWD)[A-Za-z0-9_]*='

# rc_append LINES_FILE LOCAL_NAME SOURCE — append new lines (dedup) to
# ~/.config/shell/LOCAL_NAME, routing secret-looking lines to secrets.local.
rc_append() {
  local lines="$1" local_name="$2" src="$3" line dest n_local=0 n_secret=0
  local stamp
  stamp="# --- moved here from $src by install.sh, $(date +%Y-%m-%d) ---"
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ "$line" =~ $RC_SECRET_RE ]]; then
      dest="$HOME/.config/shell/secrets.local"
    else
      dest="$HOME/.config/shell/$local_name"
    fi
    grep -qxF -- "$line" "$dest" 2>/dev/null && continue
    if [[ "$dest" == *secrets.local ]]; then
      ((n_secret)) || printf '\n%s\n' "$stamp" >> "$dest"
      n_secret=$((n_secret + 1))
    else
      ((n_local)) || printf '\n%s\n' "$stamp" >> "$dest"
      n_local=$((n_local + 1))
      echo "    + $line"
    fi
    printf '%s\n' "$line" >> "$dest"
  done < "$lines"
  [[ -f "$HOME/.config/shell/secrets.local" ]] && chmod 600 "$HOME/.config/shell/secrets.local"
  ((n_local)) && echo "  -> $n_local line(s) moved to ~/.config/shell/$local_name"
  ((n_secret)) && echo "  -> $n_secret secret-looking line(s) moved to ~/.config/shell/secrets.local (not shown)"
  return 0
}

migrate_rc_drift() {
  local rel local_name target repo_rel tmp hist added patch total overlap
  tmp="$(mktemp -d)"
  for rel in .zshrc .bashrc .bash_aliases; do
    case "$rel" in
      .zshrc) local_name=zshrc.local ;;
      *)      local_name=bashrc.local ;;
    esac
    target="$HOME/$rel" repo_rel="shell/$rel" added="$tmp/added"
    : > "$added"
    if [[ -L "$target" ]]; then
      # 1. Appended through the symlink -> uncommitted diff in the repo.
      git -C "$REPO_DIR" diff --quiet HEAD -- "$repo_rel" 2>/dev/null && continue
      # Staged (git add) edits are deliberate repo work, never installer drift.
      if ! git -C "$REPO_DIR" diff --cached --quiet -- "$repo_rel"; then
        echo "note: $repo_rel has staged edits — treated as your own work, left alone"
        continue
      fi
      if git -C "$REPO_DIR" diff --numstat HEAD -- "$repo_rel" | awk '{ exit !($2 > 0) }'; then
        echo "note: $repo_rel has uncommitted edits that change or remove lines — looks"
        echo "      like your own work, not an installer; left alone (commit or revert it)"
        continue
      fi
      # Lines the committed file already has (e.g. a re-added PATH export)
      # are dropped: the stowed rc keeps providing them.
      git -C "$REPO_DIR" show "HEAD:$repo_rel" > "$tmp/head"
      git -C "$REPO_DIR" diff -U0 HEAD -- "$repo_rel" \
        | sed -n '/^+++ /d; s/^+//p' | { grep -vxF -f "$tmp/head" || true; } > "$added"
      patch="$HOME/.config/shell/${rel#.}.drift.$(date +%Y%m%d%H%M%S).patch"
      git -C "$REPO_DIR" diff HEAD -- "$repo_rel" > "$patch"
      echo "rc drift: lines were appended to ~/$rel (= $repo_rel in this repo):"
      rc_append "$added" "$local_name" "$HOME/$rel"
      git -C "$REPO_DIR" checkout -q HEAD -- "$repo_rel"
      echo "  -> $repo_rel restored (diff saved: $patch)"
    elif [[ -f "$target" ]]; then
      # 2. Symlink replaced by a real file. Only migrate when it is a copy of
      #    ours (most lines appear in some committed version); a foreign rc
      #    is just backed up by resolve_stow_conflicts below.
      hist="$tmp/hist"
      : > "$hist"
      local rev
      for rev in $(git -C "$REPO_DIR" log --format=%H -- "$repo_rel"); do
        git -C "$REPO_DIR" show "$rev:$repo_rel" >> "$hist" 2>/dev/null || true
      done
      cat "$REPO_DIR/$repo_rel" >> "$hist"
      total="$(grep -cv '^[[:space:]]*$' "$target" || true)"
      overlap="$(grep -v '^[[:space:]]*$' "$target" | grep -cxF -f "$hist" || true)"
      ((total > 0 && overlap * 2 >= total)) || continue
      grep -vxF -f "$hist" "$target" > "$added" || true
      [[ -s "$added" ]] || continue
      echo "rc drift: ~/$rel is a modified copy of $repo_rel, not a symlink:"
      rc_append "$added" "$local_name" "$HOME/$rel"
    fi
  done
  rm -rf "$tmp"
}
migrate_rc_drift
# Karabiner writes a real ~/.config/karabiner on first launch. Left in place,
# stow would link karabiner.json INSIDE it — a file link Karabiner never
# watches. Move it aside so stow folds the whole dir (see the mkdir note).
KARABINER_DIR="$HOME/.config/karabiner"
if [[ " ${STOW_PKGS[*]} " == *" karabiner "* && -d "$KARABINER_DIR" && ! -L "$KARABINER_DIR" ]]; then
  bak="$KARABINER_DIR.bak.$(date +%Y%m%d%H%M%S)"
  mv "$KARABINER_DIR" "$bak"
  echo "backed up: $KARABINER_DIR -> $bak (replaced by the repo's karabiner config)"
fi

resolve_stow_conflicts "${STOW_PKGS[@]}"
stow --restow -t "$HOME" "${STOW_PKGS[@]}"
echo "Linked (${VARIANT}, ${TIER}): ${STOW_PKGS[*]}"

# Karabiner only starts watching a moved/relinked config after its console
# user server restarts. No-op (and harmless) when Karabiner isn't running yet.
if [[ -L "$KARABINER_DIR" ]]; then
  launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.agent.Karabiner-Console-User-Server" \
    >/dev/null 2>&1 || true
fi

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

if [[ "$VARIANT" == "server" ]]; then
  echo "note: server variant linked. remaining manual steps are in the README (secrets, git identity, ssh, gmail)."
fi
