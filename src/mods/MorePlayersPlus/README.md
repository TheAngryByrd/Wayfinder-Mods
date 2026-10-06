# Wayfinder MorePlayersPlus

This mod lets a Wayfinder host play with more than three people. Set the maximum
player count from 3 through 25. Only the host needs the mod. Wayfinder
scales encounter difficulty and enemies for the number of connected players.

While Wayfinder runs, the mod changes:

- Wayfinder's maximum player setting.
- The number of public spaces reported by the online session.
- The maximum number of members in the Steam lobby.
- The party maximum in the Discord party data.
- The player count at which Wayfinder publishes the session as full.
- The visibility of the host's party controls in the pause menu.

The mod installs a Lua script, a native DLL, license notices, and a
Wayfinder-specific UE4SS signature. The native DLL changes six instructions in
the memory of the running Wayfinder process. The mod does not change the
Wayfinder executable on disk, the game packages, or the save files.

## Contents

<!-- toc:start -->
- [Configuration](#configuration)
- [Install](#install)
  - [Install UE4SS 3.0.1](#install-ue4ss-301)
  - [Install MorePlayersPlus](#install-moreplayersplus)
- [Confirm the mod is working](#confirm-the-mod-is-working)
  - [Troubleshooting](#troubleshooting)
- [How players join](#how-players-join)
- [Known limits](#known-limits)
- [Uninstall](#uninstall)
- [Compatibility](#compatibility)
- [Build](#build)
- [Technical notes](#technical-notes)
- [Attribution](#attribution)
<!-- toc:end -->

## Configuration

Close Wayfinder. Then edit the installed configuration file:

```text
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayersPlus\config.ini
```

Set the required values:

```ini
MaxPlayers=25
PartyUiDiagnostics=0
```

Supported values are 3 through 25. The Lua script and native DLL read this same
setting when Wayfinder starts. Restart Wayfinder after you change the file.

The Lua script and native DLL use the same rule for each `MaxPlayers` line:

- The key must be exactly `MaxPlayers`. The key is case-sensitive.
- The key must be the first text on the line. The mod ignores comment lines
  such as `# MaxPlayers=8`.
- You can put spaces or tabs before the key, around `=`, and after the value.
- The value must contain only digits. Leading zeros are valid, for example
  `MaxPlayers=0012`.
- The value must be from 3 through 25.
- The mod ignores a line that has other text after the value. For example, it
  ignores `MaxPlayers=10 # note`.
- The mod ignores an out-of-range value. It does not change the value to the
  nearest supported value.
- If more than one line is valid, the last valid line sets the limit.
- If no line is valid, the mod uses 25. `UE4SS.log` and
  `MorePlayersPlus.log` then show a `Config missing/invalid` message. If
  `config.ini` does not exist, `UE4SS.log` shows `Config not found` instead.

This example sets the limit to 12 in the Lua script and native DLL:

```ini
# MaxPlayers=8 example
MaxPlayers=12
```

Set `PartyUiDiagnostics=1` to record party UI snapshots in `UE4SS.log` after
each player joins. With this setting, press F9 to record one more snapshot.
Use `1` only for troubleshooting. The snapshots can stop the game for a short
time when players join.

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
6. Extract the UE4SS archive contents into `Atlas\Binaries\Win64`.
7. Do not start Wayfinder until you install MorePlayersPlus.

The MorePlayersPlus archive installs this custom signature at:

```text
Wayfinder\Atlas\Binaries\Win64\UE4SS_Signatures\GUObjectArray.lua
```

UE4SS uses this signature to find the global object array. Lua mods cannot
load when this lookup fails.

After you install MorePlayersPlus, the directory must contain these items:

```text
Wayfinder\Atlas\Binaries\Win64\dwmapi.dll
Wayfinder\Atlas\Binaries\Win64\UE4SS.dll
Wayfinder\Atlas\Binaries\Win64\UE4SS-settings.ini
Wayfinder\Atlas\Binaries\Win64\UE4SS_Signatures\GUObjectArray.lua
Wayfinder\Atlas\Binaries\Win64\Mods
```

See the [official UE4SS installation guide](https://docs.ue4ss.com/installation-guide)
and [UE4SS 3.0.1 release notes](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1)
for additional information.

### Install MorePlayersPlus

1. Close Wayfinder.
2. If you installed an earlier unreleased MorePlayers build, delete this
   folder: `Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayers`. Two copies apply
   their changes two times.
3. If FuniWF's More Players mod is installed, remove it. Both mods change the
   same session limits.
4. Extract the MorePlayersPlus archive into the Wayfinder installation directory.
5. Permit file replacement when Windows asks for confirmation.

The archive contains an `Atlas` folder and `MorePlayersPlus-README.md`. The
`Atlas` folder of the archive must merge with the `Atlas` folder of Wayfinder.

Confirm that these files exist:

```text
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayersPlus\enabled.txt
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayersPlus\config.ini
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayersPlus\Scripts\main.lua
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayersPlus\dlls\main.dll
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayersPlus\licenses\MinHook-LICENSE.txt
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayersPlus\licenses\UE4SS-LICENSE.txt
```

Start Wayfinder. Confirm that `UE4SS.log` contains `[MorePlayersPlus] Mod loaded`.

The native diagnostic log is written to:

```text
Wayfinder\Atlas\Binaries\Win64\MorePlayersPlus.log
```

## Confirm the mod is working

Start Wayfinder. Open this file:

```text
Wayfinder\Atlas\Binaries\Win64\UE4SS.log
```

Confirm that the file contains messages similar to these:

```text
[MorePlayersPlus] Config MaxPlayers=25
[MorePlayersPlus] Mod loaded
[MorePlayersPlus] Online party maximum phase=created group_size=3.0->25.0
[MorePlayersPlus] Party invite controls hook ready
[MorePlayersPlus] Engine limits: players=25 party=25
```

Load a character into the game. When you open the party page in the pause menu,
`UE4SS.log` records one line:

```text
[MorePlayersPlus] Party invite controls first call players=1 (number) host=true (boolean) probe=shown
```

Open this file:

```text
Wayfinder\Atlas\Binaries\Win64\MorePlayersPlus.log
```

The native DLL adds lines to the end of this file at each start. Find the lines
from the last start of Wayfinder. Confirm that they include lines that start
with this text:

```text
[MorePlayersPlus] Native companion starting
[MorePlayersPlus] Config MaxPlayers=25
[MorePlayersPlus] Session capacity patch applied at 4 sites
[MorePlayersPlus] Full-party threshold patch applied at 2 sites
[MorePlayersPlus] MinHook not activated: both instruction patch groups apply
[MorePlayersPlus] Steam rich presence observer ready
```

The file also contains other lines between and after these lines. The examples
show the default value 25. Your log files show your `MaxPlayers` value. If
`MaxPlayers` is 3, the native log shows `patch not necessary` instead of
`patch applied`.

When both patch groups apply, Wayfinder itself submits the configured limit to
EOS and Steam. The native DLL then activates no MinHook hook. This is the
normal mode.

Host a public or invite-only game. In the normal mode, the native log records
your own Steam rich presence each time it changes:

```text
[MorePlayersPlus] Steam rich presence keys=... connect=... steam_player_group=...
```

`UE4SS.log` should also contain `session-settings-publication` or
`party-update-publication` with `max_group_size=25`. This confirms that the
session publication hooks run. Wayfinder does not use `MaxGroupSize` for the
session capacity.

With 3 or more players, the host keeps the session open and current until the
party reaches `MaxPlayers`. With 3 to `MaxPlayers - 1` players, the pause menu
party page shows `+Party Member` and `Code` to the host. `UE4SS.log` then
contains:

```text
[MorePlayersPlus] Party invite controls players=3 limit=25 result=shown
```

If the native log contains `patch unavailable`, the Wayfinder executable has
changed. The mod then uses its fallback mode. The fallback hooks raise the EOS
and Steam limits, and they suppress the full publication after the third
player joins:

```text
[MorePlayersPlus] Hooked ISteamMatchmaking009::SetLobbyMemberLimit[v31]
[MorePlayersPlus] SetLobbyMemberLimit 3 -> 25 lobby=...
[MorePlayersPlus] Suppressed UWFGameInstance::UpdateHostSessionFullParty requested=...
```

When a player joins or disconnects, `UE4SS.log` records ordered join events.
Search for `Join diagnostic`. A kick entry includes the reason supplied by
Wayfinder when the host observes the kick call.

```text
[MorePlayersPlus] Join diagnostic sequence=... event=post-login ...
[MorePlayersPlus] Join diagnostic sequence=... event=client-loading-complete ...
[MorePlayersPlus] Join diagnostic sequence=... event=client-kicked reason=...
[MorePlayersPlus] Join diagnostic sequence=... event=lobby-beacon-client-kicked reason=...
[MorePlayersPlus] Join diagnostic sequence=... event=party-reservation-response result=...
[MorePlayersPlus] Join diagnostic sequence=... event=logout ...
```

### Troubleshooting

MorePlayersPlus writes its log lines to two files. `UE4SS.log` contains the
lines of the Lua script. UE4SS overwrites `UE4SS.log` at each start. Copy
the file before you start Wayfinder again. `MorePlayersPlus.log` contains the
lines of the native DLL.

- If `UE4SS.log` does not exist, check the UE4SS installation and custom signature.
- If `UE4SS.log` does not contain `Mod loaded`, check the `MorePlayersPlus`
  directory and `enabled.txt`.
- If `MorePlayersPlus.log` does not exist, check `MorePlayersPlus\dlls\main.dll`.
- If `MorePlayersPlus.log` contains `build signature mismatch`, the Wayfinder
  executable changed. The line names the instruction group or the full-party
  hook. The DLL changes no instruction in that group and uses the fallback
  mode. If the line names the full-party hook, the DLL does not activate that
  hook.
- If Steam rich presence lines are absent in the normal mode, host a game and
  wait 10 seconds.
- If `SetLobbyMemberLimit result=0` appears in the fallback mode, Steam
  rejected the limit update.
- Press F9 to record a party UI snapshot when UI diagnostics are enabled.
- If only one client disconnects, also collect the Wayfinder logs of that client.

For a Wayfinder crash, collect these files:

```text
%LOCALAPPDATA%\Wayfinder\Saved\Logs\Atlas.log
%LOCALAPPDATA%\Wayfinder\Saved\Crashes
```

The logs can contain player names, online IDs, and lobby IDs.
`MorePlayersPlus.log` also contains your installation path and your own Steam
join information. The installation path can contain your Windows user name.
Before you share a log, remove the names and IDs of other players. Also remove
your own data that you do not want to share.

## How players join

The host starts a public or invite-only game. Players can then join through
these methods:

- Steam overlay invite (Shift+Tab).
- The `+Party Member` button on the party page of the pause menu. This button
  opens the Steam overlay invite.
- `Join Game` in the Steam friends list. See [Known limits](#known-limits).
- The in-game session browser, for public games.
- The session code. The host finds it under `Code` on the party page of the
  pause menu.
- Discord. If the session capacity patch does not apply, Discord joins stop at
  3 players.

The in-game social-list Invite and the chat Invite do nothing in this version
of Wayfinder. These two invites use the Digital Extremes backend, which is not
connected. Use one of the methods above.

When the party reaches `MaxPlayers`, the session is full.

## Known limits

- Live tests used 3, 4, and 5 players, with map travel at 4 and 5 players. The
  tests showed no kicks and no network errors. No test used more than 5
  players.
- These live tests ran on an earlier internal build. That build made the same
  six instruction changes. It also activated MinHook hooks for Steam and EOS.
  Its Steam hook set the Steam join information of the host.
- Version 1.0.0 has not yet been tested with a joining player. In the normal
  mode, version 1.0.0 activates no MinHook hook. `Join Game` in the Steam
  friends list then uses only the Steam join information that Wayfinder sets.
- The unmodded game supports 3 players. The tests did not examine each game
  system with more than 3 players.
- The session browser card shows a maximum of three player portraits. The
  session can contain more players.
- An earlier internal build crashed at startup in 1 of 7 starts. The crash
  occurred during MinHook hook activation. In version 1.0.0, the normal mode
  does not activate MinHook hooks. Tests have not yet confirmed that the crash
  cannot occur.
- Fallback mode: A game update can change the instructions that the DLL
  changes. Then the DLL does not change the instruction groups that are
  different. It activates MinHook hooks instead. The earlier startup crash
  occurred during this hook activation. If the full-party threshold patch does
  not apply, the session browser data can become out of date after the third
  player joins.

## Uninstall

SkipStartupWarnings and other UE4SS mods for Wayfinder can use the same
signature file.

1. Close Wayfinder.
2. Delete this folder: `Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayersPlus`.
3. Delete this file: `Wayfinder\MorePlayersPlus-README.md`.
4. If you do not need the native log, delete this file:
   `Wayfinder\Atlas\Binaries\Win64\MorePlayersPlus.log`.
5. If you also remove UE4SS, delete this file:
   `Wayfinder\Atlas\Binaries\Win64\UE4SS_Signatures\GUObjectArray.lua`.

Keep `GUObjectArray.lua` while UE4SS stays installed. To remove UE4SS, refer
to the UE4SS documentation.

## Compatibility

MorePlayersPlus does not block later UE4SS mods that use `enabled.txt`. Its
native companion starts after UE4SS finishes mod discovery and starts the event
loop. When both patch groups apply, it activates no hook. In the fallback, the
Steam and Wayfinder hooks activate as one MinHook batch, and the EOS hook batch
waits five seconds after Unreal initialization.

SkipStartupWarnings loads through its own `enabled.txt` file. It needs no
`mods.txt` entry. Both archives contain the same signature file. Version 1.0.0
of the two mods has not yet been tested together.

## Build

Run this command from the repository root to build MorePlayersPlus.
The build script also updates each generated table of contents.

To change the default configuration in a new distribution, edit:

```text
src\mods\MorePlayersPlus\content\config.ini
```

```powershell
.\build.ps1 -Mod MorePlayersPlus
```

The script creates these outputs:

```text
dist\NexusMods\MorePlayersPlus\
dist\Wayfinder-MorePlayersPlus-NexusMods.zip
```

Use `-SkipNativeBuild` to reuse the current compiled DLL. Use `-NoArchive` to
generate only the unpacked distribution.

Use `-ListMods` to show all discovered mod manifests.

See `src\mods\MorePlayersPlus\native\README.md` for native build details.

## Technical notes

Only the host needs MorePlayersPlus. Client search filters and the session
browser are not modified, so joining clients can stay unmodded.

Wayfinder writes the constant 3 as the session capacity each time the host
creates or updates its session. The native companion changes these four
instructions to the configured `MaxPlayers` value. The Steam lobby limit, the
EOS session capacity, and the Discord party data then use the configured limit.

Wayfinder publishes the session as full when the party has 3 players. The
native companion changes this threshold in two instructions to `MaxPlayers`.
The session then stays open, with current difficulty and character data, until
the party is full.

The DLL checks the bytes of all instructions in a group before it changes that
group. If the bytes of a group are different, the DLL changes no instruction in
that group. The DLL tries the full-party group only after the session capacity
group applies. If a group does not apply, the DLL uses its fallback hooks.

The pause menu party page hides `+Party Member` and `Code` at 3 players. The Lua
script shows them again for the host while the party has fewer than
`MaxPlayers` players. `+Party Member` opens the Steam overlay invite.

In the fallback mode, the native companion uses MinHook. Wayfinder ships
Steamworks SDK v157. The fallback hooks the runtime-verified
`ISteamMatchmaking009::SetLobbyMemberLimit` slot and the EOS 1.16.3 session
capacity calls. It suppresses `UWFGameInstance::UpdateHostSessionFullParty`.
Its Steam hook also sets the host's Steam join information (rich presence).

The mod opens no network connection of its own. It contains no download or
auto-update code. In the normal mode, Wayfinder itself sends the changed
session values to Steam and EOS. The Digital Extremes backend is not connected
in this version of Wayfinder.

## Attribution

- The Lua session-limit approach is based on the
  [More Players mod by FuniWF](https://www.nexusmods.com/wayfinder/mods/9) and
  is used with FuniWF's permission. MorePlayersPlus adds the native companion,
  the instruction patches, and the party controls fix.
- The Wayfinder signature in `GUObjectArray.lua` comes from FuniWF's UE4SS
  setup guide for Wayfinder. FuniWF links this guide from the More Players mod
  page.
- MinHook by Tsuda Kageyu, BSD 2-clause license. MinHook contains Hacker
  Disassembler Engine 32 C and 64 C by Vyacheslav Patkov, BSD 2-clause license.
  The license notices are in `Mods\MorePlayersPlus\licenses\MinHook-LICENSE.txt`.
- UE4SS (RE-UE4SS project), MIT license. The license notice is in
  `Mods\MorePlayersPlus\licenses\UE4SS-LICENSE.txt`. The archive does not
  include UE4SS binaries.
- Wayfinder is a game by Airship Syndicate. Airship Syndicate does not make or
  support this mod.
- AI tools (Claude and Codex) generated much of the code and documentation.
