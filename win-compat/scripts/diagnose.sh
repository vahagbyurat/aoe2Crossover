#!/usr/bin/env bash
# =============================================================================
# win-compat/scripts/diagnose.sh
#
# Prints a full diagnostics report of the Wine / compatibility stack.
# Run this if something doesn't work; paste the output when asking for help.
#
# Usage:  ~/win-compat/scripts/diagnose.sh
# =============================================================================

set -eo pipefail

BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

section() { echo -e "\n${BOLD}── $* ──${RESET}"; }
ok()      { echo -e "  ${GREEN}✓${RESET} $*"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET} $*"; }
miss()    { echo -e "  ${RED}✗${RESET} $*"; }
info()    { echo -e "  ${CYAN}→${RESET} $*"; }

echo -e "${BOLD}win-compat diagnostics  $(date)${RESET}"

# ── macOS ────────────────────────────────────────────────────────────────────
section "macOS"
sw_vers 2>/dev/null || info "sw_vers not available"
info "uname -m : $(uname -m)"
info "sysctl CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo n/a)"

# ── Rosetta 2 ─────────────────────────────────────────────────────────────────
section "Rosetta 2"
if /usr/bin/pgrep -q oahd 2>/dev/null; then
    ok "oahd process running (Rosetta 2 active)"
elif [[ -f /Library/Apple/usr/share/rosetta/rosetta ]]; then
    ok "Rosetta 2 binary present (will activate on demand)"
else
    miss "Rosetta 2 NOT detected"
    warn "Install: softwareupdate --install-rosetta --agree-to-license"
fi

# ── Homebrew ─────────────────────────────────────────────────────────────────
section "Homebrew"
if command -v brew &>/dev/null; then
    ok "brew: $(brew --version | head -1)"
    info "prefix: $(brew --prefix)"
else
    miss "Homebrew not installed"
fi

# ── Wine ─────────────────────────────────────────────────────────────────────
section "Wine"
_show_wine() {
    local p="$1"
    if [[ -x "$p" ]]; then
        local ver; ver="$("$p" --version 2>/dev/null || echo unknown)"
        local arch; arch="$(file "$p" 2>/dev/null | grep -oE 'x86.64|arm64|aarch64' | head -1 || echo ?)"
        ok "$p  [$arch]  $ver"
    else
        miss "$p  (not found)"
    fi
}
_show_wine "/Applications/Wine Crossover.app/Contents/Resources/wine/bin/wine64"
_show_wine "/Applications/Wine Crossover.app/Contents/Resources/wine/bin/wine"
_show_wine "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64"
if command -v brew &>/dev/null; then
    _show_wine "$(brew --prefix)/bin/wine64"
    _show_wine "$(brew --prefix)/bin/wine"
fi
info "PATH wine: $(command -v wine64 2>/dev/null || command -v wine 2>/dev/null || echo not in PATH)"

# ── Winetricks ────────────────────────────────────────────────────────────────
section "Winetricks"
if command -v winetricks &>/dev/null; then
    ok "winetricks: $(winetricks --version 2>/dev/null || winetricks version 2>/dev/null || echo installed)"
else
    miss "winetricks not found  (brew install winetricks)"
fi

# ── QEMU ─────────────────────────────────────────────────────────────────────
section "QEMU"
if command -v qemu-system-x86_64 &>/dev/null; then
    ok "qemu-system-x86_64: $(qemu-system-x86_64 --version | head -1)"
else
    miss "qemu-system-x86_64 not found  (brew install qemu)"
fi

# ── MoltenVK ─────────────────────────────────────────────────────────────────
section "MoltenVK / Vulkan"
ICD_PATHS=(
    "/opt/homebrew/etc/vulkan/icd.d/MoltenVK_icd.json"
    "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
    "/usr/local/etc/vulkan/icd.d/MoltenVK_icd.json"
    "/usr/local/share/vulkan/icd.d/MoltenVK_icd.json"
    "$HOME/.local/share/vulkan/icd.d/MoltenVK_icd.json"
)
FOUND_ICD=""
for p in "${ICD_PATHS[@]}"; do
    if [[ -f "$p" ]]; then ok "MoltenVK ICD: $p"; FOUND_ICD="$p"; break; fi
done
[[ -z "$FOUND_ICD" ]] && miss "MoltenVK ICD not found  (brew install molten-vk)"

if command -v vulkaninfo &>/dev/null; then
    info "vulkaninfo --summary:"
    vulkaninfo --summary 2>/dev/null | grep -E 'GPU|Vulkan|apiVersion|driverVersion|deviceName' \
        | head -10 | sed 's/^/    /'
else
    warn "vulkaninfo not installed  (brew install vulkan-tools)"
fi

# ── Prefixes ─────────────────────────────────────────────────────────────────
section "Wine Prefixes"
PREFIXES_DIR="$HOME/win-compat/prefixes"
if [[ -d "$PREFIXES_DIR" ]]; then
    for d in "$PREFIXES_DIR"/*/; do
        name="$(basename "$d")"
        if [[ -d "$d/drive_c" ]]; then
            dxvk_ver="$(cat "$d/.dxvk_version" 2>/dev/null || echo none)"
            ok "$name  (DXVK: $dxvk_ver)"
        else
            warn "$name  (empty / uninitialised)"
        fi
    done
else
    miss "No prefixes directory found"
fi

# ── DXVK DLLs in aoe2 prefix ─────────────────────────────────────────────────
section "DXVK DLLs in aoe2 prefix"
AOE2="$HOME/win-compat/prefixes/aoe2"
if [[ -d "$AOE2/drive_c/windows/system32" ]]; then
    for dll in d3d9.dll d3d10core.dll d3d11.dll dxgi.dll; do
        if [[ -f "$AOE2/drive_c/windows/system32/$dll" ]]; then
            sz="$(du -h "$AOE2/drive_c/windows/system32/$dll" | awk '{print $1}')"
            ok "system32/$dll  ($sz)"
        else
            miss "system32/$dll  MISSING"
        fi
    done
else
    miss "aoe2 prefix system32 not found"
fi

# ── scripts ───────────────────────────────────────────────────────────────────
section "win-compat scripts"
for s in winrun setup.sh setup-dxvk.sh diagnose.sh; do
    p="$HOME/win-compat/scripts/$s"
    if [[ -x "$p" ]]; then ok "$p"; else miss "$p"; fi
done

echo ""
echo -e "${BOLD}Diagnostics complete.${RESET}"
