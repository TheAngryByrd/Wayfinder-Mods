# Wayfinder SkipStartupWarnings

SkipStartupWarnings closes the epilepsy and autosave warning pages when
Wayfinder starts. The mod leaves the title prompt, profile selector, main menu,
and in-game autosave indicator unchanged.

The mod installs one UE4SS Lua script and a Wayfinder-specific UE4SS signature.
It does not replace the Wayfinder executable, game packages, videos, or save files.

## Contents

<!-- toc:start -->
- [Configuration](#configuration)
- [Install](#install)
  - [Install UE4SS 3.0.1](#install-ue4ss-301)
  - [Install SkipStartupWarnings](#install-skipstartupwarnings)
- [Confirm the mod is working](#confirm-the-mod-is-working)
- [Compatibility](#compatibility)
- [Troubleshooting](#troubleshooting)
- [Build](#build)
- [Technical notes](#technical-notes)
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

## Install

This package does not contain UE4SS. Install the compatible Wayfinder UE4SS
3.0.1 setup first.

### Install UE4SS 3.0.1

1. Download [`UE4SS_v3.0.1.zip`](https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip).
2. Close Wayfinder.
3. Open the Wayfinder installation directory in Steam.
4. Open `Atlas\Binaries\Win64`.
5. Remove an old `xinput1_3.dll` file from this directory.
6. Extract the UE4SS archive into `Atlas\Binaries\Win64`.
7. Do not start Wayfinder until you install SkipStartupWarnings.

The SkipStartupWarnings archive installs the custom Wayfinder signature at:

```text
Wayfinder\Atlas\Binaries\Win64\UE4SS_Signatures\GUObjectArray.lua
```

See the [official UE4SS installation guide](https://docs.ue4ss.com/installation-guide)
for additional information.

### Install SkipStartupWarnings

1. Close Wayfinder.
2. Extract the SkipStartupWarnings archive into the Wayfinder installation directory.
3. Permit file replacement when Windows asks for confirmation.

Confirm that these files exist:

```text
Wayfinder\Atlas\Binaries\Win64\Mods\SkipStartupWarnings\enabled.txt
Wayfinder\Atlas\Binaries\Win64\Mods\SkipStartupWarnings\config.ini
Wayfinder\Atlas\Binaries\Win64\Mods\SkipStartupWarnings\Scripts\main.lua
```

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

## Compatibility

SkipStartupWarnings can run with the Nexus Mods No-Intro video replacer.
The video replacer controls logo videos. SkipStartupWarnings controls two UMG warning pages.

SkipStartupWarnings does not disable `WFAutoSaveOverlay`. Wayfinder can still show
its normal autosave indicator during gameplay.

SkipStartupWarnings is compatible with the current MorePlayers release. Both
mods load through their `enabled.txt` files. MorePlayers defers its native hook
activation until the UE4SS event loop starts, so it does not block this mod.
No `mods.txt` entry is required.

## Troubleshooting

If a warning remains visible, search `UE4SS.log` for `[SkipStartupWarnings]`.

`Hook unavailable` means that the current Wayfinder build changed or did not
load the expected Blueprint function.

`Airship menu library is unavailable` means that the mod could not access
Wayfinder's menu service.

If UE4SS does not report `Starting Lua mod 'SkipStartupWarnings'`, confirm that
`enabled.txt` exists and update MorePlayers if an older release is installed.

Remove the mod's `enabled.txt` file to disable the mod without deleting its configuration.

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
