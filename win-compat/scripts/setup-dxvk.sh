#!/usr/bin/env bash
# =============================================================================
# win-compat/scripts/setup-dxvk.sh
#
# Downloads the latest DXVK release from GitHub and installs it into a
# Wine prefix so that Direct3D 9/10/11 calls are translated to Vulkan.
# On macOS, Vulkan is provided by MoltenVK (brew install molten-vk).
#
# Usage:
#   PREFIX_NAME=aoe2 ./setup-dxvk.sh               # install into aoe2 prefix
#   PREFIX_NAME=aoe2 DXVK_VERSION=2.4 ./setup-dxvk.sh
#   PREFIX_NAME=aoe2 DXVK_FORCE=1 ./setup-dxvk.sh  # reinstall even if present
#
# What it does:
#   1. Downloads DXVK <version>.tar.gz from the official GitHub release.
#   2. Copies x64/ DLLs → prefix/drive_c/windows/system32/
#      Copies x32/ DLLs → prefix/drive_c/windows/syswow64/
#   3. Registers the DLLs as native in the Wine registry
#      (WINEDLLOVERRIDES="dxgi,d3d9,d3d10core,d3d11=n,b").
#   4. Writes a per-prefix dxvk.conf for sensible defaults on macOS ARM.
#
# Technical context (macOS ARM)
# ─────────────────────────────
# DXVK translates D3D → Vulkan at the API level (no GPU architecture needed).
# On macOS, Vulkan is not natively supported; MoltenVK maps Vulkan calls to
# Apple's Metal API. This chain lets D3D games run via:
#
#   Game EXE  →  DXVK  →  Vulkan  →  MoltenVK  →  Metal  →  GPU
#
# Limitations on ARM:
#   - Performance is good for modern Apple Silicon GPUs.
#   - Some Vulkan extensions required by DXVK may be absent under MoltenVK;
#     DXVK gracefully disables affected features.
#   - D3D12 is NOT covered by DXVK (use vkd3d-proton for D3D12; experimental).
# =============================================================================

set -eo pipefail
IFS=$'\n\t'

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; RESET='\033[0m'
info() { echo -e "${CYAN}[dxvk]${RESET} $*"; }
ok()   { echo -e "${GREEN}[dxvk]${RESET} $*"; }
warn() { echo -e "${YELLOW}[dxvk]${RESET} $*" >&2; }
die()  { echo -e "${RED}[dxvk] FATAL:${RESET} $*" >&2; exit 1; }

# ── config ───────────────────────────────────────────────────────────────────
WINCOMPAT_ROOT="${WINCOMPAT_ROOT:-$HOME/win-compat}"
PREFIX_NAME="${PREFIX_NAME:-aoe2}"
PREFIX_DIR="$WINCOMPAT_ROOT/prefixes/$PREFIX_NAME"
DXVK_VERSION="${DXVK_VERSION:-2.4}"
DXVK_FORCE="${DXVK_FORCE:-0}"       # set to 1 to reinstall even if present
INSTALLERS_DIR="$WINCOMPAT_ROOT/installers"

mkdir -p "$INSTALLERS_DIR"

# ── locate Wine binary (same logic as winrun) ─────────────────────────────────
_find_wine() {
    for p in \
        "/Applications/Wine Crossover.app/Contents/Resources/wine/bin/wine64" \
        "/Applications/Wine Crossover.app/Contents/Resources/wine/bin/wine" \
        "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64" \
        "$(brew --prefix 2>/dev/null || echo /opt/homebrew)/bin/wine64" \
        "$(brew --prefix 2>/dev/null || echo /opt/homebrew)/bin/wine"
    do
        [[ -x "$p" ]] && { echo "$p"; return 0; }
    done
    command -v wine64 2>/dev/null || command -v wine 2>/dev/null || echo ""
}
WINE_BIN="${WINE_BIN:-$(_find_wine)}"
[[ -z "$WINE_BIN" ]] && die "Wine binary not found. Run setup.sh first."

# ── verify prefix exists ─────────────────────────────────────────────────────
[[ -d "$PREFIX_DIR/drive_c" ]] || die "Prefix not found: $PREFIX_DIR\nRun: winrun $PREFIX_NAME wineboot --init"

# ── check if DXVK already installed ──────────────────────────────────────────
DXVK_MARKER="$PREFIX_DIR/.dxvk_version"
if [[ "$DXVK_FORCE" != "1" && -f "$DXVK_MARKER" ]]; then
    INSTALLED_VER="$(cat "$DXVK_MARKER")"
    if [[ "$INSTALLED_VER" == "$DXVK_VERSION" ]]; then
        ok "DXVK $DXVK_VERSION already installed in '$PREFIX_NAME'. Use DXVK_FORCE=1 to reinstall."
        exit 0
    fi
fi

# ── download DXVK ────────────────────────────────────────────────────────────
DXVK_TARBALL="$INSTALLERS_DIR/dxvk-${DXVK_VERSION}.tar.gz"
DXVK_URL="https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz"

if [[ ! -f "$DXVK_TARBALL" ]]; then
    info "Downloading DXVK $DXVK_VERSION …"
    info "URL: $DXVK_URL"
    if command -v curl &>/dev/null; then
        curl -L --fail --progress-bar -o "$DXVK_TARBALL" "$DXVK_URL" \
            || die "Download failed. Check URL or network: $DXVK_URL"
    elif command -v wget &>/dev/null; then
        wget -q --show-progress -O "$DXVK_TARBALL" "$DXVK_URL" \
            || die "Download failed (wget): $DXVK_URL"
    else
        die "Neither curl nor wget found."
    fi
    ok "Downloaded: $DXVK_TARBALL"
else
    ok "DXVK tarball already in installers cache: $DXVK_TARBALL"
fi

# ── extract ───────────────────────────────────────────────────────────────────
DXVK_EXTRACT_DIR="$INSTALLERS_DIR/dxvk-${DXVK_VERSION}"
if [[ ! -d "$DXVK_EXTRACT_DIR" ]]; then
    info "Extracting …"
    tar -xzf "$DXVK_TARBALL" -C "$INSTALLERS_DIR"
    ok "Extracted to $DXVK_EXTRACT_DIR"
else
    ok "Already extracted: $DXVK_EXTRACT_DIR"
fi

# ── copy DLLs ─────────────────────────────────────────────────────────────────
SYS32="$PREFIX_DIR/drive_c/windows/system32"
SYSWOW64="$PREFIX_DIR/drive_c/windows/syswow64"
mkdir -p "$SYS32" "$SYSWOW64"

DLLS=(dxgi.dll d3d9.dll d3d10core.dll d3d11.dll)

info "Installing 64-bit DXVK DLLs → system32 …"
for dll in "${DLLS[@]}"; do
    src="$DXVK_EXTRACT_DIR/x64/$dll"
    if [[ -f "$src" ]]; then
        cp -f "$src" "$SYS32/$dll"
        ok "  $dll → system32/"
    else
        warn "  x64/$dll not found in DXVK archive (may be absent for this version)"
    fi
done

info "Installing 32-bit DXVK DLLs → syswow64 …"
for dll in "${DLLS[@]}"; do
    src="$DXVK_EXTRACT_DIR/x32/$dll"
    if [[ -f "$src" ]]; then
        cp -f "$src" "$SYSWOW64/$dll"
        ok "  $dll → syswow64/"
    else
        warn "  x32/$dll not found in DXVK archive (skipping)"
    fi
done

# ── register as native DLLs in Wine registry ─────────────────────────────────
info "Registering DXVK DLLs as native in Wine registry …"
for dll in "${DLLS[@]}"; do
    dll_noext="${dll%.dll}"
    WINEPREFIX="$PREFIX_DIR" WINEDEBUG="-all" \
        "$WINE_BIN" reg add \
        "HKCU\\Software\\Wine\\DllOverrides" \
        /v "$dll_noext" /t REG_SZ /d "native,builtin" /f \
        2>/dev/null && ok "  Registered: $dll_noext" \
        || warn "  Failed to register: $dll_noext (may be OK)"
done

# ── write dxvk.conf ───────────────────────────────────────────────────────────
DXVK_CONF="$PREFIX_DIR/dxvk.conf"
cat > "$DXVK_CONF" <<'CONF'
# dxvk.conf — per-prefix DXVK configuration
# Generated by win-compat/scripts/setup-dxvk.sh
# Full option reference: https://github.com/doitsujin/dxvk/blob/master/dxvk.conf

# Async shader compilation (reduces stuttering, mildly affects correctness)
dxvk.enableAsync = True

# HUD: fps counter  (options: fps, frametimes, submissions, memory, gpuload, version, api, devinfo, full)
# dxvk.hud = fps,memory

# Frame rate limit (0 = unlimited)
# dxvk.maxFrameRate = 60

# D3D9 / AoE2 DE tuning
d3d9.maxFrameLatency = 1

# macOS / MoltenVK: some Vulkan features may be unavailable
# Disable sparse resources if MoltenVK reports missing support
# dxvk.enableSparseResources = False
CONF
ok "dxvk.conf written to $DXVK_CONF"

# ── WINEDLLOVERRIDES env hint ─────────────────────────────────────────────────
OVERRIDE_VALS="dxgi,d3d9,d3d10core,d3d11=n,b"
info "DXVK DLL overrides needed at runtime: WINEDLLOVERRIDES=\"$OVERRIDE_VALS\""
info "(winrun already sets this automatically via registry entries)"

# ── check MoltenVK ICD ───────────────────────────────────────────────────────
ICD_FOUND=0
for p in \
    "/opt/homebrew/etc/vulkan/icd.d/MoltenVK_icd.json" \
    "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json" \
    "/usr/local/etc/vulkan/icd.d/MoltenVK_icd.json" \
    "/usr/local/share/vulkan/icd.d/MoltenVK_icd.json"
do
    if [[ -f "$p" ]]; then
        ok "MoltenVK ICD found: $p"
        ICD_FOUND=1; break
    fi
done

if [[ "$ICD_FOUND" -eq 0 ]]; then
    warn "MoltenVK ICD NOT found. DXVK will not be able to use Vulkan."
    warn "Install with: brew install molten-vk"
    warn "Then verify:  vulkaninfo --summary"
fi

# ── stamp version ─────────────────────────────────────────────────────────────
echo "$DXVK_VERSION" > "$DXVK_MARKER"
ok "DXVK $DXVK_VERSION installed into prefix '$PREFIX_NAME'"
