# Wayfinder MorePlayers

This mod lets a Wayfinder host play with more than three people. Set the maximum
player count from 3 through 25. Only the host needs the mod.

While Wayfinder runs, the mod changes:

- Wayfinder's maximum player setting.
- The number of public spaces reported by the online session.
- The maximum number of members in the Steam lobby.
- The Steam join information used by friend invitations.

The mod installs a Lua script, a native DLL, and a Wayfinder-specific UE4SS
signature. It does not replace the Wayfinder executable, game packages, or save
files.

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
