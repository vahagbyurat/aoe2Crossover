#!/usr/bin/env bash
# =============================================================================
# steam-install.sh  —  Login to Steam via SteamCMD and install a game
# Edit the three variables below, then run:
#   bash ~/win-compat/scripts/steam-install.sh
# =============================================================================

# ── EDIT THESE ───────────────────────────────────────────────────────────────
STEAM_USER="YOUR_USERNAME"       # your Steam account name (not display name)
STEAM_PASS="YOUR_PASSWORD"       # your Steam password
STEAM_APP_ID="221380"            # 221380 = AoE2 HD Edition
INSTALL_DIR="C:/Program Files (x86)/Steam/steamapps/common/age2hd"
# ─────────────────────────────────────────────────────────────────────────────

STEAMCMD="$HOME/win-compat/installers/steamcmd/steamcmd.exe"
WINCOMPAT_ROOT="$HOME/win-compat"
WINRUN="$WINCOMPAT_ROOT/scripts/winrun"

# Ensure winrun is available (use full path so this works even if PATH
# hasn't been reloaded after setup.sh)
if [[ ! -x "$WINRUN" ]]; then
    echo "[ERROR] winrun not found at: $WINRUN"
    echo "        Run bootstrap.sh / setup.sh first."
    exit 1
fi

if [[ ! -f "$STEAMCMD" ]]; then
    echo "SteamCMD not found. Downloading..."
    mkdir -p "$WINCOMPAT_ROOT/installers/steamcmd"
    curl -L "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" \
        -o "$WINCOMPAT_ROOT/installers/steamcmd.zip"
    unzip "$WINCOMPAT_ROOT/installers/steamcmd.zip" \
        -d "$WINCOMPAT_ROOT/installers/steamcmd"
    echo "SteamCMD ready."
fi

echo ""
echo "Logging in as: $STEAM_USER"
echo "Installing app: $STEAM_APP_ID"
echo "To: $INSTALL_DIR"
echo ""
echo ">>> Steam Guard 2FA code will be prompted interactively <<<"
echo ""

"$WINRUN" aoe2 "$STEAMCMD" \
    +login "$STEAM_USER" "$STEAM_PASS" \
    +force_install_dir "$INSTALL_DIR" \
    +app_update "$STEAM_APP_ID" validate \
    +quit
