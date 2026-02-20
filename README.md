# aoe-crossover — AoE2 HD on Apple Silicon (M1/M2/M3) via Wine

Run **Age of Empires II HD Edition** (Steam App 221380) on an Apple Silicon Mac
with no Windows installation, no Boot Camp, and no paid software.

Tested on: **macOS 15.7.3 · Apple M1 Max · Wine CrossOver 8.0.1**

---

## How it works

Apple Silicon cannot run x86 code natively. This stack chains three open-source
layers to bridge the gap:

```
AoK HD.exe (x86 Windows)
  └─ Wine CrossOver  — translates Windows API calls → macOS API calls
       └─ Rosetta 2  — translates x86_64 machine code → arm64 machine code
            └─ wined3d — translates DirectX 9 → OpenGL → Metal
```

Wine does **not** emulate a CPU. The Wine binary itself is x86_64, so Rosetta 2
handles the CPU translation invisibly. Wine's job is purely translating Windows
API calls (file I/O, windowing, Direct3D, etc.) into their macOS equivalents.

### What about DXVK?

DXVK (D3D → Vulkan) is installed by `setup.sh` and works for many games, but
**AoE2 HD requires wined3d** instead. DXVK 2.x requires Vulkan 1.3; MoltenVK
1.2.x only provides Vulkan 1.2. DXVK 1.10.3 (Vulkan 1.1+) works on MoltenVK
but AoE2 HD still hits a `geometryShader` feature absence on Metal that causes
"Failed to initialize draw system." wined3d's OpenGL→Metal path avoids this
entirely. The launch script forces wined3d with `WINEDLLOVERRIDES="d3d9=b;..."`.

### What about Steam?

SteamCMD (headless CLI) is used to install the game files. The Steam GUI client
crashes on Wine because `steamwebhelper` requires `bcryptprimitives.dll` →
`chrome_elf.dll` init chain that Wine does not support. Once installed, the game
is launched with the **Goldberg Steam Emulator** (`gbe_fork`) — an open-source
`steam_api.dll` replacement that satisfies the game's Steam DRM check without
any Steam process running.

---

## Prerequisites

- Apple Silicon Mac (M1 / M2 / M3) running macOS 12+
- [Homebrew](https://brew.sh) installed
- A Steam account that **owns** AoE2 HD (App ID 221380)
- ~5 GB free disk space for the game + Wine prefix

---

## Full Setup (one-time)

### Step 1 — Run the bootstrap

Clone this repo (or download it) and run:

```bash
bash /path/to/aoeCrossover/bootstrap.sh
```

`bootstrap.sh` copies the `win-compat/` folder to `~/win-compat/` and runs
`setup.sh`, which:

- Installs Rosetta 2 if missing
- Taps `gcenx/wine` (best macOS Wine packaging)
- Installs: `wine-crossover`, `winetricks`, `molten-vk`, `vulkan-tools`,
  `cabextract`, `p7zip`, `qemu`
- Creates the `~/win-compat/prefixes/aoe2/` Wine prefix (Windows 10, 64-bit)
- Installs DXVK 1.10.3 into the prefix (used by other games; bypassed for AoE2 HD)

After it finishes, reload your shell:

```bash
source ~/.zshrc
```

### Step 2 — Install AoE2 HD via SteamCMD

**Keep your Steam credentials out of the repo.** Copy the template script
somewhere private, fill in your username and password, then run it:

```bash
cp ~/win-compat/scripts/steam-install.sh ~/steam-install-private.sh
```

Edit `~/steam-install-private.sh` and set:

```bash
STEAM_USER="your_steam_username"
STEAM_PASS="your_steam_password"
```

Then run it:

```bash
bash ~/steam-install-private.sh
```

SteamCMD will prompt for your Steam Guard 2FA code. The game (~1.5 GB) installs
to:

```
~/win-compat/prefixes/aoe2/drive_c/Program Files (x86)/Steam/steamapps/common/age2hd/
```

### Step 3 — Install Windows runtime dependencies

```bash
WINEPREFIX="$HOME/win-compat/prefixes/aoe2" winetricks vcrun2013 vcrun2015
WINEPREFIX="$HOME/win-compat/prefixes/aoe2" winetricks d3dx9
```

`d3dx9` installs Microsoft's official D3DX9 DLLs (versions 24–43). Wine's
built-in d3dx9 cannot convert all texture formats AoE2 HD uses (e.g. 16-bit
float normal maps → `D3DFMT_A16B16G16R16F`). The native DLLs fix this.

`winetricks d3dx9` downloads ~95 MB from Microsoft's DirectX redistributable
and takes a few minutes. The `WARNING; possible 5960 extra bytes` lines from
`cabextract` are harmless noise.

### Step 4 — Install the Goldberg Steam Emulator

```bash
bash ~/win-compat/scripts/install-goldberg.sh
```

This script:

1. Downloads `emu-win-release.7z` from
   [gbe_fork](https://github.com/Detanup01/gbe_fork/releases) (~11 MB)
2. Extracts it using `p7zip` (installed by `setup.sh`)
3. Finds the 32-bit `steam_api.dll` (PE32) in the archive
4. Backs up the original `steam_api.dll` → `steam_api.dll.original`
5. Copies Goldberg's `steam_api.dll` into the game directory
6. Writes `steam_appid.txt` containing `221380`
7. Creates `steam_settings/steam_interfaces.txt` with AoE2 HD interface strings

### Step 5 — Configure Goldberg for offline mode

Create `steam_settings/config.ini` to skip the Workshop subscription screen
(which hangs indefinitely without a real Steam connection):

```bash
cat > "$HOME/win-compat/prefixes/aoe2/drive_c/Program Files (x86)/Steam/steamapps/common/age2hd/steam_settings/config.ini" << 'EOF'
[user]
SteamId = 76561198000000001
AccountName = Player
Language = english
offline = 1

[steam]
appid = 221380
EOF
```

### Step 6 — Launch the game

```bash
bash ~/win-compat/scripts/launch-aoe2-goldberg.sh
```

The script:
- Sets the working directory to the game folder (`wine start /d ...`) so
  relative paths like `resources\_common\drs\` resolve correctly
- Forces wined3d via `WINEDLLOVERRIDES="d3d9=b;dxgi=b;d3d10core=b;d3d11=b"`
- Enables multi-threaded command stream via `WINED3D_CSMT=1`
- Silences Wine debug output via `WINEDEBUG=-all` (improves performance)
- Logs to `~/win-compat/logs/aoe2_goldberg_<timestamp>.log`

---

## Launching (every time)

```bash
bash ~/win-compat/scripts/launch-aoe2-goldberg.sh
```

**If the "Validating Subscriptions" screen appears and hangs:** press `Ctrl+C`
in the terminal — this skips past it directly to the main menu. This is the
confirmed working method. The `offline = 1` setting in `config.ini` (Step 5)
may also help but was not verified to resolve it automatically.

---

## Performance tips

AoE2 HD runs through three translation layers (Rosetta 2 + Wine + wined3d),
so some overhead vs. native Windows is unavoidable. The launch script already
applies the two biggest non-visual optimisations. In-game settings do the rest.

**Already applied in `launch-aoe2-goldberg.sh`** — nothing to change:

| Variable | Value | Why it helps |
|---|---|---|
| `WINEDEBUG` | `-all` | Silences all Wine debug logging. Without this, thousands of lines are printed to the terminal every second, burning meaningful CPU. |
| `WINED3D_CSMT` | `1` | Enables wined3d Command Stream Multi-Threading — offloads D3D command processing to a second thread, making better use of M1 Max's many cores. |

**In-game settings** (Options → Graphics) — AoE2 HD uses checkboxes, not quality
sliders. Resolution is not set in-game — it follows your desktop resolution.

| Setting | Action | Effect |
|---|---|---|
| Render 3D Water | **Uncheck** | Reverts water to the original 2D look; biggest GPU saving |
| Antialias object shadows | **Uncheck** | Removes shadow edge smoothing; noticeable gain |
| Vertical Sync | **Uncheck** | Removes frame-rate cap tied to display refresh; reduces input lag |
| Desktop resolution | Lower via System Preferences | AoE2 HD follows OS resolution — lower it there, not in-game |
| Map size | Choose smaller maps | "Ludakris" is 4× larger than "Giant" and tanks FPS significantly |

---

## Repository layout

```
aoeCrossover/
├── README.md                        ← you are here
├── bootstrap.sh                     ← single-command setup entry point
└── win-compat/
    ├── config.env                   ← shared env vars (Wine binary, MoltenVK ICD, etc.)
    ├── docs/
    │   └── README.md                ← technical reference (winrun, DXVK, winetricks)
    └── scripts/
        ├── setup.sh                 ← one-shot Homebrew + Wine + DXVK bootstrap
        ├── winrun                   ← generic launcher: winrun <prefix> <exe.exe>
        ├── setup-dxvk.sh            ← install/update DXVK in any prefix
        ├── diagnose.sh              ← print full stack diagnostics
        ├── steam-install.sh         ← SteamCMD game installer (add your own creds)
        ├── install-goldberg.sh      ← download + install Goldberg Steam emulator
        ├── launch-aoe2-goldberg.sh  ← the script you run to play
        └── launch-aoe2.sh           ← DEPRECATED (Steam -applaunch; does not work)
```

---

## Troubleshooting

> **Full troubleshooting log:** Every error encountered during the original
> setup — with root cause analysis and the exact fix — is documented in
> **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**.

### "FATAL: Storage Point #12 … does not exist"

The game is launching from the wrong working directory. Make sure you are
using `launch-aoe2-goldberg.sh`, which sets the working dir via `wine start /d`.

### "Failed to initialize draw system"

DXVK is active instead of wined3d. Check that
`WINEDLLOVERRIDES="d3d9=b;dxgi=b;d3d10core=b;d3d11=b"` is set (it is in the
launch script). This error is caused by DXVK requesting `geometryShader` and
`shaderFloat64` GPU features that Metal/Apple Silicon does not expose.

### `D3DXCreateTextureFromFileInMemoryEx Texture loading failed`

Native d3dx9 DLLs are not installed. Run:

```bash
WINEPREFIX="$HOME/win-compat/prefixes/aoe2" winetricks d3dx9
```

### Subscription screen hangs forever

Ensure `steam_settings/config.ini` exists and contains `offline = 1`. If it
still hangs, press **Ctrl+C** in the terminal — the game skips straight to the
main menu.

### Game exits immediately (code 0) with no window

Steam DRM check fired. Verify Goldberg is installed:

```bash
file "$HOME/win-compat/prefixes/aoe2/drive_c/Program Files (x86)/Steam/steamapps/common/age2hd/steam_api.dll"
# Should say: PE32 executable (DLL) ... for MS Windows
# Size should be ~15 MB (Goldberg), NOT ~200 KB (original Steam stub)
cat "$HOME/win-compat/prefixes/aoe2/drive_c/Program Files (x86)/Steam/steamapps/common/age2hd/steam_appid.txt"
# Should print: 221380
```

If either check fails, re-run `install-goldberg.sh`.

### Diagnose everything at once

```bash
bash ~/win-compat/scripts/diagnose.sh
```

---

## Technical stack — version reference

| Component | Version tested | Role |
|---|---|---|
| macOS | 15.7.3 (Sequoia) | Host OS |
| Apple M1 Max | arm64 | CPU |
| Rosetta 2 | built-in | x86_64 → arm64 translation |
| Wine CrossOver | 8.0.1 (CrossOverFOSS 23.7.1) | Windows API translation |
| wined3d | (bundled with Wine) | DirectX 9 → OpenGL → Metal |
| MoltenVK | 1.2.5 | Vulkan → Metal (for DXVK, not used by AoE2 HD) |
| DXVK | 1.10.3 | D3D → Vulkan (installed, not used by AoE2 HD) |
| Goldberg (gbe_fork) | release-2026_02_19 | Steam DRM emulator |
| SteamCMD | latest | Headless game installer |

> **Why DXVK 1.10.3 and not 2.x?** DXVK 2.x requires Vulkan 1.3. MoltenVK
> 1.2.5 only exposes Vulkan 1.2. DXVK 1.10.3 is the last release that works
> with Vulkan 1.1+. That said, AoE2 HD uses wined3d anyway — DXVK is available
> for other games you may install in the same prefix.

---

## Credits & Licences

| Component | Licence | URL |
|---|---|---|
| Wine | LGPL-2.1 | https://www.winehq.org |
| wine-crossover (GCenx) | Apache 2.0 | https://github.com/Gcenx/homebrew-wine |
| wined3d | LGPL-2.1 | (bundled with Wine) |
| DXVK | zlib | https://github.com/doitsujin/dxvk |
| MoltenVK | Apache 2.0 | https://github.com/KhronosGroup/MoltenVK |
| Goldberg gbe_fork | MIT | https://github.com/Detanup01/gbe_fork |
| winetricks | LGPL-2.1 | https://github.com/Winetricks/winetricks |
| SteamCMD | Valve (free) | https://developer.valvesoftware.com/wiki/SteamCMD |
| QEMU | GPL-2.0 | https://www.qemu.org |

---

## Legal disclaimer

**This project is not affiliated with, endorsed by, or associated with Microsoft
Corporation, Xbox Game Studios, Forgotten Empires LLC, Valve Corporation, or any
other rights holder of Age of Empires II HD Edition.** "Age of Empires" is a
registered trademark of Microsoft Corporation. All game assets, game code, and
related intellectual property belong to their respective owners.

This repository contains only shell scripts, configuration files, and
documentation. It does not contain, distribute, or reproduce any game files,
game assets, or copyrighted content from Age of Empires II HD Edition or any
other game. You must own a legitimate, purchased copy of Age of Empires II HD
Edition (Steam App ID 221380) via your own Steam account to use this setup.

### Purpose

This is a personal, non-commercial quality-of-life utility. Its sole purpose is
to help Mac users who **already own** Age of Empires II HD Edition on Steam run
the game on Apple Silicon hardware, where no officially supported macOS client
exists. This project is not monetised, not sold, and is provided free of charge
with no warranty of any kind.

### Third-party components

All third-party software used or referenced by these scripts (Wine, DXVK,
MoltenVK, Goldberg Steam Emulator, SteamCMD, winetricks, QEMU) is free and
open-source and is governed by its own respective licence. See the
[Credits & Licences](#credits--licences) table above for details. None of those
projects are affiliated with this repository.

The Goldberg Steam Emulator (`gbe_fork`) replaces the Steam API DLL solely to
allow offline play on hardware where the Steam client cannot run. It is used
here strictly within the bounds of personal, offline use by a legitimate owner
of the game.

### Licence (scripts in this repository)

The shell scripts and configuration files in this repository are released under
the **MIT Licence**:

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Note on game ownership

This setup requires that you **own Age of Empires II HD Edition on Steam**.
SteamCMD authenticates with your real Steam account to download the game files.
The Goldberg emulator is used solely to bypass the online DRM check for
offline/LAN play on hardware where the Steam client cannot run.
