# Wayfinder MorePlayers

This package raises the host session limit and the Steam lobby member limit.
Only the host needs this mod for session capacity and invitations.

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
