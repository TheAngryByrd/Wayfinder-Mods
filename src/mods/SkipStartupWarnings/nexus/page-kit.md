# SkipStartupWarnings Nexus Mods page kit

This kit contains the text for the Nexus Mods page and the upload form. The
author creates the page, uploads the archive, and publishes. The page
description is in [description.bbcode](description.bbcode).

## Page fields

| Field | Value |
|---|---|
| Game | Wayfinder (https://www.nexusmods.com/games/wayfinder) |
| Mod name | SkipStartupWarnings |
| Category | Miscellaneous |
| Version | 1.0.0 |
| Description | Paste [description.bbcode](description.bbcode). |

Summary (about 220 characters):

```text
This mod closes the epilepsy and autosave warning pages when Wayfinder starts. Each page has an on/off setting. The mod needs UE4SS 3.0.1. The archive does not include UE4SS. Other menus and save files stay unchanged.
```

## File upload fields

| Field | Value |
|---|---|
| Archive | `dist/Wayfinder-SkipStartupWarnings-NexusMods.zip` |
| File name | SkipStartupWarnings |
| File version | 1.0.0 |
| Category | Main files |
| Requirements pop-up | On |

Keep the version out of the file name. The version field shows it.

File description (about 230 characters):

```text
This UE4SS Lua mod closes the epilepsy and autosave warning pages at startup. It includes the Wayfinder UE4SS signature GUObjectArray.lua. UE4SS 3.0.1 is not included. Extract the archive into the folder that contains Wayfinder.exe.
```

## Requirements

| Type | Name | URL | Notes |
|---|---|---|---|
| Off-site | UE4SS 3.0.1 | https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1 | Download UE4SS_v3.0.1.zip. Extract it into Wayfinder\Atlas\Binaries\Win64. This mod includes the Wayfinder signature file. |

## Permissions and credits

The repository has no license file for the project code. These rows are
suggestions. The author confirms each row.

| Row | Suggested value |
|---|---|
| Other user's assets | Some assets in this file belong to other authors. |
| Upload permission | Select the preset that requires the author's permission. |
| Modification permission | You can change the files and release fixes or improvements if you give credit. |
| Conversion permission | Not allowed. |
| Asset use permission | You can use the files in your own mods if you give credit. If you reuse GUObjectArray.lua, credit FuniWF. |
| Asset use in sold mods | Not allowed. |
| Asset use in mods that earn Donation Points | Author decision. |
| Donation Points | Author decision. |

Author notes:

```text
This mod needs UE4SS 3.0.1, which is not included. To report a problem, attach Wayfinder\Atlas\Binaries\Win64\UE4SS.log.
```

File credits:

```text
FuniWF, for the Wayfinder UE4SS signature from the UE4SS setup guide linked on https://www.nexusmods.com/wayfinder/mods/9. The RE-UE4SS project, for the UE4SS mod loader, which is not included. Airship Syndicate, for Wayfinder. Airship Syndicate does not make or support this mod.
```

## Tags

- AI-Generated Content (code)
- AI Media (page text)
- Quality of Life
- Utilities for Players
- Advanced Setup

Confirm each tag name in the Wayfinder tag picker.

## Changelog

```text
Version 1.0.0
- First public release.
- Closes the epilepsy warning page at startup. Setting: SkipEpilepsyWarning.
- Closes the autosave warning page at startup. Setting: SkipAutoSaveWarning.
- Includes the Wayfinder UE4SS signature file GUObjectArray.lua.
```

## Screenshots

Before each capture, set Steam to Offline or turn off friend notifications.

1. Header image: the mod name and the text "Closes the epilepsy and autosave
   warning pages".
2. Before: the epilepsy warning page, with `SkipEpilepsyWarning=0`.
3. Before: the autosave warning page, with `SkipAutoSaveWarning=0`.
4. After: the title prompt after the logo videos, with both pages closed.
5. `config.ini` in a text editor with both settings at `1`.
6. `UE4SS.log` with the five `[SkipStartupWarnings]` lines. Crop paths that
   show a Windows user name.

## Release checklist

Use the checklist in the
[MorePlayersPlus page kit](../../MorePlayersPlus/nexus/page-kit.md#release-checklist).
It covers both mods. For SkipStartupWarnings, also do these steps:

1. After the combined test passes, delete "Version 1.0.0 of SkipStartupWarnings
   and MorePlayersPlus has not yet been tested together." from this page, and
   delete the matching sentence from the README.
2. If FuniWF confirms the signature permission, add "used with FuniWF's
   permission" to the signature credit.
3. Use the description preview. Make sure that the `[SkipStartupWarnings]`
   text in code blocks shows correctly.
