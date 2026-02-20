#!/usr/bin/env bash
# =============================================================================
# launch-aoe2.sh — DEPRECATED
#
# This script attempted to launch AoE2 HD via Steam's -applaunch flag.
# It does NOT work because steamwebhelper crashes on Wine (missing
# bcryptprimitives.dll → chrome_elf.dll init failure), so Steam never
# fires the applaunch and the game never starts.
#
# USE INSTEAD: launch-aoe2-goldberg.sh
# That script uses the Goldberg Steam emulator to bypass DRM entirely
# and launches the game EXE directly — no Steam required.
# =============================================================================
echo "[DEPRECATED] This script does not work. Use launch-aoe2-goldberg.sh instead."
exit 1

LOGDIR="$HOME/win-compat/logs"
LOGFILE="$LOGDIR/aoe2_launch_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOGDIR"

STEAM_EXE="C:/Program Files (x86)/Steam/steam.exe"
APP_ID="221380"

echo "=== AoE2 HD Launch — $(date) ===" | tee "$LOGFILE"
echo "Log: $LOGFILE" | tee -a "$LOGFILE"
echo "Steam: $STEAM_EXE  App: $APP_ID" | tee -a "$LOGFILE"
echo "────────────────────────────────" | tee -a "$LOGFILE"
echo ">>> When 'steamwebhelper not responding' appears — click EXIT (not restart)" | tee -a "$LOGFILE"
echo ">>> Game window should appear within 15-20s after dismissing it" | tee -a "$LOGFILE"
echo "────────────────────────────────" | tee -a "$LOGFILE"

WINEPREFIX="$HOME/win-compat/prefixes/aoe2" \
WINEARCH="win64" \
WINEDEBUG="err+all,warn+module,warn+loaddll" \
STEAM_DISABLE_BROWSER=1 \
VK_ICD_FILENAMES="/opt/homebrew/etc/vulkan/icd.d/MoltenVK_icd.json" \
DXVK_LOG_LEVEL="warn" \
"/Applications/Wine Crossover.app/Contents/Resources/wine/bin/wine64" \
  "$STEAM_EXE" -no-browser -silent -applaunch "$APP_ID" \
  2>&1 | tee -a "$LOGFILE"

echo "────────────────────────────────" | tee -a "$LOGFILE"
echo "=== Exited — $(date) ===" | tee -a "$LOGFILE"
echo "Full log saved to: $LOGFILE"
