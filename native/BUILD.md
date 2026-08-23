# Building `main.dll`

This native companion targets 64-bit Windows and the UE4SS 3.0.1 C++ mod ABI.
Wayfinder ships Steamworks SDK v157 and requests `SteamMatchMaking009` through
`SteamInternal_ContextInit`. It does not import the flat matchmaking functions.
This companion therefore hooks only the runtime-proven method:

- `ISteamMatchmaking009::SetLobbyMemberLimit` (vtable slot 31)

The crash-run trace showed this slot receiving `(this, lobby, 3)`, returning
success, and reporting a resulting limit of 25. No other vtable slots or getters
are called. The captured lobby ID is used to publish Steam `connect` rich
presence and open Steam's native lobby invite dialog.

The hook raises the requested Steam lobby capacity to the value in
`../config.ini`, publishes a `+connect_lobby` Steam Rich Presence value, and
opens Steam's native lobby invite dialog once per captured lobby. Both
`../Scripts/main.lua` and `../dlls/main.dll` read the same `MaxPlayers` setting.

## Requirements

- Visual Studio 2022 Build Tools or Visual Studio 2022
- **Desktop development with C++** workload
- CMake 3.22 or newer
- Git and internet access during CMake configuration (to fetch MinHook v1.3.4)

## Build commands

Open **Developer PowerShell for VS 2022**, change into this `source` directory,
and run:

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target MorePlayersSteamLimit
```

The output is:

```text
build\Release\MorePlayersSteamLimit.dll
```

Rename/copy it to:

```text
..\dlls\main.dll
```

## Validation

From a Visual Studio Developer PowerShell:

```powershell
dumpbin /headers build\Release\MorePlayersSteamLimit.dll
dumpbin /exports build\Release\MorePlayersSteamLimit.dll
dumpbin /dependents build\Release\MorePlayersSteamLimit.dll
```

Confirm that it is x64 and exports both `start_mod` and `uninstall_mod`.

At runtime, inspect `Atlas\Binaries\Win64\MorePlayersSteamLimit.log`. It records
hook installation, lobby calls, rich-presence return values, and invite-dialog
activation.

## Important ABI warning

The source contains a small compatibility definition matching UE4SS 3.0.1's
published `CppUserModBase` layout. C++ mods are ABI-sensitive. Rebuild and
review this compatibility class before using the DLL with any other UE4SS
version. Successful compilation and exported symbols do not replace runtime
testing against Wayfinder.

The Steam hook is also experimental: if Wayfinder calls the C++ virtual
`ISteamMatchmaking` interface instead of Steam's flat exports, the hooks will
not fire and a different native interception point will be required.
