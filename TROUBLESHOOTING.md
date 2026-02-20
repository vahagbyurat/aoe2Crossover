# Troubleshooting — Every Error Encountered During Setup

This document chronicles every real error hit while getting AoE2 HD running on
Apple Silicon (M1 Max, macOS 15.7.3), in the order they appeared, along with
the exact fix that resolved each one.

---

## 1. `set -euo pipefail` — unbound variable crash on macOS bash 3.2

**Symptom**

```
/Users/.../setup.sh: line 122: flags[@]: unbound variable
```

**Cause**

macOS ships with bash 3.2 (GPL2 licensing reason). The `-u` flag in
`set -euo pipefail` causes bash to treat an empty array (`"${flags[@]}"`) as an
unbound variable and abort.

**Fix**

Changed `set -euo pipefail` → `set -eo pipefail` in all four scripts
(`setup.sh`, `winrun`, `setup-dxvk.sh`, `diagnose.sh`). Also added a guard
before expanding the array:

```bash
if [[ ${#flags[@]} -gt 0 ]]; then
    brew install "${flags[@]}" "$pkg"
else
    brew install "$pkg"
fi
```

---

## 2. `mapfile: command not found`

**Symptom**

```
/Users/.../install-goldberg.sh: line 86: mapfile: command not found
```

**Cause**

`mapfile` (also known as `readarray`) is a bash 4+ built-in. macOS's system
bash is 3.2.

**Fix**

Replaced:

```bash
mapfile -t CANDIDATES < <(find "$EXTRACT_DIR" -iname "steam_api.dll")
```

With a bash 3.2-compatible `while` loop:

```bash
while IFS= read -r dll; do
  ...
done < <(find "$EXTRACT_DIR" -iname "steam_api.dll")
```

---

## 3. MoltenVK ICD not found — wrong path

**Symptom**

DXVK/Vulkan silently fell back to software rendering. `diagnose.sh` reported
"MoltenVK ICD NOT found."

**Cause**

Scripts were checking `/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json`.
Homebrew actually installs MoltenVK's ICD to:

```
/opt/homebrew/etc/vulkan/icd.d/MoltenVK_icd.json
```

**Fix**

Updated the ICD detection in `config.env`, `winrun`, `diagnose.sh`, and
`setup-dxvk.sh` to check `etc/` before `share/`:

```bash
"/opt/homebrew/etc/vulkan/icd.d/MoltenVK_icd.json"
"/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"   # fallback
```

---

## 4. DXVK 2.4 fails — requires Vulkan 1.3, MoltenVK only provides 1.2

**Symptom**

```
warn: Skipping Vulkan 1.2 adapter: Apple M1 Max
warn: A Vulkan 1.3 capable driver is required
```

DXVK initialized but then reported no usable GPU and fell back to software.

**Cause**

DXVK 2.x requires a Vulkan 1.3 driver. MoltenVK 1.2.5 (the current Homebrew
version) only exposes Vulkan 1.2.

**Fix**

Downgraded DXVK to 1.10.3, the last release that supports Vulkan 1.1+:

```bash
PREFIX_NAME=aoe2 DXVK_VERSION=1.10.3 DXVK_FORCE=1 ~/win-compat/scripts/setup-dxvk.sh
```

Also updated `config.env` to default to `1.10.3`.

> **Note:** Even DXVK 1.10.3 ultimately isn't used for AoE2 HD — see error #7.

---

## 5. Game EXE not found — wrong path after SteamCMD install

**Symptom**

```
wine: cannot find 'Z:\...\age2_x1\age2_x1.5.exe'
```

**Cause**

Initial guess at the game's EXE path was wrong. SteamCMD installed AoE2 HD
to a different subdirectory and EXE name than expected.

**Fix**

Used macOS Spotlight search (`Cmd+Space → "AoK HD.exe"`) to locate the actual
installed path:

```
~/win-compat/prefixes/aoe2/drive_c/Program Files (x86)/Steam/steamapps/common/age2hd/AoK HD.exe
```

---

## 6. `c0000135` — DLL not found on launch

**Symptom**

```
err:module:import_dll Library MSVCP120.dll not found
wine: Unhandled exception 0xc0000135 in thread 00cc
```

**Cause**

AoE2 HD requires the Visual C++ 2013 and 2015 runtimes, which are not present
in a fresh Wine prefix.

**Fix**

```bash
WINEPREFIX="$HOME/win-compat/prefixes/aoe2" winetricks vcrun2013 vcrun2015
```

---

## 7. Steam DRM — `SteamAPI_RestartAppIfNecessary()` kills the game

**Symptom**

The game launched, showed a Steam login prompt or immediately exited. Log showed:

```
SteamAPI_RestartAppIfNecessary(221380) returning true, launching Steam
```

**Cause**

AoE2 HD calls `SteamAPI_RestartAppIfNecessary()` at startup. If this returns
`true`, the game self-terminates and expects Steam to relaunch it. Without a
running Steam client, the game simply exits.

**Attempted fix 1 (didn't work):** Place `steam_appid.txt` containing `221380`
next to the EXE. The original `steam_api.dll` ignores this.

**Attempted fix 2 (didn't work):** Run Steam in the background via Wine and use
`-applaunch 221380`. Blocked by error #8 below.

**Working fix:** Replace `steam_api.dll` with the Goldberg Steam Emulator — see
`install-goldberg.sh`. Goldberg's stub `SteamAPI_RestartAppIfNecessary()` always
returns `false`, so the game proceeds normally.

---

## 8. `steamwebhelper` crash — Steam GUI never initializes

**Symptom**

A "steamwebhelper is not responding" macOS dialog appeared. Log showed:

```
err:module:import_dll Library bcryptprimitives.dll (which is needed by ...chrome_elf.dll) not found
```

Steam's window never appeared, so `-applaunch 221380` never fired.

**Cause**

`steamwebhelper.exe` (Steam's Chromium-based UI process) requires
`bcryptprimitives.dll`, a Windows cryptography primitive DLL that Wine does not
implement. Without it, `chrome_elf.dll` fails to initialize, which prevents the
entire Steam UI from loading.

**Fix**

There is no clean fix for this on Wine without proprietary components. The
solution is to avoid the Steam GUI entirely and use the Goldberg emulator
instead (see error #7).

---

## 9. Goldberg download URL returned HTML — not a zip

**Symptom**

```
Archive:  /Users/.../goldberg_emulator.zip
  End-of-central-directory signature not found.
```

The downloaded file was 163 bytes of HTML, not a zip archive.

**Cause**

The GitLab permalink URL
`https://gitlab.com/Mr_Goldberg/goldberg_emulator/-/releases/permalink/latest/downloads/goldberg_emulator.zip`
redirected to a GitLab login or error page instead of the binary.

**Fix**

Switched to **gbe_fork** (the actively maintained Goldberg fork) on GitHub.
Used GitHub's `expanded_assets` API endpoint to discover the actual filenames:

```bash
curl -sL "https://github.com/Detanup01/gbe_fork/releases/expanded_assets/release-2026_02_19" \
  | grep -oE 'href="[^"]*releases/download[^"]*"'
```

The correct archive is `emu-win-release.7z` (not a zip), downloaded from:

```
https://github.com/Detanup01/gbe_fork/releases/download/release-2026_02_19/emu-win-release.7z
```

---

## 10. `FATAL: Storage Point #12 'resources\_common\drs\retail-campaigns\' does not exist`

**Symptom**

A game error dialog appeared immediately after launch. The directory listed
in the error *did* exist on disk.

**Cause**

Wine launched `AoK HD.exe` with the working directory set to the Mac user's
home folder (`~`). AoE2 HD resolves `resources\...` as a *relative path* from
wherever the EXE was invoked. From `~`, that path doesn't exist.

**Fix**

Changed the Wine invocation from:

```bash
wine64 "C:/Program Files .../AoK HD.exe"
```

to:

```bash
wine64 start /d "C:\\Program Files (x86)\\Steam\\steamapps\\common\\age2hd\\" "AoK HD.exe"
```

`wine start /d <dir>` sets the working directory for the launched process,
matching how Windows normally starts games from their own folder.

---

## 11. "Failed to initialize draw system" (DXVK + Metal feature absence)

**Symptom**

A game error dialog: **"Failed to initialize draw system"** appeared immediately
after the game window opened. Log showed:

```
[mvk-error] VK_ERROR_FEATURE_NOT_PRESENT: vkCreateDevice(): Requested physical
device feature specified by the 5th flag in VkPhysicalDeviceFeatures is not
available on this device.
[mvk-error] VK_ERROR_FEATURE_NOT_PRESENT: vkCreateDevice(): Requested physical
device feature specified by the 39th flag in VkPhysicalDeviceFeatures is not
available on this device.
```

**Cause**

The 5th and 39th flags in `VkPhysicalDeviceFeatures` are:
- Flag 4: `geometryShader` — Metal/Apple Silicon does not support geometry shaders
- Flag 39: `shaderFloat64` — 64-bit float in shaders, not supported on Apple Silicon

DXVK was requesting these features. Even though MoltenVK created the device
anyway (logging non-fatal errors), the game's draw system initialization then
failed internally.

**Fix**

Bypassed DXVK entirely for AoE2 HD by forcing Wine's built-in `wined3d`
renderer with:

```bash
WINEDLLOVERRIDES="d3d9=b;dxgi=b;d3d10core=b;d3d11=b"
```

`=b` means "use builtin" (wined3d), overriding the native DXVK DLLs in the
registry. wined3d's OpenGL→Metal path does not request `geometryShader` or
`shaderFloat64`.

---

## 12. "Validating Subscriptions" screen hangs indefinitely

**Symptom**

At startup, AoE2 HD showed a "Validating Subscriptions — Registering local
mods:" dialog that never closed. The game appeared to hang here permanently.

**Cause**

AoE2 HD queries the Steam Workshop API at startup to validate subscribed mods.
Without a real Steam connection, Goldberg's Workshop emulation either timed out
very slowly or blocked waiting for a network response.

**Confirmed working fix:** Click the game window to make sure it has focus,
then press `Ctrl+C`. This sends a cancel/interrupt keyboard event to the game
which breaks out of the subscription check and drops straight to the main menu.
The game continues normally from there.

**Attempted fix (unverified):** Creating `steam_settings/config.ini` with
`offline = 1` was tried as a way to make Goldberg skip the Workshop query
entirely, but was never confirmed to resolve the hang automatically. Ctrl+C in
the game window remains the only verified method.

---

## 13. `D3DXCreateTextureFromFileInMemoryEx Texture loading failed` — crash on new game

**Symptom**

The game reached the main menu but crashed when starting a new game. Log showed:

```
fixme:d3dx:get_format_info Unknown format 0x3c (as FOURCC "<\x00\x00\x00").
fixme:d3dx:D3DXLoadSurfaceFromMemory Unsupported format conversion 0x14 -> 0x3c.
fixme:d3dx:D3DXCreateTextureFromFileInMemoryEx Texture loading failed.
```

**Cause**

Format `0x3c` is a 16-bit floating-point texture format (`D3DFMT_A16B16G16R16F`)
used by AoE2 HD's normal maps (e.g. `resources\_common\terrain\water\normal0.png`).
Wine's built-in `d3dx9` implementation does not support this format conversion.

**Fix**

Installed Microsoft's official D3DX9 DLLs via winetricks, which handle all
format conversions:

```bash
WINEPREFIX="$HOME/win-compat/prefixes/aoe2" winetricks d3dx9
```

This installs `d3dx9_24.dll` through `d3dx9_43.dll` (both 32-bit and 64-bit)
from the official June 2010 DirectX redistributable. The `WARNING; possible
5960 extra bytes at end of file` messages from `cabextract` are harmless.

---

## 14. Script permission denied — cannot execute

**Symptom**

```
bash: ./install-goldberg.sh: Permission denied
```

**Cause**

Files synced via the Cowork workspace folder did not have the execute bit set
on the Mac filesystem.

**Fix**

Use `bash script.sh` instead of `./script.sh`. No `chmod +x` needed — bash
reads the file directly rather than executing it as a binary. Alternatively:

```bash
chmod +x ~/win-compat/scripts/*.sh ~/win-compat/scripts/winrun
```

---

## Summary table

| # | Error | Root cause | Fix |
|---|---|---|---|
| 1 | `flags[@]: unbound variable` | bash 3.2 + `set -u` + empty array | `set -eo` + array length guard |
| 2 | `mapfile: command not found` | bash 3.2 lacks `mapfile` | Replace with `while IFS= read -r` loop |
| 3 | MoltenVK ICD not found | Wrong path (`share/` vs `etc/`) | Check `etc/vulkan/icd.d/` first |
| 4 | DXVK skips M1 adapter | DXVK 2.x needs Vulkan 1.3, MoltenVK provides 1.2 | Use DXVK 1.10.3 |
| 5 | EXE not found | Wrong path guessed | Spotlight to find real path |
| 6 | `c0000135` crash | Missing VC++ 2013/2015 runtimes | `winetricks vcrun2013 vcrun2015` |
| 7 | `SteamAPI_RestartAppIfNecessary` exits | Steam DRM, no Steam client running | Goldberg emulator (`install-goldberg.sh`) |
| 8 | `steamwebhelper` crash | Missing `bcryptprimitives.dll` | Abandon Steam GUI; use Goldberg |
| 9 | Goldberg download = HTML | Wrong GitLab permalink URL | Use gbe_fork on GitHub (`emu-win-release.7z`) |
| 10 | `resources\...\retail-campaigns\` not found | Wrong working directory | `wine start /d "game dir"` |
| 11 | "Failed to initialize draw system" | DXVK needs `geometryShader` + `shaderFloat64`, Metal doesn't have them | `WINEDLLOVERRIDES=d3d9=b;...` (use wined3d) |
| 12 | Subscription screen hangs | Workshop API query with no Steam | **Ctrl+C in the game window** (confirmed); `offline = 1` in config.ini (unverified) |
| 13 | Texture load failed | Wine d3dx9 can't convert 16-bit float formats | `winetricks d3dx9` (native Microsoft DLLs) |
| 14 | Permission denied on scripts | No execute bit in workspace | Use `bash script.sh` or `chmod +x` |

---

## Performance optimisations applied

Once the game was running, it was noticeably laggy. This is expected — three
translation layers (Rosetta 2 + Wine + wined3d) all add overhead. The following
changes were made and are now baked into `launch-aoe2-goldberg.sh`.

### `WINEDEBUG=-all` — biggest CPU win

The initial launch script used `WINEDEBUG=err+all,warn+module,warn+loaddll`.
This caused Wine to print thousands of debug lines per second to the terminal —
every DLL load, every unimplemented stub, every module warning. Writing all that
output burns real CPU time. Setting `WINEDEBUG=-all` silences everything and
gave a noticeable framerate improvement with no downside during normal play.

To re-enable debug output for troubleshooting, temporarily change it in the
launch script:

```bash
WINEDEBUG="err+all,warn+module,warn+loaddll" \
```

### `WINED3D_CSMT=1` — multi-core GPU command processing

wined3d by default processes its internal D3D command stream on a single thread.
Setting `WINED3D_CSMT=1` (Command Stream Multi-Threading) moves that work to a
dedicated second thread, freeing the main thread and making better use of the
M1 Max's performance cores. This is a safe flag with no known compatibility
issues for AoE2 HD.

### In-game graphics settings

AoE2 HD Edition (2013) has a much simpler options menu than the Definitive
Edition — graphics options are checkboxes, not quality sliders. There is no
in-game resolution setting; the game follows whatever your desktop resolution
is set to in System Preferences.

| Setting | Action | Reason |
|---|---|---|
| Render 3D Water | **Uncheck** | Biggest GPU saving; reverts water to the original flat 2D look |
| Antialias object shadows | **Uncheck** | Removes shadow edge smoothing; noticeable performance gain |
| Vertical Sync | **Uncheck** | Removes the display-refresh frame cap; reduces input lag |
| Desktop resolution | Lower via System Preferences | AoE2 HD renders at OS resolution — lower it there if needed |
| Map size | Choose smaller maps | "Ludakris" is 4× the size of "Giant" and has a severe FPS impact |

> Note: "Terrain quality", "Shadow quality", and resolution dropdowns are
> **Definitive Edition** settings and do not exist in AoE2 HD Edition.
