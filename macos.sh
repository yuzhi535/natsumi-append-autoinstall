#!/usr/bin/env bash
#
# Reapply Natsumi Append (fx-autoconfig) after a Firefox update.
# macOS only. Natsumi Browser must already be installed in the profile.
set -euo pipefail

REPO="greeeen-dev/fx-autoconfig"
REF="${FX_AUTOCONFIG_REF:-master}"
APP="${FIREFOX_APP:-/Applications/Firefox.app}"
PROFILE="${NATSUMI_PROFILE:-}"
DRY_RUN=0
KEEP_TEMP=0

usage() {
  cat <<'EOF'
Usage: macos.sh [options]

Options:
  --profile PATH   Firefox profile directory (default: newest *.default-release)
  --firefox PATH   Firefox.app path (default: /Applications/Firefox.app)
  --dry-run        Print actions without changing files
  --keep-temp      Keep the downloaded fx-autoconfig files
  -h, --help       Show this help
EOF
}

section() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

newest_profile() {
  local root="$1"
  local pattern="$2"
  find "$root" -maxdepth 1 -type d -name "$pattern" -print0 2>/dev/null |
    while IFS= read -r -d '' p; do
      printf '%s\t%s\n' "$(stat -f %m "$p")" "$p"
    done |
    sort -rn |
    head -n 1 |
    cut -f 2-
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || die "Missing value for --profile"
      PROFILE="$2"
      shift 2
      ;;
    --firefox)
      [[ $# -ge 2 ]] || die "Missing value for --firefox"
      APP="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --keep-temp)
      KEEP_TEMP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS."

if [[ ! -d "$APP" && -d "$HOME/Applications/Firefox.app" ]]; then
  APP="$HOME/Applications/Firefox.app"
fi
[[ -d "$APP" ]] || die "Firefox.app not found. Use --firefox /path/to/Firefox.app."

RES="$APP/Contents/Resources"
[[ -d "$RES" ]] || die "Firefox resources folder not found: $RES"

if [[ "$DRY_RUN" -eq 0 ]] && pgrep -x firefox >/dev/null 2>&1; then
  die "Firefox is running. Quit Firefox, then run this script again."
fi

PROFILE_ROOT="$HOME/Library/Application Support/Firefox/Profiles"
[[ -d "$PROFILE_ROOT" ]] || die "Firefox profiles folder not found: $PROFILE_ROOT"

if [[ -z "$PROFILE" ]]; then
  PROFILE="$(newest_profile "$PROFILE_ROOT" '*.default-release')"
fi
if [[ -z "$PROFILE" ]]; then
  PROFILE="$(newest_profile "$PROFILE_ROOT" '*.default*')"
fi
if [[ -n "$PROFILE" && ! -d "$PROFILE" ]]; then
  PROFILE="$PROFILE_ROOT/$PROFILE"
fi
[[ -n "$PROFILE" && -d "$PROFILE" ]] || die "No Firefox profile found in $PROFILE_ROOT."

CHROME="$PROFILE/chrome"
[[ -f "$CHROME/natsumi/natsumi.css" ]] || \
  die "Natsumi Browser is not installed in this profile. Install Natsumi CSS-only first."

TMP="$(mktemp -d "${TMPDIR:-/tmp}/natsumi-append.XXXXXX")"
cleanup() {
  [[ "$KEEP_TEMP" -eq 1 ]] || rm -rf "$TMP"
}
trap cleanup EXIT

section "Downloading fx-autoconfig ($REF)"
if [[ -n "${FX_AUTOCONFIG_ZIP:-}" ]]; then
  ZIP="$FX_AUTOCONFIG_ZIP"
  [[ -f "$ZIP" ]] || die "FX_AUTOCONFIG_ZIP does not exist: $ZIP"
else
  ZIP="$TMP/fx-autoconfig.zip"
  curl -fsSL --http1.1 --retry 3 --connect-timeout 20 \
    "https://github.com/$REPO/archive/refs/heads/$REF.zip" -o "$ZIP"
fi
unzip -q "$ZIP" -d "$TMP"

SRC="$(find "$TMP" -maxdepth 1 -type d -name 'fx-autoconfig-*' -print -quit)"
[[ -n "$SRC" && -d "$SRC" ]] || die "Could not unpack fx-autoconfig."

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$PROFILE/natsumi-append-backups/$STAMP"
if [[ "$DRY_RUN" -eq 0 ]]; then
  mkdir -p "$BACKUP"
fi

backup_file() {
  local src="$1" name="$2"
  [[ -f "$src" ]] || return 0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would back up $src"
  else
    cp "$src" "$BACKUP/$name"
  fi
}

backup_dir() {
  local src="$1" name="$2"
  [[ -d "$src" ]] || return 0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would back up $src"
  else
    cp -R "$src" "$BACKUP/$name"
  fi
}

backup_file "$RES/config.js" "config.js"
backup_dir "$RES/defaults" "defaults"
backup_dir "$CHROME/utils" "chrome-utils"
backup_dir "$CHROME/CSS" "chrome-CSS"
backup_dir "$CHROME/resources" "chrome-resources"

SUDO=()
if [[ ! -w "$RES" ]]; then
  SUDO=(sudo)
  section "Administrator permission is required for $RES"
  "${SUDO[@]}" -v
fi

run_priv() {
  if [[ ${#SUDO[@]} -gt 0 ]]; then
    "${SUDO[@]}" "$@"
  else
    "$@"
  fi
}

copy_priv_file() {
  local src="$1" dest="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would copy $src -> $dest"
  else
    run_priv mkdir -p "$(dirname "$dest")"
    run_priv cp "$src" "$dest"
  fi
}

copy_tree() {
  local src="$1" dest="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "would copy contents of $src -> $dest"
  else
    mkdir -p "$dest"
    cp -R "$src/." "$dest/"
  fi
}

section "Installing Firefox program files"
copy_priv_file "$SRC/program/config.js" "$RES/config.js"
copy_priv_file "$SRC/program/defaults/pref/config-prefs.js" "$RES/defaults/pref/config-prefs.js"

section "Installing fx-autoconfig profile files"
copy_tree "$SRC/profile/chrome/CSS" "$CHROME/CSS"
copy_tree "$SRC/profile/chrome/utils" "$CHROME/utils"
copy_tree "$SRC/profile/chrome/resources" "$CHROME/resources"

MANIFEST="$CHROME/utils/chrome.manifest"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "would write $MANIFEST"
else
  cat > "$MANIFEST" <<'EOF'
content userchromejs ./
content userscripts ../natsumi/scripts/
skin userstyles classic/1.0 ../CSS/
content userchrome ../resources/
content natsumi ../natsumi/
content natsumi-icons ../natsumi/icons/
EOF
fi

USER_JS="$PROFILE/user.js"
PREF='user_pref("userChromeJS.persistent_domcontent_callback", true);'
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "would ensure the persistent_domcontent_callback pref in $USER_JS"
else
  if [[ -f "$USER_JS" ]]; then
    if ! grep -q 'userChromeJS.persistent_domcontent_callback.*true' "$USER_JS"; then
      printf '\n%s\n' "$PREF" >> "$USER_JS"
    fi
  else
    printf '%s\n' "$PREF" > "$USER_JS"
  fi
fi

CACHE_DIR="$HOME/Library/Caches/Firefox/Profiles/$(basename "$PROFILE")/startupCache"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "would clear $CACHE_DIR"
else
  rm -rf "$CACHE_DIR" "$PROFILE/startupCache"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  for f in \
    "$RES/config.js" \
    "$RES/defaults/pref/config-prefs.js" \
    "$CHROME/utils/boot.sys.mjs" \
    "$CHROME/utils/module_loader.mjs" \
    "$CHROME/utils/chrome.manifest"; do
    [[ -f "$f" ]] || die "Missing $f after install."
  done
fi

section "Done"
echo "Profile: $PROFILE"
echo "Backup:  $BACKUP"
echo "Start Firefox. If the Natsumi settings page is missing, clear the startup cache from about:support and restart."
