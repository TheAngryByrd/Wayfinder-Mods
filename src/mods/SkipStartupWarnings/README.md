# Wayfinder SkipStartupWarnings

SkipStartupWarnings closes the epilepsy and autosave warning pages when
Wayfinder starts. It can also select and load an existing save profile.
The mod preserves the normal in-game autosave indicator.

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

The default configuration skips both warning pages and loads the first profile:

```ini
SkipEpilepsyWarning=1
SkipAutoSaveWarning=1
AutoLoadProfile=1
```

Set a warning option to `0` to show that warning.

`AutoLoadProfile` uses the profile numbers shown in Wayfinder. Set it to `1`
for the first profile or `2` for the second profile. Set it to `0` to keep the
profile selector open.

The mod loads only a profile that contains save data. An empty, missing, or
unreadable profile leaves the profile selector open. Restart Wayfinder after
each configuration change.

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

Start Wayfinder. The game must continue without both warning pages. With the
default configuration, the game must also load the first existing profile.

Open this file:

```text
Wayfinder\Atlas\Binaries\Win64\UE4SS.log
```

Confirm that the file contains these messages:

```text
[SkipStartupWarnings] Config epilepsy=enabled autosave=enabled profile=1
[SkipStartupWarnings] Hook ready: epilepsy
[SkipStartupWarnings] Hook ready: autosave
[SkipStartupWarnings] Profile auto-load ready: profile 1
[SkipStartupWarnings] Skipped: epilepsy
[SkipStartupWarnings] Skipped: autosave
[SkipStartupWarnings] Load requested: profile 1
```

## Compatibility

SkipStartupWarnings can run with the Nexus Mods No-Intro video replacer.
The video replacer controls logo videos. SkipStartupWarnings controls two UMG warning pages.

SkipStartupWarnings does not disable `WFAutoSaveOverlay`. Wayfinder can still show
its normal autosave indicator during gameplay.

Profile auto-loading uses Wayfinder's existing profile selection and load
functions. The mod does not edit or replace save files.

UE4SS loads explicit `mods.txt` entries before mods that use only `enabled.txt`.
If another mod blocks later startup mods, add this line near the top of
`Atlas\Binaries\Win64\Mods\mods.txt`:

```text
SkipStartupWarnings : 1
```

The `enabled.txt` file can remain installed. UE4SS does not start the same mod twice.

## Troubleshooting

If a warning remains visible, search `UE4SS.log` for `[SkipStartupWarnings]`.

If the profile selector remains visible, search the same log for a profile
message. The mod leaves the selector open when the configured profile is empty,
missing, unreadable, or cannot be selected.

`Hook unavailable` means the current Wayfinder build changed or did not load the expected Blueprint function.

`Airship menu library is unavailable` means the mod could not access Wayfinder's menu service.

If UE4SS does not report `Starting Lua mod 'SkipStartupWarnings'`, add the
`mods.txt` entry from the compatibility section.

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

Profile auto-loading waits for `WFProfileSelectPage:InternalProfileInitialized`.
It finds the matching `WFSaveProfileWidget`, checks `bHasData`, and activates the
widget's normal `OnBaseButtonClicked` function. It calls `CreateOrLoadProfile`
only after Wayfinder reports the configured profile as selected with save data.
