#!/usr/bin/env bash
# macOS system preferences (`defaults write`) — opt-in, NOT run by install.sh:
# these are per-user UI choices, not config files, so they are applied
# deliberately. Idempotent: only keys that differ are written, and each change
# is printed. No sudo, nothing machine-identifying (hostname, locale, ...).
#
# Curated from the mathiasbynens/webpro lineage; skipped on purpose: anything
# that weakens security (LSQuarantine, disk-image verification), keys that
# are no-ops on current macOS / Apple Silicon (pmset sms, askForPassword*),
# and personal layout choices (Dock autohide, trackpad gestures).
#
# Usage:
#   ./macos-defaults.sh          # apply, then restart Finder/Dock/SystemUIServer
#   ./macos-defaults.sh --check  # report drift only; exit 1 if anything differs
#
# Key repeat changes need a logout to take effect.

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macos-defaults.sh: macOS only" >&2
  exit 1
fi

CHECK=0
case "${1:-}" in
  --check) CHECK=1 ;;
  -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

changed=0

# want DOMAIN KEY TYPE VALUE — TYPE is a `defaults write` type flag without
# the dash (bool|int|string). `defaults read` prints bools as 1/0.
want() {
  local domain="$1" key="$2" type="$3" value="$4" expected current
  expected="$value"
  if [[ "$type" == bool ]]; then
    [[ "$value" == true ]] && expected=1 || expected=0
  fi
  current="$(defaults read "$domain" "$key" 2>/dev/null || echo "<unset>")"
  [[ "$current" == "$expected" ]] && return 0
  changed=$((changed + 1))
  if ((CHECK)); then
    echo "drift: $domain $key = $current (want $expected)"
  else
    defaults write "$domain" "$key" "-$type" "$value"
    echo "set:   $domain $key = $expected (was $current)"
  fi
}

# --- Keyboard & input ---------------------------------------------------------
# Fast key repeat, and hold-to-repeat instead of the accent popup (hjkl in nvim).
want NSGlobalDomain KeyRepeat int 2
want NSGlobalDomain InitialKeyRepeat int 15
want NSGlobalDomain ApplePressAndHoldEnabled bool false
# No smart quotes/dashes or auto-correct — they mangle code and shell commands.
want NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled bool false
want NSGlobalDomain NSAutomaticDashSubstitutionEnabled bool false
want NSGlobalDomain NSAutomaticSpellingCorrectionEnabled bool false

# --- Dialogs ------------------------------------------------------------------
# Expanded save/print panels; new documents save to disk, not iCloud.
want NSGlobalDomain NSNavPanelExpandedStateForSaveMode bool true
want NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 bool true
want NSGlobalDomain PMPrintingExpandedStateForPrint bool true
want NSGlobalDomain PMPrintingExpandedStateForPrint2 bool true
want NSGlobalDomain NSDocumentSaveNewDocumentsToCloud bool false

# --- Finder -------------------------------------------------------------------
want NSGlobalDomain AppleShowAllExtensions bool true
want com.apple.finder ShowPathbar bool true
want com.apple.finder ShowStatusBar bool true
want com.apple.finder _FXShowPosixPathInTitle bool true
want com.apple.finder _FXSortFoldersFirst bool true
# Search the current folder, not "This Mac".
want com.apple.finder FXDefaultSearchScope string SCcf
# No .DS_Store litter on network shares and USB drives.
want com.apple.desktopservices DSDontWriteNetworkStores bool true
want com.apple.desktopservices DSDontWriteUSBStores bool true

# --- Screenshots --------------------------------------------------------------
((CHECK)) || mkdir -p "$HOME/Screenshots"
want com.apple.screencapture location string "$HOME/Screenshots"
want com.apple.screencapture disable-shadow bool true

# --- Dock / Spaces ------------------------------------------------------------
want com.apple.dock show-recents bool false
want com.apple.dock launchanim bool false
# Keep Spaces in a fixed order instead of reordering by most recent use.
want com.apple.dock mru-spaces bool false

# --- Apply --------------------------------------------------------------------
if ((CHECK)); then
  ((changed)) && { echo "$changed setting(s) differ — run ./macos-defaults.sh to apply"; exit 1; }
  echo "all settings match"
  exit 0
fi
if ((changed)); then
  killall Finder Dock SystemUIServer >/dev/null 2>&1 || true
  echo "$changed setting(s) changed. Log out and back in for key repeat to apply."
else
  echo "all settings already match"
fi
