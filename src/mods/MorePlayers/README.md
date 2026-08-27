# Wayfinder MorePlayers

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
  - [Install MorePlayers](#install-moreplayers)
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
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayers\config.ini
```

Set the required values:

```ini
MaxPlayers=25
PartyUiDiagnostics=0
```

Supported values are 3 through 25. The Lua script and native DLL read this same
setting when Wayfinder starts. Restart Wayfinder after you change the file.

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
7. Do not start Wayfinder until you install MorePlayers.

The MorePlayers archive installs this custom signature at:

```text
Wayfinder\Atlas\Binaries\Win64\UE4SS_Signatures\GUObjectArray.lua
```

The MorePlayers archive includes this custom signature. UE4SS uses it to locate
the global object array. Lua mods cannot load when this lookup fails.

After you install MorePlayers, the directory must contain these items:

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

### Install MorePlayers

1. Close Wayfinder.
2. Extract the MorePlayers archive into the Wayfinder installation directory.
3. Permit file replacement when Windows asks for confirmation.

Confirm that these files exist:

```text
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayers\enabled.txt
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayers\config.ini
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayers\Scripts\main.lua
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayers\dlls\main.dll
```

Start Wayfinder. Confirm that `UE4SS.log` contains `[MorePlayers] Mod loaded`.

The native diagnostic log is written to:

```text
Wayfinder\Atlas\Binaries\Win64\MorePlayersSteamLimit.log
```

## Confirm the mod is working

Start Wayfinder. Open this file:

```text
Wayfinder\Atlas\Binaries\Win64\UE4SS.log
```

Confirm that the file contains messages similar to these:

```text
[MorePlayers] Config MaxPlayers=25
[MorePlayers] Mod loaded
[MorePlayers] Online party maximum phase=created group_size=3.0->25.0
[MorePlayers] Engine limits: players=25 party=25
```

Open this file:

```text
Wayfinder\Atlas\Binaries\Win64\MorePlayersSteamLimit.log
```

Confirm that the file contains these startup messages:

```text
[MorePlayersSteamLimit] Native companion starting
[MorePlayersSteamLimit] Config MaxPlayers=25
[MorePlayersSteamLimit] EOS hooks installed; configured capacity overrides enabled
```

Host a public or invite-only game. Confirm that the native log contains these
session messages:

```text
[MorePlayersSteamLimit] EOS advertised NumPublicConnections 3 -> 25
[MorePlayersSteamLimit] SetLobbyMemberLimit 3 -> 25 lobby=...
[MorePlayersSteamLimit] SetLobbyMemberLimit result=1
```

`UE4SS.log` should also contain `session-settings-publication` or
`party-update-publication` with `max_group_size=25`. This confirms that the
host changed Wayfinder's own online-party maximum before publication.

After the third player joins, `MorePlayersSteamLimit.log` should contain:

```text
[MorePlayersSteamLimit] Suppressed UWFGameInstance::UpdateHostSessionFullParty requested=...
```

This confirms that the host did not publish the party as full.

Repeated `3 -> 25` messages are normal. Wayfinder submits its original limit
each time it updates the session. The mod replaces each submitted value.

When a player joins or disconnects, `UE4SS.log` records ordered join events.
Search for `Join diagnostic`. A kick entry includes the reason supplied by
Wayfinder when the host observes the kick call.

```text
[MorePlayers] Join diagnostic sequence=... event=post-login ...
[MorePlayers] Join diagnostic sequence=... event=client-loading-complete ...
[MorePlayers] Join diagnostic sequence=... event=client-kicked reason=...
[MorePlayers] Join diagnostic sequence=... event=lobby-beacon-client-kicked reason=...
[MorePlayers] Join diagnostic sequence=... event=party-reservation-response result=...
[MorePlayers] Join diagnostic sequence=... event=logout ...
```

### Troubleshooting

- If `UE4SS.log` does not exist, check the UE4SS installation and custom signature.
- If `Mod loaded` is absent, check the `MorePlayers` directory and `enabled.txt`.
- If the native log does not exist, check `MorePlayers\dlls\main.dll`.
- If Steam messages are absent, host a game before you check the log.
- If `SetLobbyMemberLimit result=0` appears, Steam rejected the limit update.
- Press F9 to record a party UI snapshot when UI diagnostics are enabled.
- For a client-only disconnect, also collect that client's Wayfinder logs.

For a Wayfinder crash, collect these files:

```text
%LOCALAPPDATA%\Wayfinder\Saved\Logs\Atlas.log
%LOCALAPPDATA%\Wayfinder\Saved\Crashes
```

## Compatibility

MorePlayers does not block later UE4SS mods that use `enabled.txt`. Its native
Steam and Wayfinder hooks activate after UE4SS finishes mod discovery and starts
the event loop. The native hooks activate as one MinHook batch.

SkipStartupWarnings can load after MorePlayers without an explicit `mods.txt`
entry. Keep each mod's `enabled.txt` file installed.

## Build

Run this command from the repository root to build MorePlayers.
The build script also updates each generated table of contents.

To change the default configuration in a new distribution, edit:

```text
src\mods\MorePlayers\content\config.ini
```

```powershell
.\build.ps1 -Mod MorePlayers
```

The script creates these outputs:

```text
dist\NexusMods\MorePlayers\
dist\Wayfinder-MorePlayers-NexusMods.zip
```

Use `-SkipNativeBuild` to reuse the current compiled DLL. Use `-NoArchive` to
generate only the unpacked distribution.

Use `-ListMods` to show all discovered mod manifests.

See `src\mods\MorePlayers\native\README.md` for native build details.

## Technical notes

Wayfinder ships Steamworks SDK v157 and uses `SteamMatchMaking009` through the
C++ interface. The native companion hooks the runtime-verified
`ISteamMatchmaking009::SetLobbyMemberLimit` slot and avoids unverified vtable
methods.

The native companion raises the host's EOS 1.16.3 session capacity and
advertised `NumPublicConnections` value. EOS lobby/session search hooks remain
read-only diagnostics; client search filters and lobby-browser UI are not
modified, allowing joining clients to remain unmodded.

## Attribution

The Lua session-limit approach is based on the More Players mod by FuniWF. This
repository contains a local compatibility implementation and native Steam lobby
companion.
