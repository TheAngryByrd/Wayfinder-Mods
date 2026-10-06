# Wayfinder MorePlayersPlus

This mod lets a Wayfinder host play with more than three people. Set the maximum
player count from 3 through 25. Only the host needs the mod. Wayfinder
automatically scales the game for the number of connected players.

While Wayfinder runs, the mod changes:

- Wayfinder's maximum player setting.
- The number of public spaces reported by the online session.
- The maximum number of members in the Steam lobby.
- The Steam join information used by friend invitations.

The mod installs a Lua script, a native DLL, and a Wayfinder-specific UE4SS
signature. It does not replace the Wayfinder executable, game packages, or save
files.

## Contents

<!-- toc:start -->
- [Configuration](#configuration)
- [Install](#install)
  - [Install UE4SS 3.0.1](#install-ue4ss-301)
  - [Install MorePlayersPlus](#install-moreplayersplus)
- [Confirm the mod is working](#confirm-the-mod-is-working)
  - [Troubleshooting](#troubleshooting)
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
  `MorePlayersPlus.log` then show a `Config missing/invalid` message.

This example sets the limit to 12 in the Lua script and native DLL:

```ini
# MaxPlayers=8 example
MaxPlayers=12
```

Party UI diagnostics run after each player joins. Press F9 to record an
additional snapshot in `UE4SS.log`. Set `PartyUiDiagnostics=1` to enable these
snapshots.

## Install

This package does not contain UE4SS. Install the compatible Wayfinder UE4SS
3.0.1 setup first.

### Install UE4SS 3.0.1

1. Download [`UE4SS_v3.0.1.zip`](https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip).
2. Close Wayfinder.
3. Open the Wayfinder installation directory in Steam.
4. Open `Atlas\Binaries\Win64`.
5. Remove an old `xinput1_3.dll` file from this directory.
6. Extract the UE4SS archive contents into `Atlas\Binaries\Win64`.
7. Do not start Wayfinder until you install MorePlayersPlus.

The MorePlayersPlus archive installs this custom signature at:

```text
Wayfinder\Atlas\Binaries\Win64\UE4SS_Signatures\GUObjectArray.lua
```

The MorePlayersPlus archive includes this custom signature. UE4SS uses it to locate
the global object array. Lua mods cannot load when this lookup fails.

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
2. If you installed an earlier MorePlayers build, delete this folder:
   `Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayers`. Two copies apply their
   changes twice.
3. Do not install FuniWF's More Players at the same time. Both mods change the
   same session limits.
4. Extract the MorePlayersPlus archive into the Wayfinder installation directory.
5. Permit file replacement when Windows asks for confirmation.

Confirm that these files exist:

```text
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayersPlus\enabled.txt
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayersPlus\config.ini
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayersPlus\Scripts\main.lua
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayersPlus\dlls\main.dll
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

When you open the party page in the pause menu, `UE4SS.log` records one line:

```text
[MorePlayersPlus] Party invite controls first call players=1 (number) host=true (boolean) probe=shown
```

Open this file:

```text
Wayfinder\Atlas\Binaries\Win64\MorePlayersPlus.log
```

Confirm that the file contains these startup messages:

```text
[MorePlayersPlus] Native companion starting
[MorePlayersPlus] Config MaxPlayers=25
[MorePlayersPlus] Session capacity patch applied at 4 sites
[MorePlayersPlus] Full-party threshold patch applied at 2 sites
[MorePlayersPlus] MinHook not activated: both instruction patch groups apply
[MorePlayersPlus] Steam rich presence observer ready
```

When both patch groups apply, Wayfinder itself submits the configured limit to
EOS and Steam. The mod then installs no hook.

Host a public or invite-only game. The native log records your own Steam rich
presence each time it changes:

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
changed. The mod then uses its fallback hooks. They raise the EOS and Steam
limits, and they suppress the full publication after the third player joins:

```text
[MorePlayersPlus] Hooked ISteamMatchmaking009::SetLobbyMemberLimit[v31]
[MorePlayersPlus] SetLobbyMemberLimit 3 -> 25 lobby=...
[MorePlayersPlus] Suppressed UWFGameInstance::UpdateHostSessionFullParty requested=...
```

In the fallback, Discord joins stop at 3 players.

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

- If `UE4SS.log` does not exist, check the UE4SS installation and custom signature.
- If `Mod loaded` is absent, check the `MorePlayersPlus` directory and `enabled.txt`.
- If the native log does not exist, check `MorePlayersPlus\dlls\main.dll`.
- If `build signature mismatch` appears, the Wayfinder executable changed. The
  mod then keeps the original session capacity instructions.
- If Steam rich presence lines are absent, host a game and wait 10 seconds.
- If `SetLobbyMemberLimit result=0` appears in the fallback, Steam rejected the
  limit update.
- Press F9 to record a party UI snapshot when UI diagnostics are enabled.
- For a client-only disconnect, also collect that client's Wayfinder logs.

For a Wayfinder crash, collect these files:

```text
%LOCALAPPDATA%\Wayfinder\Saved\Logs\Atlas.log
%LOCALAPPDATA%\Wayfinder\Saved\Crashes
```

## Compatibility

MorePlayersPlus does not block later UE4SS mods that use `enabled.txt`. Its
native companion starts after UE4SS finishes mod discovery and starts the event
loop. When both patch groups apply, it activates no hook. In the fallback, the
Steam and Wayfinder hooks activate as one MinHook batch, and the EOS hook batch
waits five seconds after Unreal initialization.

SkipStartupWarnings can load after MorePlayersPlus without an explicit `mods.txt`
entry. Keep each mod's `enabled.txt` file installed.

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
instructions to the configured `MaxPlayers` value. Wayfinder's rich presence
and Discord party data then use the configured limit. The native companion
changes no instruction when the executable bytes are different.

Wayfinder publishes the session as full when the party has 3 players. The
native companion changes this threshold in two instructions to `MaxPlayers`.
The session then stays open, with current difficulty and character data, until
the party is full. If these instructions are different, the native companion
suppresses the full publication.

The pause menu party page hides `+Party Member` and `Code` at 3 players. The Lua
script shows them again for the host while the party has fewer than
`MaxPlayers` players. `+Party Member` opens the Steam overlay invite.

When a game update changes the patched instructions, the native companion uses
its fallback hooks. Wayfinder ships Steamworks SDK v157. The fallback hooks the
runtime-verified `ISteamMatchmaking009::SetLobbyMemberLimit` slot and the EOS
1.16.3 session capacity calls, and it suppresses
`UWFGameInstance::UpdateHostSessionFullParty`.

## Attribution

The Lua session-limit approach is based on the More Players mod by FuniWF and
is used with FuniWF's permission. MorePlayersPlus adds the native companion,
the instruction patches, and the party controls fix.
