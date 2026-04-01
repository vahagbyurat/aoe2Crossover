#!/usr/bin/env bash
# =============================================================================
# launch-aoe2-goldberg.sh — Launch AoE2 HD directly via Goldberg emulator
#
# Requires install-goldberg.sh to have been run first.
# Does NOT require Steam running — Goldberg handles the Steam DRM stub.
#
# Usage: bash ~/win-compat/scripts/launch-aoe2-goldberg.sh
# =============================================================================
set -eo pipefail

LOGDIR="$HOME/win-compat/logs"
LOGFILE="$LOGDIR/aoe2_goldberg_$(date '+%Y%m%d_%H%M%S').log"
mkdir -p "$LOGDIR"

GAME_WIN_PATH="C:/Program Files (x86)/Steam/steamapps/common/age2hd/AoK HD.exe"
GAME_DIR="$HOME/win-compat/prefixes/aoe2/drive_c/Program Files (x86)/Steam/steamapps/common/age2hd"
PREFIX="$HOME/win-compat/prefixes/aoe2"

# Source config.env for auto-detected WINE_BIN (same logic as winrun/setup.sh)
CONFIG_ENV="$HOME/win-compat/config.env"
if [[ -f "$CONFIG_ENV" ]]; then
  # shellcheck source=../config.env
  source "$CONFIG_ENV"
fi

# Fallback Wine detection if config.env didn't resolve it
if [[ -z "${WINE_BIN:-}" ]]; then
  for p in \
      "/Applications/Wine Crossover.app/Contents/Resources/wine/bin/wine64" \
      "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64" \
      "$(brew --prefix 2>/dev/null || echo /opt/homebrew)/bin/wine64" \
      "$(brew --prefix 2>/dev/null || echo /opt/homebrew)/bin/wine"; do
    if [[ -x "$p" ]]; then WINE_BIN="$p"; break; fi
  done
fi

# Sanity checks
if [[ -z "${WINE_BIN:-}" || ! -x "$WINE_BIN" ]]; then
  echo "[ERROR] Wine not found. Install via:"
  echo "        brew install --cask --no-quarantine wine-crossover"
  exit 1
fi

if [[ ! -f "$GAME_DIR/steam_api.dll" ]]; then
  echo "[ERROR] $GAME_DIR/steam_api.dll not found."
  echo "        Run install-goldberg.sh first."
  exit 1
fi

if [[ ! -f "$GAME_DIR/steam_appid.txt" ]]; then
  echo "[ERROR] steam_appid.txt missing — run install-goldberg.sh first."
  exit 1
fi

GOLDBERG_DLL_SIZE=$(stat -f%z "$GAME_DIR/steam_api.dll" 2>/dev/null || stat -c%s "$GAME_DIR/steam_api.dll" 2>/dev/null || echo 0)
echo "=== AoE2 HD — Goldberg Launch — $(date) ===" | tee "$LOGFILE"
echo "EXE    : $GAME_WIN_PATH"          | tee -a "$LOGFILE"
echo "Prefix : $PREFIX"                  | tee -a "$LOGFILE"
echo "DLL sz : ${GOLDBERG_DLL_SIZE}b (steam_api.dll)" | tee -a "$LOGFILE"
echo "Log    : $LOGFILE"                 | tee -a "$LOGFILE"
echo "────────────────────────────────────────────" | tee -a "$LOGFILE"

# Force wined3d (Wine's built-in DX9 renderer) instead of DXVK.
# AoE2 HD is DX9 — DXVK requests geometryShader + shaderFloat64 which
# Metal/Apple Silicon cannot provide, causing "Failed to initialize draw system".
# CrossOver's wined3d translates DX9 → Metal directly without those features.
WINEPREFIX="$PREFIX" \
WINEARCH="win64" \
WINEDEBUG="-all" \
VK_ICD_FILENAMES="/opt/homebrew/etc/vulkan/icd.d/MoltenVK_icd.json" \
WINEDLLOVERRIDES="d3d9=b;dxgi=b;d3d10core=b;d3d11=b" \
WINED3D_CSMT=1 \
STEAM_APPID="221380" \
  "$WINE_BIN" start /d "C:\\Program Files (x86)\\Steam\\steamapps\\common\\age2hd\\" "AoK HD.exe" \
  2>&1 | tee -a "$LOGFILE"

EXIT_CODE=$?
echo "────────────────────────────────────────────" | tee -a "$LOGFILE"
echo "=== Exited (code $EXIT_CODE) — $(date) ===" | tee -a "$LOGFILE"
echo "Full log: $LOGFILE"
