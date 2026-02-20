#!/usr/bin/env bash
# =============================================================================
# install-goldberg.sh — Install Goldberg Steam Emulator for AoE2 HD
#
# Downloads gbe_fork (active Goldberg fork) and replaces steam_api.dll
# in the AoE2 HD game directory so the game launches without Steam DRM.
#
# Run this ONCE before launching the game.
# =============================================================================
set -eo pipefail

# --- Config ------------------------------------------------------------------
RELEASE_TAG="release-2026_02_19"
DOWNLOAD_URL="https://github.com/Detanup01/gbe_fork/releases/download/${RELEASE_TAG}/emu-win-release.7z"
APP_ID="221380"
GAME_DIR="$HOME/win-compat/prefixes/aoe2/drive_c/Program Files (x86)/Steam/steamapps/common/age2hd"
WORK_DIR="$HOME/win-compat/installers/goldberg"
LOG="$HOME/win-compat/logs/goldberg_install_$(date '+%Y%m%d_%H%M%S').log"
# -----------------------------------------------------------------------------

mkdir -p "$HOME/win-compat/logs"
exec > >(tee -a "$LOG") 2>&1

echo "============================================================"
echo " Goldberg Steam Emulator — installer"
echo " $(date)"
echo " Release : $RELEASE_TAG"
echo " Game    : $GAME_DIR"
echo " Log     : $LOG"
echo "============================================================"

# ── 1. Preflight checks ──────────────────────────────────────────────────────
if [[ ! -d "$GAME_DIR" ]]; then
  echo "[ERROR] Game directory not found:"
  echo "        $GAME_DIR"
  echo "        Run steam-install.sh first."
  exit 1
fi

# Find 7z / 7za (brew install p7zip  →  provides 7za)
_7Z=""
for cmd in 7z 7za; do
  if command -v "$cmd" &>/dev/null; then
    _7Z="$cmd"
    break
  fi
done
if [[ -z "$_7Z" ]]; then
  echo "[INFO] p7zip not found — installing via Homebrew..."
  brew install p7zip
  _7Z=7za
fi
echo "[OK] Using: $($_7Z i 2>/dev/null | head -1 || echo "$_7Z")"

# ── 2. Download ───────────────────────────────────────────────────────────────
ARCHIVE="$WORK_DIR/emu-win-release.7z"
mkdir -p "$WORK_DIR"

if [[ -f "$ARCHIVE" ]]; then
  FSIZE=$(stat -f%z "$ARCHIVE" 2>/dev/null || stat -c%s "$ARCHIVE" 2>/dev/null || echo 0)
  if [[ "$FSIZE" -gt 1000000 ]]; then
    echo "[SKIP] Archive already downloaded ($FSIZE bytes): $ARCHIVE"
  else
    echo "[WARN] Stale archive ($FSIZE bytes) — re-downloading..."
    rm -f "$ARCHIVE"
  fi
fi

if [[ ! -f "$ARCHIVE" ]]; then
  echo "[INFO] Downloading: $DOWNLOAD_URL"
  curl -L --progress-bar --max-time 120 -o "$ARCHIVE" "$DOWNLOAD_URL"
  FSIZE=$(stat -f%z "$ARCHIVE" 2>/dev/null || stat -c%s "$ARCHIVE" 2>/dev/null || echo 0)
  echo "[OK] Downloaded $FSIZE bytes → $ARCHIVE"
fi

# ── 3. Extract ────────────────────────────────────────────────────────────────
EXTRACT_DIR="$WORK_DIR/extracted"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
echo "[INFO] Extracting archive..."
"$_7Z" x "$ARCHIVE" -o"$EXTRACT_DIR" -y > /dev/null
echo "[OK] Extracted to: $EXTRACT_DIR"

# ── 4. Find the right steam_api.dll (must be 32-bit PE32, not PE32+) ─────────
echo "[INFO] Scanning for steam_api.dll candidates..."
# bash 3.2 compatible — no mapfile
CHOSEN_DLL=""
FOUND_ANY=0
while IFS= read -r dll; do
  FOUND_ANY=1
  FILE_INFO=$(file "$dll" 2>/dev/null || echo "unknown")
  echo "  Found: $dll"
  echo "         $FILE_INFO"
  # Prefer PE32 (32-bit) — skip PE32+ (64-bit)
  if echo "$FILE_INFO" | grep -q "PE32[^+]"; then
    CHOSEN_DLL="$dll"
    echo "  ✓ Selected (PE32 / 32-bit)"
    break
  fi
done < <(find "$EXTRACT_DIR" -iname "steam_api.dll" 2>/dev/null)

if [[ "$FOUND_ANY" -eq 0 ]]; then
  echo "[ERROR] No steam_api.dll found in archive!"
  echo "        Contents of extract dir:"
  find "$EXTRACT_DIR" | head -40
  exit 1
fi

# Fallback: take any file literally named steam_api.dll (not steam_api64.dll)
if [[ -z "$CHOSEN_DLL" ]]; then
  while IFS= read -r dll; do
    if [[ "$(basename "$dll")" == "steam_api.dll" ]]; then
      CHOSEN_DLL="$dll"
      echo "  ✓ Fallback selected: $dll"
      break
    fi
  done < <(find "$EXTRACT_DIR" -iname "steam_api.dll" 2>/dev/null)
fi

if [[ -z "$CHOSEN_DLL" ]]; then
  echo "[ERROR] Could not find a suitable 32-bit steam_api.dll"
  exit 1
fi

echo "[OK] Using DLL: $CHOSEN_DLL"

# ── 5. Backup original steam_api.dll ─────────────────────────────────────────
ORIG="$GAME_DIR/steam_api.dll"
BACKUP="$GAME_DIR/steam_api.dll.original"

if [[ -f "$ORIG" && ! -f "$BACKUP" ]]; then
  cp "$ORIG" "$BACKUP"
  echo "[OK] Backed up original: $BACKUP"
elif [[ -f "$BACKUP" ]]; then
  echo "[SKIP] Backup already exists: $BACKUP"
fi

# ── 6. Install Goldberg steam_api.dll ─────────────────────────────────────────
cp "$CHOSEN_DLL" "$ORIG"
echo "[OK] Installed Goldberg steam_api.dll → $ORIG"

# ── 7. steam_appid.txt ────────────────────────────────────────────────────────
APPID_FILE="$GAME_DIR/steam_appid.txt"
echo "$APP_ID" > "$APPID_FILE"
echo "[OK] Written: $APPID_FILE (app id: $APP_ID)"

# ── 8. steam_settings directory ───────────────────────────────────────────────
# Goldberg reads settings from steam_settings/ next to the EXE
SETTINGS_DIR="$GAME_DIR/steam_settings"
mkdir -p "$SETTINGS_DIR"

# steam_interfaces.txt — tells Goldberg which Steam interface versions to expose.
# For AoE2 HD (2013, SDK ~1.28) these are the correct interface strings.
# If the game crashes at startup, run generate_interfaces.exe from the
# extracted archive against the original steam_api.dll to regenerate.
IFACE_FILE="$SETTINGS_DIR/steam_interfaces.txt"
if [[ ! -f "$IFACE_FILE" ]]; then
  cat > "$IFACE_FILE" <<'EOF'
SteamClient012
SteamGameServer012
SteamGameServerStats001
SteamUser017
SteamFriends014
SteamUtils007
SteamMatchMaking009
SteamMatchMakingServers002
STEAMUSERSTATS_INTERFACE_VERSION011
SteamApps006
SteamNetworking005
SteamRemoteStorage013
SteamScreenshots002
SteamHTTP002
SteamUnifiedMessages001
STEAMCONTROLLER_INTERFACE_VERSION
SteamUGC007
SteamAppList001
SteamMusic001
SteamMusicRemote001
SteamHTMLSurface003
SteamInventory001
SteamVideo001
EOF
  echo "[OK] Written: $IFACE_FILE"
else
  echo "[SKIP] $IFACE_FILE already exists"
fi

# copy generate_interfaces.exe to game dir for future use
GEN_SRC=$(find "$EXTRACT_DIR" -iname "generate_interfaces*" 2>/dev/null | head -1)
if [[ -n "$GEN_SRC" ]]; then
  cp "$GEN_SRC" "$GAME_DIR/" 2>/dev/null || true
  echo "[OK] Copied generate_interfaces tool → $GAME_DIR/"
fi

echo ""
echo "============================================================"
echo " Goldberg installation COMPLETE"
echo "============================================================"
echo " Game dir : $GAME_DIR"
echo " DLL      : Goldberg steam_api.dll (32-bit)"
echo " App ID   : $APP_ID (steam_appid.txt)"
echo " Settings : $SETTINGS_DIR/"
echo ""
echo " NEXT STEP — launch the game:"
echo ""
echo '   ~/win-compat/scripts/winrun aoe2 \
     "C:/Program Files (x86)/Steam/steamapps/common/age2hd/AoK HD.exe"'
echo ""
echo " If the game crashes immediately, re-run generate_interfaces:"
echo '   ~/win-compat/scripts/winrun aoe2 \
     "C:/Program Files (x86)/Steam/steamapps/common/age2hd/generate_interfaces.exe" \
     "C:/Program Files (x86)/Steam/steamapps/common/age2hd/AoK HD.exe"'
echo "============================================================"
