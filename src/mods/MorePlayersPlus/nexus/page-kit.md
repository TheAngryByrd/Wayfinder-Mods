# MorePlayersPlus Nexus Mods page kit

This kit contains the text for the Nexus Mods page and the upload form. The
author creates the page, uploads the archive, and publishes. The page
description is in [description.bbcode](description.bbcode).

## Page fields

| Field | Value |
|---|---|
| Game | Wayfinder (https://www.nexusmods.com/games/wayfinder) |
| Mod name | MorePlayersPlus |
| Category | Miscellaneous |
| Version | 1.0.0 |
| Description | Paste [description.bbcode](description.bbcode). |

Summary (about 215 characters):

```text
The host can set the co-op player limit from 3 through 25 players. The limit includes the host. The default is 25. Only the host needs the mod. The mod needs UE4SS 3.0.1 (not included). No test used more than 5 players.
```

## File upload fields

| Field | Value |
|---|---|
| Archive | `dist/Wayfinder-MorePlayersPlus-NexusMods.zip` |
| File name | MorePlayersPlus |
| File version | 1.0.0 |
| Category | Main files |
| Requirements pop-up | On |

Keep the version out of the file name. The version field shows it.

File description (about 185 characters):

```text
Extract into the Wayfinder folder that contains Wayfinder.exe. Requires UE4SS 3.0.1, which is not included. Includes the Wayfinder UE4SS signature file. Only the host needs this mod.
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
| Modification permission | Get the author's permission. Changes to the Lua session-limit approach also need FuniWF's permission. |
| Conversion permission | Not allowed. FuniWF does not allow conversions of More Players. |
| Asset use permission | Get the author's permission. If you reuse GUObjectArray.lua, credit FuniWF. |
| Asset use in sold mods | Not allowed. FuniWF does not allow this use. |
| Asset use in mods that earn Donation Points | Author decision. FuniWF allows Donation Points. |
| Donation Points | Author decision. |

Author notes:

```text
Only the host needs this mod. Joining players need no mod. To report a problem, attach UE4SS.log and MorePlayersPlus.log from Wayfinder\Atlas\Binaries\Win64. Before you share a log, remove the names and IDs of other players and your Windows user name.
```

File credits:

```text
FuniWF, for More Players and the Lua session-limit approach, used with permission. FuniWF, for the Wayfinder UE4SS signature from the UE4SS setup guide linked on https://www.nexusmods.com/wayfinder/mods/9. Tsuda Kageyu, for MinHook (BSD 2-clause license). Vyacheslav Patkov, for the Hacker Disassembler Engine in MinHook (BSD 2-clause license). The RE-UE4SS project, for UE4SS (MIT license). Airship Syndicate, for Wayfinder. Airship Syndicate does not make or support this mod.
```

## Tags

- AI-Generated Content (code)
- AI Media (page text)
- Gameplay
- Quality of Life
- Utilities for Players
- 5-6 Players
- Advanced Setup

Confirm each tag name in the Wayfinder tag picker. Do not add a tag for more
than 6 players until a test uses that number.

## Changelog

```text
Version 1.0.0
- First public release.
- Sets the co-op player limit from MaxPlayers in config.ini. Supported values: 3 through 25. Default: 25. The limit includes the host.
- The Lua script and the native DLL use the same MaxPlayers rule. The last valid line sets the limit. If no line is valid, the mod uses 25.
- The native DLL changes six instructions in the memory of the running game after it checks their bytes. It uses MinHook fallback hooks only when an instruction group does not match.
- When both instruction groups apply, the DLL activates no MinHook hook.
- The host keeps the "+Party Member" and "Code" controls in the pause menu until the party reaches MaxPlayers.
- The session stays open, with current session browser data, until the party reaches MaxPlayers.
- The archive includes the Wayfinder UE4SS signature file and the MinHook and UE4SS license notices.
```

## Screenshots

Show no names or IDs of other players in any image.

1. Header image: the text "MorePlayersPlus - co-op limit 3 through 25, host
   only" on a Wayfinder screenshot of the host character alone.
2. `config.ini` in a text editor with `MaxPlayers=25` and
   `PartyUiDiagnostics=0`. Crop paths that show a Windows user name.
3. File Explorer view of `Mods\MorePlayersPlus` and `UE4SS_Signatures`. Crop
   the address bar if it shows a Windows user name.
4. `UE4SS.log` with the five startup lines and the `first call` line. Do not
   show `Join diagnostic` lines.
5. `MorePlayersPlus.log` with the startup lines. Crop the `path=` text of the
   `Config` line. Do not show `Steam rich presence keys=` lines.
6. The pause menu party page with the host alone and the `+Party Member` and
   `Code` controls.
7. Optional: gameplay with 4 or 5 players. Get consent from the players. Blur
   all other names, nameplates, and portraits.

Do not use screenshots of the Steam friends list, the Steam overlay invite
list, Discord, or session browser cards of other hosts.

## Release checklist

Do these steps in this order:

1. Ask FuniWF in a Nexus forum private message to confirm three items:
   - the permission covers the Lua session-limit approach;
   - the permission covers the GUObjectArray.lua signature in MorePlayersPlus
     and SkipStartupWarnings;
   - FuniWF accepts the name MorePlayersPlus.
2. If FuniWF confirms the signature, add "used with FuniWF's permission" to the
   signature credit in both READMEs and both pages.
3. Run the 1.0.0 runtime tests in
   [the release plan](../../../../lode/plans/nexus-release.md): a solo start,
   Steam friends list `Join Game`, a Steam overlay invite, and both mods
   together.
4. Update the text after the tests:
   - If all tests pass, delete "Version 1.0.0 has not yet been tested with a
     joining player." from the README and the page.
   - Delete "Version 1.0.0 of the two mods has not yet been tested together."
     from both READMEs.
   - If `Join Game` fails, remove it from "How players join".
5. Rebuild both archives after the last README change:
   `.\build.ps1 -Mod MorePlayersPlus,SkipStartupWarnings`.
6. Decide Donation Points.
7. In the upload form, confirm the summary and file description limits.
8. Use the description preview. Make sure that `[line]`, numbered lists, and
   the `[MorePlayersPlus]` text in code blocks show correctly. If `[line]`
   shows as text, delete those lines.
9. After the upload, check the VirusTotal result. If Nexus quarantines the
   file, email support@nexusmods.com with the page link. Do not delete the
   file.
