#!/usr/bin/env bash
# Remove Apple's preinstalled optional apps (iMovie, GarageBand, Keynote,
# Pages, Numbers) plus GarageBand/Logic's multi-GB sound library: Apple Loops,
# instruments, impulse responses and their install receipts. install-deps.sh
# runs it with --apply on every Mac (and without it under --check). Run by
# hand it is a dry run: it lists what it would delete and how big it is;
# --apply deletes (sudo for /Applications and /Library, asked only when
# something is actually there — reruns on a clean Mac never prompt).
#
# Kept on purpose:
#   - Your own documents: ~/Movies/iMovie Library, ~/Music/GarageBand,
#     iWork files in iCloud Drive/Documents.
#   - The shared sound library (/Library/Application Support/Logic, Apple
#     Loops, ...) when Logic Pro or MainStage is installed — they use it too.
#     Pass --include-shared to delete it anyway.
#   - Apple TV (and Music, Chess, ...): they live on the sealed, read-only system
#     volume and cannot be deleted (only hidden from the Dock).
# Reinstall any of them from the App Store; GarageBand re-downloads its
# sounds on first launch.
#
# Usage:
#   ./macos-remove-apps.sh                   # dry run: list + sizes
#   ./macos-remove-apps.sh --apply           # delete
#   ./macos-remove-apps.sh --apply --include-shared

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macos-remove-apps.sh: macOS only" >&2
  exit 1
fi

APPLY=0 SHARED=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --include-shared) SHARED=1 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

APPS=(
  "/Applications/iMovie.app"
  "/Applications/GarageBand.app"
  "/Applications/Keynote.app"
  "/Applications/Pages.app"
  "/Applications/Numbers.app"
)

# Per-user app state (prefs, caches, sandbox containers) — no documents.
USER_DATA=(
  "$HOME/Library/Containers/com.apple.iMovieApp"
  "$HOME/Library/Containers/com.apple.garageband10"
  "$HOME/Library/Containers/com.apple.iWork.Keynote"
  "$HOME/Library/Containers/com.apple.iWork.Pages"
  "$HOME/Library/Containers/com.apple.iWork.Numbers"
  "$HOME/Library/Application Scripts/com.apple.iMovieApp"
  "$HOME/Library/Application Scripts/com.apple.garageband10"
  "$HOME/Library/Application Scripts/com.apple.iWork.Keynote"
  "$HOME/Library/Application Scripts/com.apple.iWork.Pages"
  "$HOME/Library/Application Scripts/com.apple.iWork.Numbers"
  "$HOME/Library/Application Support/GarageBand"
  "$HOME/Library/Caches/com.apple.garageband10"
  "$HOME/Library/Preferences/com.apple.garageband10.plist"
)

# GarageBand-only content.
GARAGEBAND_DATA=(
  "/Library/Application Support/GarageBand"
)

# Sound library shared by GarageBand, Logic Pro and MainStage.
SHARED_DATA=(
  "/Library/Application Support/Logic"
  "/Library/Audio/Apple Loops"
  "/Library/Audio/Apple Loops Index"
  "/Library/Audio/Impulse Responses/Apple"
)

if ((!SHARED)); then
  for pro in "/Applications/Logic Pro.app" "/Applications/Logic Pro X.app" \
             "/Applications/MainStage.app" "/Applications/MainStage 3.app"; do
    if [[ -d "$pro" ]]; then
      echo "note: ${pro##*/} is installed — keeping the shared sound library (--include-shared to delete it)"
      SHARED_DATA=()
      break
    fi
  done
fi

total_kb=0 found=0

# remove PATH [sudo] — print the path and size; delete it with --apply.
remove() {
  local path="$1" use_sudo="${2:-}" kb
  [[ -e "$path" || -L "$path" ]] || return 0
  kb="$(du -sk "$path" 2>/dev/null | awk '{print $1}')"
  kb="${kb:-0}"
  total_kb=$((total_kb + kb))
  found=$((found + 1))
  printf '%8s MB  %s\n' "$((kb / 1024))" "$path"
  ((APPLY)) || return 0
  if [[ -n "$use_sudo" ]]; then
    sudo rm -rf -- "$path"
  else
    rm -rf -- "$path"
  fi
}

for p in "${APPS[@]}" "${GARAGEBAND_DATA[@]}" ${SHARED_DATA[@]+"${SHARED_DATA[@]}"}; do
  remove "$p" sudo
done
for p in "${USER_DATA[@]}"; do
  remove "$p"
done

# Install receipts for the sound-library packages (MAContent10_*) and the
# apps, so softwareupdate/App Store stop treating them as installed. Shared
# content receipts stay when the shared library is kept.
pkg_re='^com\.apple\.pkg\.(GarageBand|iMovie|Keynote|Pages|Numbers)'
((${#SHARED_DATA[@]})) && pkg_re="$pkg_re|^com\.apple\.pkg\.MAContent10_"
receipts=()
while IFS= read -r pkg; do
  receipts+=("$pkg")
done < <(pkgutil --pkgs 2>/dev/null | grep -E "$pkg_re" || true)
if ((${#receipts[@]})); then
  echo "receipts: ${#receipts[@]} package receipt(s) to forget"
  if ((APPLY)); then
    for pkg in "${receipts[@]}"; do
      sudo pkgutil --forget "$pkg" >/dev/null
    done
  fi
fi

if ((!APPLY)) && [[ -d /System/Applications/TV.app ]]; then
  echo "skip: /System/Applications/TV.app (sealed system volume — remove it from the Dock instead)"
fi

if ((found == 0 && ${#receipts[@]} == 0)); then
  echo "nothing to remove"
elif ((APPLY)); then
  echo "removed $found item(s), $((total_kb / 1024)) MB freed"
else
  echo "dry run: $found item(s), $((total_kb / 1024)) MB — rerun with --apply to delete"
fi
