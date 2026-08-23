# Wayfinder MorePlayers

Local Wayfinder/UE4SS mod that raises Unreal session limits and the associated
Steam lobby member limit. It also publishes Steam lobby rich presence so the
native invite flow can target the active lobby.

## Configuration

Edit `MorePlayers/config.ini` before launching Wayfinder:

```ini
MaxPlayers=25
```

Supported values are 3 through 25. The Lua script and native DLL read this same
setting at startup.

## Install

This repository contains only the mod, not UE4SS itself. Install the compatible
Wayfinder UE4SS 3.0.1 setup first, then copy the `MorePlayers` directory to:

```text
Wayfinder\Atlas\Binaries\Win64\Mods\MorePlayers
```

The native diagnostic log is written to:

```text
Wayfinder\Atlas\Binaries\Win64\MorePlayersSteamLimit.log
```

## Build

See [`native/BUILD.md`](native/BUILD.md). The resulting DLL should be copied to
`MorePlayers/dlls/main.dll`.

## Technical notes

Wayfinder ships Steamworks SDK v157 and uses `SteamMatchMaking009` through the
C++ interface. The native companion hooks the runtime-verified
`ISteamMatchmaking009::SetLobbyMemberLimit` slot and avoids unverified vtable
methods.

The native companion also contains read-only EOS 1.16.3 diagnostics for lobby
creation, capacity updates, and lobby/session search parameters. These are used
to identify Wayfinder's in-game lobby-browser filters before changing them.

## Attribution

The Lua session-limit approach is based on the More Players mod by FuniWF. This
repository contains a local compatibility implementation and native Steam lobby
companion. Review the original author's permissions before publishing or
redistributing modified assets.
