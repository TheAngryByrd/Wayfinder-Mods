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
- [Build](#build)
- [Project layout](#project-layout)
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
PartyUiDiagnostics=1
```

Supported values are 3 through 25. The Lua script and native DLL read this same
setting when Wayfinder starts. Restart Wayfinder after you change the file.

Party UI diagnostics run after each player joins. Press F9 to record an
additional snapshot in `UE4SS.log`. Set `PartyUiDiagnostics=0` to disable these
snapshots.

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
7. Copy [`src/UE4SS_Signatures/GUObjectArray.lua`](src/UE4SS_Signatures/GUObjectArray.lua) to:

```text
Wayfinder\Atlas\Binaries\Win64\UE4SS_Signatures\GUObjectArray.lua
```

Wayfinder requires this custom signature. UE4SS uses it to locate the global
object array. Lua mods cannot load when this lookup fails.

The directory must contain these items:

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

Build the Nexus Mods distribution. Then copy its `Atlas` directory into the
Wayfinder installation directory.

```powershell
.\build.ps1
```

The generated mod directory is:

```text
dist\NexusMods\Atlas\Binaries\Win64\Mods\MorePlayers
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

Run `build.ps1` to compile the native DLL and generate the Nexus Mods files.
The build script also updates each generated table of contents.

To change the default configuration in a new distribution, edit:

```text
src\MorePlayers\config.ini
```

```powershell
.\build.ps1
```

The script creates these outputs:

```text
dist\NexusMods\
dist\Wayfinder-MorePlayers-NexusMods.zip
```

Use `-SkipNativeBuild` to reuse the current compiled DLL. Use `-NoArchive` to
generate only the unpacked distribution.

See [`src/native/README.md`](src/native/README.md) for native build details.

## Project layout

```text
src\MorePlayers                 Lua script and mod configuration
src\native                      C++ source and native build files
src\UE4SS_Signatures            Wayfinder UE4SS signature
dist\NexusMods                  Generated Nexus Mods directory
dist\Wayfinder-MorePlayers-NexusMods.zip
```

The repository ignores `dist` because all distribution files are generated.

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
