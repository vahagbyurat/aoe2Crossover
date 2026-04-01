#!/usr/bin/env bash
# =============================================================================
# win-compat/scripts/setup.sh
#
# One-shot bootstrap for the Wine / Windows compatibility stack on
# Apple Silicon (arm64) macOS.
#
# Run once:
#   chmod +x ~/win-compat/scripts/setup.sh
#   ~/win-compat/scripts/setup.sh
#
# What it does
# ------------
#  1. Prints environment facts (macOS, arch, Rosetta 2, Homebrew).
#  2. Installs Rosetta 2 if missing.
#  3. Taps GCenx/wine (best macOS ARM Wine packaging).
#  4. Installs: wine-crossover, winetricks, qemu, molten-vk, vulkan-loader,
#               vulkan-tools, cabextract, p7zip.
#  5. Creates ~/win-compat directory tree.
#  6. Creates a "aoe2" Wine prefix (Windows 10, 64-bit).
#  7. Installs DXVK into the prefix.
#  8. Runs a quick sanity check (wineboot / notepad.exe).
# =============================================================================

set -eo pipefail
IFS=$'\n\t'

# ── colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ERR]${RESET}   $*" >&2; }
section() { echo -e "\n${BOLD}══════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD} $*${RESET}"; \
            echo -e "${BOLD}══════════════════════════════════════════${RESET}"; }

LOGFILE="$HOME/win-compat/logs/setup_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOGFILE")"
# Tee all output to log file
exec > >(tee -a "$LOGFILE") 2>&1
info "Full log → $LOGFILE"

# ── 1. Environment facts ─────────────────────────────────────────────────────
section "1. Environment Detection"

OS_VER="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
BUILD="$(sw_vers -buildVersion 2>/dev/null || echo unknown)"
ARCH="$(uname -m)"

info "macOS version : $OS_VER  (build $BUILD)"
info "CPU arch      : $ARCH"

if [[ "$ARCH" != "arm64" ]]; then
    warn "This script is optimised for Apple Silicon (arm64). Detected: $ARCH"
    warn "Intel Mac users can skip Rosetta 2; Wine x86_64 runs natively."
fi

# Check Rosetta 2
if /usr/bin/pgrep -q oahd 2>/dev/null || \
   [[ -f /Library/Apple/usr/share/rosetta/rosetta ]]; then
    ok "Rosetta 2 is installed"
    ROSETTA_OK=1
else
    warn "Rosetta 2 NOT detected"
    ROSETTA_OK=0
fi

# ── 2. Install Rosetta 2 ──────────────────────────────────────────────────────
section "2. Rosetta 2"

if [[ "$ARCH" == "arm64" && "$ROSETTA_OK" -eq 0 ]]; then
    info "Installing Rosetta 2 (required to run x86_64 Wine on ARM) …"
    softwareupdate --install-rosetta --agree-to-license
    ok "Rosetta 2 installed"
else
    ok "Rosetta 2 check passed (not needed on Intel or already present)"
fi

# ── 3. Homebrew ───────────────────────────────────────────────────────────────
section "3. Homebrew"

if command -v brew &>/dev/null; then
    BREW_VER="$(brew --version | head -1)"
    ok "Homebrew found: $BREW_VER"
    BREW_PREFIX="$(brew --prefix)"
    info "Homebrew prefix: $BREW_PREFIX"
else
    err "Homebrew is NOT installed."
    info "Installing Homebrew …"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add to PATH for the rest of this script
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    ok "Homebrew installed"
fi

# ── 4. Tap GCenx/wine (best macOS Wine packaging incl. ARM) ──────────────────
section "4. GCenx Wine Tap"

info "Tapping gcenx/wine …"
brew tap gcenx/wine 2>/dev/null || warn "gcenx/wine tap already present or failed (continuing)"

# ── 5. Install packages ───────────────────────────────────────────────────────
section "5. Package Installation"

# ---- helper: install only if missing ----------------------------------------
brew_install() {
    local pkg="$1"; shift
    local flags=("$@")
    if brew list --formula "$pkg" &>/dev/null 2>&1; then
        ok "$pkg already installed (formula)"
    elif brew list --cask "$pkg" &>/dev/null 2>&1; then
        ok "$pkg already installed (cask)"
    else
        info "Installing $pkg …"
        if [[ ${#flags[@]} -gt 0 ]]; then
            brew install "${flags[@]}" "$pkg" && ok "$pkg installed" || warn "$pkg install FAILED – continuing"
        else
            brew install "$pkg" && ok "$pkg installed" || warn "$pkg install FAILED – continuing"
        fi
    fi
}

# ---- Wine -------------------------------------------------------------------
# wine-crossover: CodeWeavers' open-source Wine fork, packaged as a macOS .app
# by Gcenx. It supports arm64 Macs best among free options and is Apache-2.0.
# The --no-quarantine flag prevents Gatekeeper from blocking the unsigned app.
info "Installing wine-crossover (Cask) …"
if brew list --cask wine-crossover &>/dev/null 2>&1; then
    ok "wine-crossover already installed"
else
    brew install --cask --no-quarantine wine-crossover \
        && ok "wine-crossover installed" \
        || {
            warn "wine-crossover Cask failed; falling back to wine-stable …"
            brew install --cask --no-quarantine wine-stable \
                && ok "wine-stable installed" \
                || warn "wine-stable also failed – Wine not installed; manual install required"
        }
fi

# ---- Supporting tools -------------------------------------------------------
brew_install winetricks
brew_install cabextract          # winetricks dependency
brew_install p7zip               # winetricks dependency for some verbs
brew_install qemu                # full-system x86 emulation (UTM alternative approach)
brew_install molten-vk           # Vulkan → Metal (needed by DXVK on macOS)
brew_install vulkan-loader       # Vulkan loader / dispatch
brew_install vulkan-tools        # vulkaninfo diagnostic

# ── 6. Directory layout ───────────────────────────────────────────────────────
section "6. Directory Layout"

WINCOMPAT="$HOME/win-compat"
for d in prefixes installers scripts logs; do
    mkdir -p "$WINCOMPAT/$d"
    ok "Created $WINCOMPAT/$d"
done

# Copy scripts from their current location if they exist
SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for s in winrun setup-dxvk.sh; do
    if [[ -f "$SCRIPT_SRC/$s" && "$SCRIPT_SRC" != "$WINCOMPAT/scripts" ]]; then
        cp "$SCRIPT_SRC/$s" "$WINCOMPAT/scripts/$s"
        chmod +x "$WINCOMPAT/scripts/$s"
        ok "Copied $s → $WINCOMPAT/scripts/"
    fi
done

# Copy config.env
if [[ -f "$SCRIPT_SRC/../config.env" && \
      "$SCRIPT_SRC/../config.env" != "$WINCOMPAT/config.env" ]]; then
    cp "$SCRIPT_SRC/../config.env" "$WINCOMPAT/config.env"
    ok "Copied config.env → $WINCOMPAT/"
fi

# Ensure winrun is executable and in a convenient place
chmod +x "$WINCOMPAT/scripts/winrun" 2>/dev/null || true

# Add scripts dir to PATH hint
SHELL_RC="$HOME/.zshrc"
[[ -f "$HOME/.bashrc" && ! -f "$HOME/.zshrc" ]] && SHELL_RC="$HOME/.bashrc"
if ! grep -q "win-compat/scripts" "$SHELL_RC" 2>/dev/null; then
    echo '' >> "$SHELL_RC"
    echo '# win-compat launcher' >> "$SHELL_RC"
    echo 'export PATH="$HOME/win-compat/scripts:$PATH"' >> "$SHELL_RC"
    ok "Added ~/win-compat/scripts to PATH in $SHELL_RC"
    info "Run: source $SHELL_RC  (or open a new terminal)"
fi

# ── 7. Detect Wine binary location ───────────────────────────────────────────
section "7. Wine Binary Detection"

# Source config to use the auto-detect logic
# shellcheck source=../config.env
source "$WINCOMPAT/config.env" 2>/dev/null || true

if [[ -z "$WINE_BIN" ]]; then
    # Last-ditch: scan common Cask locations
    for p in \
        "/Applications/Wine Crossover.app/Contents/Resources/wine/bin/wine64" \
        "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64" \
        "$(brew --prefix)/bin/wine64" \
        "$(brew --prefix)/bin/wine"
    do
        if [[ -x "$p" ]]; then WINE_BIN="$p"; break; fi
    done
fi

if [[ -z "$WINE_BIN" ]]; then
    err "Could not locate a Wine binary. Please install wine-crossover manually:"
    err "  brew install --cask --no-quarantine wine-crossover"
    err "Then re-run this script."
    exit 1
fi

ok "Wine binary: $WINE_BIN"
WINE_VER="$("$WINE_BIN" --version 2>/dev/null || echo unknown)"
ok "Wine version: $WINE_VER"

# ── 8. Create 'aoe2' Wine prefix ─────────────────────────────────────────────
section "8. Wine Prefix: aoe2"

AOE2_PREFIX="$WINCOMPAT/prefixes/aoe2"

if [[ -d "$AOE2_PREFIX/drive_c" ]]; then
    ok "Prefix $AOE2_PREFIX already initialised"
else
    info "Initialising Wine prefix at $AOE2_PREFIX …"
    info "(This may take 30–90 s and will flash a few Wine dialogs briefly)"

    # WINEARCH=win64 → 64-bit prefix (required for modern games)
    WINEPREFIX="$AOE2_PREFIX" \
    WINEARCH="win64" \
    WINEDEBUG="-all" \
    "$WINE_BIN" wineboot --init 2>&1 | tail -5

    ok "Prefix initialised"
fi

# Set Windows version to Windows 10
info "Setting Windows version to Windows 10 …"
WINEPREFIX="$AOE2_PREFIX" \
WINEDEBUG="-all" \
"$WINE_BIN" reg add \
    "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
    /v CurrentVersion /t REG_SZ /d "10.0" /f 2>/dev/null || true

WINEPREFIX="$AOE2_PREFIX" \
WINEDEBUG="-all" \
"$WINE_BIN" reg add \
    "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" \
    /v CurrentBuildNumber /t REG_SZ /d "19041" /f 2>/dev/null || true
ok "Windows 10 (build 19041) set in registry"

# ── 9. Install DXVK ──────────────────────────────────────────────────────────
section "9. DXVK Setup"

DXVK_SETUP="$WINCOMPAT/scripts/setup-dxvk.sh"
if [[ -x "$DXVK_SETUP" ]]; then
    info "Running DXVK setup for prefix: aoe2"
    PREFIX_NAME="aoe2" "$DXVK_SETUP" \
        && ok "DXVK installed into aoe2 prefix" \
        || warn "DXVK setup failed – games may use software rendering"
else
    warn "setup-dxvk.sh not found at $DXVK_SETUP – skipping DXVK"
fi

# ── 10. Sanity check ─────────────────────────────────────────────────────────
section "10. Sanity Check"

info "Running: wineboot --update (background)"
WINEPREFIX="$AOE2_PREFIX" \
WINEDEBUG="-all" \
"$WINE_BIN" wineboot --update 2>&1 | tail -3 || true
ok "wineboot --update completed"

info "Checking notepad.exe exists in prefix …"
NOTEPAD_PATH="$AOE2_PREFIX/drive_c/windows/notepad.exe"
if [[ -f "$NOTEPAD_PATH" ]]; then
    ok "notepad.exe found: $NOTEPAD_PATH"
else
    warn "notepad.exe not found (prefix may be incomplete)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
section "Setup Complete"

cat <<'EOF'

NEXT STEPS — AoE2 HD setup
---------------------------

  1. Reload your shell so winrun is in PATH:
       source ~/.zshrc

  2. (Optional) Verify Wine works:
       winrun aoe2 notepad

  3. Install the game via SteamCMD — copy the template, add your creds, run it:
       cp ~/win-compat/scripts/steam-install.sh ~/steam-install-private.sh
       # edit ~/steam-install-private.sh with your Steam username + password
       bash ~/steam-install-private.sh

  4. Install Windows runtime dependencies:
       WINEPREFIX="$HOME/win-compat/prefixes/aoe2" winetricks vcrun2013 vcrun2015
       WINEPREFIX="$HOME/win-compat/prefixes/aoe2" winetricks d3dx9

  5. Install the Goldberg Steam Emulator (needed because Steam's client
     cannot run on Wine — see README for details):
       bash ~/win-compat/scripts/install-goldberg.sh

  6. Launch the game:
       bash ~/win-compat/scripts/launch-aoe2-goldberg.sh

Quick usage (general)
---------------------

  # Launch any EXE inside the aoe2 prefix:
    winrun aoe2 /path/to/game.exe

  # Launch winecfg for the aoe2 prefix:
    winrun aoe2 winecfg

  # Create a new prefix for another game:
    winrun myprefix /path/to/installer.exe

Environment
-----------
  Wine prefix  :  ~/win-compat/prefixes/<name>/
  Logs         :  ~/win-compat/logs/<name>_<timestamp>.log
  Config       :  ~/win-compat/config.env
  Scripts      :  ~/win-compat/scripts/

EOF

ok "All done. Log saved to $LOGFILE"
