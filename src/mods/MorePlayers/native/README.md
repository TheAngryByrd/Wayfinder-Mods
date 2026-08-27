# Building `main.dll`

This native companion targets 64-bit Windows and the UE4SS 3.0.1 C++ mod ABI.
Wayfinder ships Steamworks SDK v157 and requests `SteamMatchMaking009` through
`SteamInternal_ContextInit`. It does not import the flat matchmaking functions.
This companion therefore hooks only the runtime-proven method:

- `ISteamMatchmaking009::SetLobbyMemberLimit` (vtable slot 31)
- `UWFGameInstance::UpdateHostSessionFullParty` for the supported Wayfinder
  executable build

The crash-run trace showed this slot receiving `(this, lobby, 3)`, returning
success, and reporting a resulting limit of 25. No other vtable slots or getters
are called. The captured lobby ID is used to publish Steam `connect` rich
presence while leaving the invite dialog under user control.

The hook raises the requested Steam lobby capacity to the value in
`../content/config.ini` and publishes a `+connect_lobby` Steam Rich Presence value.
It does not open the Steam overlay automatically. Both
`../content/Scripts/main.lua` and the compiled DLL read the same `MaxPlayers`
setting.

## Contents

<!-- toc:start -->
- [Requirements](#requirements)
- [Build commands](#build-commands)
- [Validation](#validation)
- [Updating the full-party hook](#updating-the-full-party-hook)
  - [Current reference build](#current-reference-build)
  - [Find the native function](#find-the-native-function)
  - [Calculate the RVA](#calculate-the-rva)
  - [Capture the byte signature](#capture-the-byte-signature)
  - [Validate the updated hook](#validate-the-updated-hook)
- [EOS lobby-browser diagnostics](#eos-lobby-browser-diagnostics)
- [Important ABI warning](#important-abi-warning)
<!-- toc:end -->

## Requirements

- Visual Studio 2022 Build Tools or Visual Studio 2022
- **Desktop development with C++** workload
- CMake 3.22 or newer
- Git and internet access during CMake configuration (to fetch MinHook v1.3.4)

## Build commands

Use the root build script for a complete Nexus Mods distribution. From the
repository root, run:

```powershell
.\build.ps1 -Mod MorePlayers
```

This command compiles the DLL, stages all required files, and creates the Nexus
Mods ZIP file.

For a native-only build, open **Developer PowerShell for VS 2022**.
Run this command from the repository root:

```powershell
.\scripts\build-native.ps1 `
    -SourceDirectory .\src\mods\MorePlayers\native `
    -BuildDirectory .\build\native\MorePlayers `
    -Target MorePlayersSteamLimit
```

The native script configures and compiles an x64 Release build.
It does not stage distribution files.
Use `-Configuration Debug` for a debug build.

The equivalent manual commands are:

```powershell
cmake -S src\mods\MorePlayers\native -B build\native\MorePlayers -G "Visual Studio 17 2022" -A x64
cmake --build build\native\MorePlayers --config Release --target MorePlayersSteamLimit
```

The output is:

```text
build\native\MorePlayers\Release\MorePlayersSteamLimit.dll
```

The root build script copies it to:

```text
dist\NexusMods\MorePlayers\Atlas\Binaries\Win64\Mods\MorePlayers\dlls\main.dll
```

## Validation

From a Visual Studio Developer PowerShell:

```powershell
dumpbin /headers build\native\MorePlayers\Release\MorePlayersSteamLimit.dll
dumpbin /exports build\native\MorePlayers\Release\MorePlayersSteamLimit.dll
dumpbin /dependents build\native\MorePlayers\Release\MorePlayersSteamLimit.dll
```

Confirm that it is x64 and exports both `start_mod` and `uninstall_mod`.

At runtime, inspect `Atlas\Binaries\Win64\MorePlayersSteamLimit.log`. It records
hook installation, lobby calls, rich-presence return values, and EOS capacity
updates.

UE4SS `on_program_start` only schedules native installation. The first
`on_update` call creates the Steam lobby-limit and Wayfinder full-party hooks
while they are disabled. It queues both hooks and enables them with one
`MH_ApplyQueued` call. Keep this event-loop boundary and batch activation when
you add or change startup hooks. Synchronous startup activation blocks later
`enabled.txt` mods. Concurrent activation can crash while Wayfinder initializes.

## Updating the full-party hook

The full-party hook is specific to one `Wayfinder.exe` build. A game update can
move the function, change its instructions, or change its calling convention.

The byte signature is a safety check. The DLL disables this hook when the
function entry does not match.

### Current reference build

```text
PE timestamp: 0x67EAE4E6
SHA-256: 00DE5E57987367B09733905148DE51F5170895585FFCFBF7FFD8E64A1F061F70
Image base: 0x140000000
Function VA: 0x14164D770
Function RVA: 0x164D770
```

### Find the native function

The game log first identified the native function through this exact message:

```text
UWFGameInstance::UpdateHostSessionFullParty setting session settings full
```

The executable stores this message as UTF-16 text. Use a PE-aware disassembler,
such as Ghidra, to locate the function.

1. Open the current `Wayfinder.exe` in the disassembler.
2. Complete the standard x64 analysis.
3. Search the defined strings for the exact UTF-16 message.
4. Open each code reference to the string.
5. Select the function that formats the message.
6. Use the disassembler's function boundary.
7. Do not use only nearby `CC` padding to select the boundary.
8. Confirm the Windows x64 arguments before changing the hook.

The current build contains this evidence:

```text
0x14164D7A2  movzx r12d,dl
0x14164D7A6  mov   r15,rcx
0x14164D7BA  lea   rax,[0x14539D4B0]
```

`RCX` contains the first argument, which is the `this` pointer. `DL` contains
the Boolean second argument.

The `lea` instruction references the full-party log message. Together, these
instructions support the current `void(void*, bool)` hook signature.

If the arguments or return behavior change, stop. Review the callers and update
the function type before installing the hook.

### Calculate the RVA

Read the image base and disassemble the candidate function with Visual Studio
`dumpbin`:

```powershell
dumpbin /headers "F:\SteamLibrary\steamapps\common\Wayfinder\Atlas\Binaries\Win64\Wayfinder.exe"
dumpbin /disasm:bytes /range:0x14164D700,0x14164D900 "F:\SteamLibrary\steamapps\common\Wayfinder\Atlas\Binaries\Win64\Wayfinder.exe"
```

Calculate the RVA from the function virtual address and image base:

```text
RVA = function VA - image base
RVA = 0x14164D770 - 0x140000000
RVA = 0x164D770
```

Update `target_rva` with the new result.

### Capture the byte signature

Copy complete instructions from the exact function entry. Avoid address bytes
that relocation or linking can change.

The current signature uses these first 24 bytes:

```text
48 89 5C 24 10 48 89 74 24 18 48 89 7C 24 20 55
41 54 41 55 41 56 41 57
```

Update `expected_prologue` with the new bytes. Do not start at `target + 0xA`.
That offset caused the previous validator failure.

### Validate the updated hook

1. Rebuild the native DLL.
2. Start Wayfinder with the new DLL.
3. Open `Atlas\Binaries\Win64\MorePlayersSteamLimit.log`.
4. Confirm that the log reports the updated RVA.
5. Confirm that the log contains the successful hook message.

```text
[MorePlayersSteamLimit] Hooked UWFGameInstance::UpdateHostSessionFullParty[Wayfinder+0x164D770]
```

Treat `build signature mismatch` as a failed validation. Do not remove the byte
check to force installation.

## EOS lobby-browser diagnostics

Wayfinder ships `EOSSDK-Win64-Shipping.dll` version 1.16.3. The DLL installs
pass-through diagnostic hooks for:

- `EOS_Lobby_CreateLobby`
- `EOS_LobbyModification_SetMaxMembers`
- `EOS_LobbySearch_SetParameter`
- `EOS_SessionSearch_SetParameter`
- `EOS_Sessions_CreateSessionModification`
- `EOS_Sessions_UpdateSessionModification`
- `EOS_SessionModification_SetMaxPlayers`
- `EOS_SessionModification_AddAttribute`

The session-advertisement hooks raise `CreateSessionModification.MaxPlayers`,
`SessionModification_SetMaxPlayers`, and the advertised
`NumPublicConnections` attribute to the shared configured limit. The remaining
EOS hooks are diagnostics only and record search keys, values, comparison
operators, API versions, modification handles, and return codes. Browser search
filters and client UI are intentionally unchanged so only the host needs the
mod.

## Important ABI warning

The source contains a small compatibility definition matching UE4SS 3.0.1's
published `CppUserModBase` layout. C++ mods are ABI-sensitive. Rebuild and
review this compatibility class before using the DLL with any other UE4SS
version. Successful compilation and exported symbols do not replace runtime
testing against Wayfinder.

The Steam hook is also experimental: if Wayfinder calls the C++ virtual
`ISteamMatchmaking` interface instead of Steam's flat exports, the hooks will
not fire and a different native interception point will be required.
