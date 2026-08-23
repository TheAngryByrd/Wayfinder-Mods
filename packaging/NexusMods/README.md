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
- [Requirements](#requirements)
- [Install](#install)
- [Confirm the mod is working](#confirm-the-mod-is-working)
  - [Troubleshooting](#troubleshooting)
- [Configuration](#configuration)
- [Logs](#logs)
<!-- toc:end -->

## Requirements

Install [UE4SS 3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1)
before you install MorePlayers.

## Install

1. Close Wayfinder.
2. Open the Wayfinder installation directory in Steam.
3. Extract this archive into the Wayfinder installation directory.
4. Permit file replacement when Windows asks for confirmation.
5. Start Wayfinder.
6. Confirm that `Atlas\Binaries\Win64\UE4SS.log` contains `[MorePlayers] Mod loaded`.

The archive installs the custom Wayfinder signature at:

```text
Atlas\Binaries\Win64\UE4SS_Signatures\GUObjectArray.lua
```

The archive installs the mod at:

```text
Atlas\Binaries\Win64\Mods\MorePlayers
```

## Confirm the mod is working

Start Wayfinder. Open this file:

```text
Atlas\Binaries\Win64\UE4SS.log
```

Confirm that the file contains messages similar to these:

```text
[MorePlayers] Config MaxPlayers=25
[MorePlayers] Mod loaded
[MorePlayers] Engine MaxPlayers: 25
```

Open this file:

```text
Atlas\Binaries\Win64\MorePlayersSteamLimit.log
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

Repeated `3 -> 25` messages are normal. Wayfinder submits its original limit
each time it updates the session. The mod replaces each submitted value.

### Troubleshooting

- If `UE4SS.log` does not exist, check the UE4SS installation and custom signature.
- If `Mod loaded` is absent, check the `MorePlayers` directory and `enabled.txt`.
- If the native log does not exist, check `MorePlayers\dlls\main.dll`.
- If Steam messages are absent, host a game before you check the log.
- If `SetLobbyMemberLimit result=0` appears, Steam rejected the limit update.
- Press F9 to record a party UI snapshot when UI diagnostics are enabled.

For a Wayfinder crash, collect these files:

```text
%LOCALAPPDATA%\Wayfinder\Saved\Logs\Atlas.log
%LOCALAPPDATA%\Wayfinder\Saved\Crashes
```

## Configuration

Edit this file before you start Wayfinder:

```text
Atlas\Binaries\Win64\Mods\MorePlayers\config.ini
```

`MaxPlayers` supports values from 3 through 25.

Set `PartyUiDiagnostics=0` to disable party UI snapshots. Press F9 to record a
manual snapshot when diagnostics are enabled.

## Logs

UE4SS and Lua write to:

```text
Atlas\Binaries\Win64\UE4SS.log
```

The native companion writes to:

```text
Atlas\Binaries\Win64\MorePlayersSteamLimit.log
```
