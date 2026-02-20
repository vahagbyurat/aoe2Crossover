> **Getting started?** See the top-level **[README.md](../../README.md)** for
> the complete setup guide. This document is the technical reference for
> `winrun`, DXVK, and winetricks.

# win-compat — Free/Open-Source Windows Compatibility Stack for Apple Silicon

A fully open-source, Homebrew-based stack for running x86 Windows apps and
games on macOS Apple Silicon (M1/M2/M3), using Wine + MoltenVK + DXVK.

---

## ⚠️  What is actually possible on Apple Silicon — be honest with yourself

| Layer | What it does | Status on M1/M2/M3 |
|---|---|---|
| **Wine** | Translates Windows API calls to macOS equivalents | ✅ Works (x86_64 build via Rosetta 2) |
| **Rosetta 2** | Translates x86_64 *macOS* instructions to arm64 | ✅ Built-in, seamless |
| **Wine running x86 Windows EXEs** | Wine (x86_64) + Rosetta 2 together | ✅ This is the key: Rosetta translates Wine's x86_64 code; Wine translates Windows API calls. Net effect: x86 Windows EXEs run. |
| **DXVK** | D3D9/10/11 → Vulkan translation | ⚠️ Use v1.10.3 (v2.x needs Vulkan 1.3, MoltenVK only provides 1.2). Not used by AoE2 HD — wined3d is used instead (see main README). |
| **MoltenVK** | Vulkan → Metal translation | ✅ Works (Apple GPU) |
| **Full D3D chain** | EXE → DXVK → Vulkan → MoltenVK → Metal | ✅ Works for many games (not AoE2 HD — Metal lacks geometryShader) |
| **Wine running arm64 Windows EXEs** | — | ⚠️ Limited (arm64 Windows PE support in Wine is experimental) |
| **QEMU (installed)** | Full x86 CPU emulation in a VM | 🐢 Very slow; for use only when Wine can't run something |
| **D3D12 games** | Not covered by DXVK (needs vkd3d-proton) | ⚠️ Experimental |

**Summary:** Wine does NOT emulate a CPU. Instead, the *Wine binary itself* is
x86_64, which means Rosetta 2 handles the CPU translation transparently. This
lets Wine run x86 Windows applications.  QEMU is included as a fallback for
full-system emulation but is far slower.

---

## Directory Layout

```
~/win-compat/
├── config.env                   ← shared env vars (Wine binary, MoltenVK ICD, etc.)
├── prefixes/
│   └── aoe2/                    ← Wine prefix (Windows 10, 64-bit)
│       ├── drive_c/
│       └── .dxvk_version
├── installers/                  ← downloaded archives (DXVK tarball, Goldberg, etc.)
├── scripts/
│   ├── setup.sh                 ← one-shot bootstrap (run once)
│   ├── winrun                   ← launch any EXE (the main tool you'll use)
│   ├── setup-dxvk.sh            ← install/update DXVK in a prefix
│   ├── diagnose.sh              ← print full environment diagnostics
│   ├── steam-install.sh         ← SteamCMD game installer template (add your own creds)
│   ├── install-goldberg.sh      ← download + install Goldberg Steam emulator
│   ├── launch-aoe2-goldberg.sh  ← launch AoE2 HD (use this to play)
│   └── launch-aoe2.sh           ← DEPRECATED — Steam -applaunch (does not work)
└── logs/                        ← per-run logs (<prefix>_<timestamp>.log)
```

---

## Quick Start

### 1. Copy scripts to your home directory

```bash
cp -r ~/win-compat ~/win-compat_backup 2>/dev/null || true
# (the workspace folder IS ~/win-compat already if you followed the setup)
```

### 2. Run the one-shot setup

```bash
chmod +x ~/win-compat/scripts/setup.sh
~/win-compat/scripts/setup.sh
```

This will:
- Install Rosetta 2 (if missing)
- Add the GCenx Homebrew tap (best macOS Wine packaging)
- Install wine-crossover, winetricks, qemu, molten-vk, vulkan-tools, cabextract, p7zip
- Create the `aoe2` Wine prefix
- Install DXVK into the prefix
- Run a quick sanity check

### 3. Reload your shell

```bash
source ~/.zshrc   # or ~/.bashrc
```

### 4. Test Wine works

```bash
winrun aoe2 notepad
```

---

## winrun — the launcher

```
Usage:  winrun <prefix_name> <exe_or_wine_command> [args...]
```

### Examples

```bash
# Built-in Wine tools
winrun aoe2 notepad          # open Notepad
winrun aoe2 winecfg          # Wine configuration GUI
winrun aoe2 regedit          # Wine registry editor
winrun aoe2 wineboot --init  # (re-)initialise prefix

# Run an installer
winrun aoe2 ~/Downloads/AoE2DE_setup.exe

# Run a game EXE
winrun aoe2 "/path/to/Age of Empires 2 DE/AoE2DE_s.exe"

# Pass arguments
winrun aoe2 ~/Downloads/setup.exe /S /D="C:\\Game"

# Create a fresh prefix for a different game
winrun mygame ~/Downloads/game_installer.exe
# (prefix is created automatically at ~/win-compat/prefixes/mygame/)

# Run Steam installer inside its own prefix
winrun steam ~/Downloads/SteamSetup.exe
```

### What winrun does automatically

1. Sources `~/win-compat/config.env` for shared settings
2. Finds the best available Wine binary (wine-crossover → wine64 → wine)
3. Checks Rosetta 2 is present on Apple Silicon
4. Creates the prefix if it doesn't exist (Windows 10, 64-bit)
5. Sets `VK_ICD_FILENAMES` to MoltenVK's ICD JSON
6. Logs all Wine stderr output to `~/win-compat/logs/<prefix>_<timestamp>.log`
7. Exits non-zero on failure

---

## DXVK (DirectX 9/10/11 acceleration)

DXVK replaces Wine's built-in D3D with a Vulkan-based implementation that
runs much faster on Apple Silicon (via MoltenVK → Metal).

### Install / update DXVK in a prefix

```bash
# Default: aoe2 prefix, DXVK 1.10.3 (last version compatible with MoltenVK 1.2)
PREFIX_NAME=aoe2 ~/win-compat/scripts/setup-dxvk.sh

# Different prefix
PREFIX_NAME=mygame ~/win-compat/scripts/setup-dxvk.sh

# Force reinstall
PREFIX_NAME=aoe2 DXVK_FORCE=1 ~/win-compat/scripts/setup-dxvk.sh

# Pin a specific DXVK version
PREFIX_NAME=aoe2 DXVK_VERSION=2.3.1 ~/win-compat/scripts/setup-dxvk.sh
```

### Verify DXVK is active

When you launch a D3D game, you should see `DXVK` in the window title bar
(if hud is enabled) or in the log file.  To enable the HUD:

```bash
DXVK_HUD=fps,memory winrun aoe2 /path/to/game.exe
```

---

## MoltenVK (Vulkan → Metal)

```bash
brew install molten-vk vulkan-tools

# Verify Vulkan works
vulkaninfo --summary
```

`winrun` automatically sets `VK_ICD_FILENAMES` to the MoltenVK ICD JSON.
If you see "no Vulkan device found" in DXVK logs, check:

```bash
ls "$(brew --prefix)/etc/vulkan/icd.d/"
# should show MoltenVK_icd.json
# (older Homebrew versions may use share/vulkan/icd.d/ instead)
```

---

## Winetricks — install Windows components

```bash
# Install Visual C++ runtimes (needed by many games)
WINEPREFIX=~/win-compat/prefixes/aoe2 winetricks vcrun2019

# Install DirectX (not needed if using DXVK, but some games insist)
WINEPREFIX=~/win-compat/prefixes/aoe2 winetricks directx9

# Install .NET Framework
WINEPREFIX=~/win-compat/prefixes/aoe2 winetricks dotnet48

# Shortcut: use winrun to open the winetricks GUI
WINEPREFIX=~/win-compat/prefixes/aoe2 winetricks --gui
```

---

## QEMU — full x86 VM (alternative / fallback)

QEMU is installed but is only needed if Wine can't run a particular EXE.
For Windows gaming, the better open-source alternative is **UTM** (free on
macOS), which provides a GUI around QEMU and supports Windows ARM + x86
emulation inside Windows.

```bash
# Check QEMU is installed
qemu-system-x86_64 --version

# For a full VM approach, see: https://mac.getutm.app/
# UTM + Windows ARM ISO + Windows' built-in x86 emulation layer
# is more compatible for heavily DRM'd or anti-cheat games that
# Wine cannot run, at the cost of VM overhead.
```

---

## Troubleshooting

### "Wine is not installed" / winrun fails immediately

```bash
brew install --cask --no-quarantine wine-crossover
```

### "Rosetta 2 not found" warning

```bash
softwareupdate --install-rosetta --agree-to-license
```

### Game crashes with D3D error / black screen

```bash
# Check DXVK is installed
cat ~/win-compat/prefixes/aoe2/.dxvk_version

# Reinstall DXVK
PREFIX_NAME=aoe2 DXVK_FORCE=1 ~/win-compat/scripts/setup-dxvk.sh

# Enable verbose logging
DXVK_LOG_LEVEL=info winrun aoe2 /path/to/game.exe
# then check ~/win-compat/logs/
```

### Verbose Wine debug output

```bash
WINEDEBUG="+d3d11,+dxvk,warn+all" winrun aoe2 /path/to/game.exe
```

### Full diagnostics

```bash
~/win-compat/scripts/diagnose.sh
```

---

## Licence & Credits

All components are free / open-source:

| Component | Licence | URL |
|---|---|---|
| Wine | LGPL-2.1 | https://www.winehq.org |
| wine-crossover (GCenx packaging) | Apache 2.0 | https://github.com/Gcenx/homebrew-wine |
| DXVK | zlib | https://github.com/doitsujin/dxvk |
| MoltenVK | Apache 2.0 | https://github.com/KhronosGroup/MoltenVK |
| Vulkan-Loader | Apache 2.0 | https://github.com/KhronosGroup/Vulkan-Loader |
| Winetricks | LGPL-2.1 | https://github.com/Winetricks/winetricks |
| QEMU | GPL-2.0 | https://www.qemu.org |
| UTM (optional) | Apache 2.0 | https://mac.getutm.app |
