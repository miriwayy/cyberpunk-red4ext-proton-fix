#!/usr/bin/env bash
# Fix "RED4ext (error 998)" for Cyberpunk 2077 on Linux (Steam + Proton).
#
#  1. Updates the Visual C++ runtime inside the game's Proton prefix
#     (the prefix ships 14.28 from 2020; RED4ext needs 14.40+).
#  2. Optionally (--red4ext-dev) installs the latest RED4ext build from the
#     official GitHub CI, for game patches not yet covered by a release.
#
# Usage: ./fix-red4ext-proton.sh [--red4ext-dev]
set -euo pipefail

APPID=1091500
VC_URL="https://aka.ms/vs/17/release/vc_redist.x64.exe"
RED4EXT_REPO="WopsS/RED4ext"
MIN_VC_MAJOR=14
MIN_VC_MINOR=40

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

INSTALL_DEV=0
for arg in "$@"; do
    case "$arg" in
        --red4ext-dev) INSTALL_DEV=1 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unknown option: $arg" ;;
    esac
done

command -v protontricks >/dev/null || die "protontricks is required (e.g. 'sudo dnf install protontricks' or 'flatpak install com.github.Matoking.protontricks')."
command -v curl >/dev/null || die "curl is required."
command -v unzip >/dev/null || die "unzip is required."

# --- Locate the game and its Proton prefix across all Steam libraries ---
STEAM_ROOT=""
for d in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [[ -f "$d/steamapps/libraryfolders.vdf" ]] && { STEAM_ROOT="$d"; break; }
done
[[ -n "$STEAM_ROOT" ]] || die "Steam installation not found."

LIBRARY=""
while IFS= read -r lib; do
    if [[ -f "$lib/steamapps/appmanifest_$APPID.acf" ]]; then LIBRARY="$lib"; break; fi
done < <(grep -E '^\s*"path"' "$STEAM_ROOT/steamapps/libraryfolders.vdf" | sed -E 's/.*"path"\s*"([^"]+)".*/\1/')
[[ -n "$LIBRARY" ]] || die "Cyberpunk 2077 is not installed in any Steam library."

GAME_DIR="$LIBRARY/steamapps/common/Cyberpunk 2077"
SYS32="$LIBRARY/steamapps/compatdata/$APPID/pfx/drive_c/windows/system32"
info "Game: $GAME_DIR"
[[ -d "$SYS32" ]] || die "Proton prefix not found. Launch the game once, then re-run this script."

if pgrep -f 'x64\\Cyberpunk2077\.exe' >/dev/null; then
    die "Cyberpunk 2077 is running. Close it first."
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- 1. Visual C++ runtime ---
vc_version() {
    strings -el "$SYS32/msvcp140.dll" 2>/dev/null | grep -A1 '^FileVersion$' | tail -1 | awk '{print $1}'
}

current=$(vc_version || true)
major=${current%%.*}
rest=${current#*.}
minor=${rest%%.*}
if [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] &&
   (( major > MIN_VC_MAJOR || (major == MIN_VC_MAJOR && minor >= MIN_VC_MINOR) )); then
    info "Visual C++ runtime is already up to date ($current)."
else
    info "Visual C++ runtime in the prefix: ${current:-unknown}. Installing the latest one..."
    curl -fsSL -o "$TMP/vc_redist.x64.exe" "$VC_URL"
    VC="$TMP/vc_redist.x64.exe" protontricks -c 'wine "$VC" /install /quiet /norestart' $APPID >/dev/null 2>&1 || true
    current=$(vc_version || true)
    info "Visual C++ runtime is now: ${current:-unknown}"
fi

# --- 2. RED4ext development build (optional) ---
if [[ $INSTALL_DEV -eq 1 ]]; then
    info "Looking up the latest successful RED4ext CI build on master..."
    run_id=$(curl -fsSL "https://api.github.com/repos/$RED4EXT_REPO/actions/workflows/cpp-build.yml/runs?branch=master&status=success&per_page=1" \
        | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["workflow_runs"][0]["id"])')
    artifact=$(curl -fsSL "https://api.github.com/repos/$RED4EXT_REPO/actions/runs/$run_id/artifacts" \
        | python3 -I -c 'import json,sys; print(next(a["name"] for a in json.load(sys.stdin)["artifacts"] if a["name"].startswith("red4ext-release-") and not a["expired"]))')
    info "Downloading $artifact (run $run_id) via nightly.link..."
    curl -fsSL -o "$TMP/red4ext.zip" "https://nightly.link/$RED4EXT_REPO/actions/runs/$run_id/$artifact.zip"
    unzip -q "$TMP/red4ext.zip" -d "$TMP/red4ext"

    backup="$GAME_DIR/red4ext-backup-$(date +%Y%m%d-%H%M%S)"
    if [[ -f "$GAME_DIR/red4ext/RED4ext.dll" ]]; then
        mkdir -p "$backup"
        cp "$GAME_DIR/bin/x64/winmm.dll" "$GAME_DIR/red4ext/RED4ext.dll" "$backup/" 2>/dev/null || true
        info "Previous RED4ext backed up to: $backup"
    fi
    mkdir -p "$GAME_DIR/bin/x64" "$GAME_DIR/red4ext"
    cp "$TMP/red4ext/bin/x64/winmm.dll" "$GAME_DIR/bin/x64/"
    cp "$TMP/red4ext/red4ext/RED4ext.dll" "$TMP/red4ext/red4ext/LICENSE.txt" "$TMP/red4ext/red4ext/THIRD_PARTY_LICENSES.txt" "$GAME_DIR/red4ext/"
    info "RED4ext development build installed."
fi

# --- Launch options reminder ---
if ! grep -rqs 'winmm=n,b' "$STEAM_ROOT"/userdata/*/config/localconfig.vdf; then
    warn "Set the game's Steam launch options to:"
    echo '    WINEDLLOVERRIDES="winmm=n,b" %command%'
fi

info "Done. Launch the game; RED4ext logs are in: $GAME_DIR/red4ext/logs"
