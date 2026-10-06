# Wayfinder SkipStartupWarnings

SkipStartupWarnings closes the epilepsy and autosave warning pages when
Wayfinder starts. The mod leaves the title prompt, profile selector, main menu,
and in-game autosave indicator unchanged.

The mod installs one UE4SS Lua script, a configuration file, an `enabled.txt`
file, and a Wayfinder-specific UE4SS signature. It contains no DLL and no
executable. It does not replace the Wayfinder executable, game packages,
videos, or save files.

## Contents

<!-- toc:start -->
- [Configuration](#configuration)
- [Install](#install)
  - [Install UE4SS 3.0.1](#install-ue4ss-301)
  - [Install SkipStartupWarnings](#install-skipstartupwarnings)
- [Confirm the mod is working](#confirm-the-mod-is-working)
- [Compatibility](#compatibility)
- [Known limits](#known-limits)
- [Uninstall](#uninstall)
- [Troubleshooting](#troubleshooting)
- [Build](#build)
- [Technical notes](#technical-notes)
- [Attribution](#attribution)
<!-- toc:end -->

## Configuration

Close Wayfinder. Then edit this installed file:

```text
Wayfinder\Atlas\Binaries\Win64\Mods\SkipStartupWarnings\config.ini
```

The default configuration skips both warning pages:

```ini
SkipEpilepsyWarning=1
SkipAutoSaveWarning=1
```

Set a warning option to `0` to show that warning. Restart Wayfinder after each
configuration change.

The mod uses these rules for each line:

- The key must be exactly `SkipEpilepsyWarning` or `SkipAutoSaveWarning`. The
  key is case-sensitive.
- The value must be `0` or `1`.
- You can put spaces or tabs before the key, around `=`, and after the value.
- The mod ignores a line that has other text after the value.
- If more than one line is valid for a key, the last valid line sets the value.
- If a key has no valid line, the mod uses `1`.
- If `config.ini` does not exist, `UE4SS.log` shows `Config not found`. The mod
  then skips both pages.

## Install

This package does not contain UE4SS. Install the compatible Wayfinder UE4SS
3.0.1 setup first. Vortex does not support Wayfinder. Install the files
manually.

### Install UE4SS 3.0.1

1. Download [`UE4SS_v3.0.1.zip`](https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip).
2. Close Wayfinder.
3. Open the Wayfinder installation directory in Steam.
4. Open `Atlas\Binaries\Win64`.
5. If an earlier UE4SS version left an `xinput1_3.dll` file in this directory,
   delete it.
6. Extract the UE4SS archive into `Atlas\Binaries\Win64`.
7. Do not start Wayfinder until you install SkipStartupWarnings.

The SkipStartupWarnings archive installs the custom Wayfinder signature at:

```text
Wayfinder\Atlas\Binaries\Win64\UE4SS_Signatures\GUObjectArray.lua
```

UE4SS uses this signature to find the global object array. Lua mods cannot
load when this lookup fails.

See the [official UE4SS installation guide](https://docs.ue4ss.com/installation-guide)
for additional information.

### Install SkipStartupWarnings

1. Close Wayfinder.
2. Extract the SkipStartupWarnings archive into the Wayfinder installation directory.
3. Permit file replacement when Windows asks for confirmation.

The archive contains an `Atlas` folder and `SkipStartupWarnings-README.md`. The
`Atlas` folder of the archive must merge with the `Atlas` folder of Wayfinder.

Confirm that these files exist:

```text
Wayfinder\Atlas\Binaries\Win64\dwmapi.dll
Wayfinder\Atlas\Binaries\Win64\UE4SS.dll
Wayfinder\Atlas\Binaries\Win64\UE4SS-settings.ini
Wayfinder\Atlas\Binaries\Win64\UE4SS_Signatures\GUObjectArray.lua
Wayfinder\Atlas\Binaries\Win64\Mods\SkipStartupWarnings\enabled.txt
Wayfinder\Atlas\Binaries\Win64\Mods\SkipStartupWarnings\config.ini
Wayfinder\Atlas\Binaries\Win64\Mods\SkipStartupWarnings\Scripts\main.lua
```

UE4SS 3.0.1 installs the first three files. This archive installs the other
files.

## Confirm the mod is working

Start Wayfinder. The game must continue without the epilepsy and autosave
warning pages. Use the normal controls at the title prompt and all later menus.

Open this file:

```text
Wayfinder\Atlas\Binaries\Win64\UE4SS.log
```

Confirm that the file contains these messages:

```text
[SkipStartupWarnings] Config epilepsy=enabled autosave=enabled
[SkipStartupWarnings] Hook ready: epilepsy
[SkipStartupWarnings] Hook ready: autosave
[SkipStartupWarnings] Skipped: epilepsy
[SkipStartupWarnings] Skipped: autosave
```

For each page that you set to `0`, the log contains the related line:

```text
[SkipStartupWarnings] Epilepsy warning skip disabled
[SkipStartupWarnings] Autosave warning skip disabled
```

## Compatibility

SkipStartupWarnings can run with the Nexus Mods No-Intro video replacer.
The video replacer controls logo videos. SkipStartupWarnings controls two UMG warning pages.

SkipStartupWarnings does not disable `WFAutoSaveOverlay`. Wayfinder can still show
its normal autosave indicator during gameplay.

SkipStartupWarnings loads through its own `enabled.txt` file. It needs no
`mods.txt` entry. MorePlayersPlus uses the same signature file. Version 1.0.0
of the two mods has not yet been tested together.

## Known limits

- If a Wayfinder update changes the warning pages, the hooks can fail.
  `UE4SS.log` then shows `Hook unavailable`, and the warning page stays.
- If the page transition or the menu removal fails, the warning page stays
  available. Continue with the normal controls.

## Uninstall

MorePlayersPlus and other UE4SS mods for Wayfinder can use the same signature
file.

To disable the mod and keep its configuration, delete this file:
`Wayfinder\Atlas\Binaries\Win64\Mods\SkipStartupWarnings\enabled.txt`.

To remove the mod:

1. Close Wayfinder.
2. Delete this folder: `Wayfinder\Atlas\Binaries\Win64\Mods\SkipStartupWarnings`.
3. Delete this file: `Wayfinder\SkipStartupWarnings-README.md`.
4. If you also remove UE4SS, delete this file:
   `Wayfinder\Atlas\Binaries\Win64\UE4SS_Signatures\GUObjectArray.lua`.

Keep `GUObjectArray.lua` while UE4SS stays installed. To remove UE4SS, refer
to the UE4SS documentation.

## Troubleshooting

If a warning remains visible, search `UE4SS.log` for `[SkipStartupWarnings]`.
UE4SS overwrites `UE4SS.log` at each start. Copy the file before you start
Wayfinder again.

- `Hook unavailable` means that the current Wayfinder build changed or did not
  load the expected Blueprint function.
- `Airship menu library is unavailable` means that the mod could not access
  Wayfinder's menu service.
- `Skip canceled` or `Unable to finish` means that the mod could not close the
  page. The warning page stays available.
- `Unable to remove` or `did not remove` means that the menu removal failed.
  The warning page stays available.
- If UE4SS does not report `Starting Lua mod 'SkipStartupWarnings'`, confirm
  that `enabled.txt` exists.
- If the folder `Mods\MorePlayers` exists, delete it. This folder is from an
  earlier unreleased build. An old build can stop UE4SS from starting later Lua
  mods.

For a Wayfinder crash, collect these files:

```text
%LOCALAPPDATA%\Wayfinder\Saved\Logs\Atlas.log
%LOCALAPPDATA%\Wayfinder\Saved\Crashes
```

`Atlas.log` can contain player names and online IDs. Remove them before you
post the log in public.

## Build

Run this command from the repository root:

```powershell
.\build.ps1 -Mod SkipStartupWarnings
```

The build creates these outputs:

```text
dist\NexusMods\SkipStartupWarnings
dist\Wayfinder-SkipStartupWarnings-NexusMods.zip
```

## Technical notes

The Lua script registers post-construction hooks for these Blueprint functions:

```text
/Game/UI/UI_WF_Blueprints/AutoSave/UI_EpilepsyWarningPage.UI_EpilepsyWarningPage_C:Construct
/Game/UI/UI_WF_Blueprints/AutoSave/UI_AutoSaveWarningPage.UI_AutoSaveWarningPage_C:Construct
```

Each hook finishes the page transition and calls Wayfinder's
`RemoveFromAirshipMenu` function. A failed removal leaves the warning page available.

## Attribution

- The Wayfinder signature in `GUObjectArray.lua` comes from FuniWF's UE4SS
  setup guide for Wayfinder. FuniWF links this guide from the
  [More Players mod page](https://www.nexusmods.com/wayfinder/mods/9).
- UE4SS (RE-UE4SS project) loads this mod. The archive does not include UE4SS
  binaries.
- Wayfinder is a game by Airship Syndicate. Airship Syndicate does not make or
  support this mod.
- AI tools (Claude and Codex) generated much of the code and documentation.
