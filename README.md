# Wayfinder MorePlayers

Local Wayfinder/UE4SS mod that raises Unreal session limits and the associated
Steam lobby member limit. It also publishes Steam lobby rich presence so the
native invite flow can target the active lobby.

## Configuration

Edit `MorePlayers/config.ini` before launching Wayfinder:

```ini
MaxPlayers=25
PartyUiDiagnostics=1
```

Supported values are 3 through 25. The Lua script and native DLL read this same
setting at startup. Party UI diagnostics run after each player joins. Press F9
to record an additional snapshot in `UE4SS.log`. Set `PartyUiDiagnostics=0` to
disable these snapshots.

## Install

This repository contains only the mod, not UE4SS itself. Install the compatible
Wayfinder UE4SS 3.0.1 setup first.

### Install UE4SS 3.0.1

1. Download [`UE4SS_v3.0.1.zip`](https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip).
2. Close Wayfinder.
3. Open the Wayfinder installation directory in Steam.
4. Open `Atlas\Binaries\Win64`.
5. Remove an old `xinput1_3.dll` file from this directory.
6. Extract the UE4SS archive contents into `Atlas\Binaries\Win64`.

The directory must contain these items:

```text
Wayfinder\Atlas\Binaries\Win64\dwmapi.dll
Wayfinder\Atlas\Binaries\Win64\UE4SS.dll
Wayfinder\Atlas\Binaries\Win64\UE4SS-settings.ini
Wayfinder\Atlas\Binaries\Win64\Mods
```

See the [official UE4SS installation guide](https://docs.ue4ss.com/installation-guide)
and [UE4SS 3.0.1 release notes](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1)
for additional information.

### Install MorePlayers

Copy the `MorePlayers` directory to:

```text
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayers
```

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

## Build

See [`native/README.md`](native/README.md). The resulting DLL should be copied to
`MorePlayers/dlls/main.dll`.

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
companion. Review the original author's permissions before publishing or
redistributing modified assets.
