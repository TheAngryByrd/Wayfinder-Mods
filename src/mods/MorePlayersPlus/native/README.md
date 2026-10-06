# Building `main.dll`

This native companion targets 64-bit Windows and the UE4SS 3.0.1 C++ mod ABI.
It changes four session-capacity instructions and two full-party threshold
instructions in `Wayfinder.exe`. See [Instruction patches](#instruction-patches).

When both patch groups apply, the companion activates no hook and does not
initialize MinHook. A startup crash dump showed a null call in
`chrome_elf.dll` under MinHook's thread freeze, and the hooks only passed the
configured limit through. The companion then logs the local user's own Steam
rich presence through the Steam flat API each time it changes.

When a patch group does not apply, the companion uses its fallback hooks.
Wayfinder ships Steamworks SDK v157 and requests `SteamMatchMaking009` through
`SteamInternal_ContextInit`. It does not import the flat matchmaking functions.
The fallback therefore hooks only the runtime-proven methods:

- `ISteamMatchmaking009::SetLobbyMemberLimit` (vtable slot 31)
- `UWFGameInstance::UpdateHostSessionFullParty` for the supported Wayfinder
  executable build
- the EOS session capacity calls, five seconds after Unreal initialization

The crash-run trace showed the Steam slot receiving `(this, lobby, 3)`,
returning success, and reporting a resulting limit of 25. No other vtable slots
or getters are called. The fallback raises the requested Steam lobby capacity
and publishes a `+connect_lobby` Steam rich presence value. It does not open
the Steam overlay automatically.

Both `../content/Scripts/main.lua` and the compiled DLL read the same
`MaxPlayers` setting.

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
- [Instruction patches](#instruction-patches)
  - [Session capacity sites](#session-capacity-sites)
  - [Full-party threshold sites](#full-party-threshold-sites)
  - [Patch checks](#patch-checks)
  - [Update the patch sites](#update-the-patch-sites)
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
.\build.ps1 -Mod MorePlayersPlus
```

This command compiles the DLL, stages all required files, and creates the Nexus
Mods ZIP file.

For a native-only build, open **Developer PowerShell for VS 2022**.
Run this command from the repository root:

```powershell
.\scripts\build-native.ps1 `
    -SourceDirectory .\src\mods\MorePlayersPlus\native `
    -BuildDirectory .\build\native\MorePlayersPlus `
    -Target MorePlayersPlus
```

The native script configures and compiles an x64 Release build.
It does not stage distribution files.
Use `-Configuration Debug` for a debug build.

The equivalent manual commands are:

```powershell
cmake -S src\mods\MorePlayersPlus\native -B build\native\MorePlayersPlus -G "Visual Studio 17 2022" -A x64
cmake --build build\native\MorePlayersPlus --config Release --target MorePlayersPlus
```

The output is:

```text
build\native\MorePlayersPlus\Release\MorePlayersPlus.dll
```

The root build script copies it to:

```text
dist\NexusMods\MorePlayersPlus\Atlas\Binaries\Win64\Mods\MorePlayersPlus\dlls\main.dll
```

## Validation

From a Visual Studio Developer PowerShell:

```powershell
dumpbin /headers build\native\MorePlayersPlus\Release\MorePlayersPlus.dll
dumpbin /exports build\native\MorePlayersPlus\Release\MorePlayersPlus.dll
dumpbin /dependents build\native\MorePlayersPlus\Release\MorePlayersPlus.dll
```

Confirm that it is x64 and exports both `start_mod` and `uninstall_mod`.

At runtime, inspect `Atlas\Binaries\Win64\MorePlayersPlus.log`. It records
hook installation, lobby calls, rich-presence return values, and EOS capacity
updates.

UE4SS `on_program_start` only schedules native installation. The first
`on_update` call applies the instruction patches. In the fallback, it then
creates the Steam lobby-limit and Wayfinder full-party hooks while they are
disabled, queues both hooks, and enables them with one `MH_ApplyQueued` call.
Keep this event-loop boundary and batch activation when you add or change
startup hooks. MinHook freezes all threads during `MH_ApplyQueued`, and one
startup crash occurred in `chrome_elf.dll` during that freeze. Synchronous startup activation blocks later
`enabled.txt` mods. Concurrent activation can crash while Wayfinder initializes.

## Updating the full-party hook

The full-party hook is a fallback. The DLL installs it only when the
[full-party threshold patch](#full-party-threshold-sites) does not apply. With
both patch groups active, the log contains `MinHook not activated`.

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
3. Open `Atlas\Binaries\Win64\MorePlayersPlus.log`.
4. Confirm that the log reports the updated RVA.
5. Confirm that the log contains the successful hook message.

```text
[MorePlayersPlus] Hooked UWFGameInstance::UpdateHostSessionFullParty[Wayfinder+0x164D770]
```

Treat `build signature mismatch` as a failed validation. Do not remove the byte
check to force installation.

## Instruction patches

During native installation, the DLL changes the immediate value 3 to the
configured `MaxPlayers` in two groups of instructions. `patch_immediates` in
`dllmain.cpp` applies each group.

### Session capacity sites

Wayfinder writes the constant 3 to `FOnlineSessionSettings::NumPublicConnections`
each time it builds the hosted session settings. The EOS and Steam hooks change
only the values in the outgoing calls. Without this patch, the host keeps 3 in
its local named session.

`UWFRichPresenceSubsystem::IsSessionJoinable` compares the player count with
the local value. At 3 players, the host clears the rich presence join
information and publishes a party maximum of 3.

These sites hold a 32-bit immediate value:

| RVA | Function | Original bytes |
|---|---|---|
| `0x16309C2` | `UWFGameInstance::CreateHostPc` | `48 C7 45 F8 03 00 00 00` |
| `0x163110A` | Defunct-session update | `48 C7 45 88 03 00 00 00` |
| `0x164D64C` | `UpdateHostSessionEmptyParty` | `C7 45 A8 03 00 00 00` |
| `0x164DA61` | `UpdateHostSessionFullParty` | `C7 45 A8 03 00 00 00` |

`NumPublicConnections` is at offset `+0x8` in the settings object. A 64-bit
`mov` with REX.W also writes 0 to `NumPrivateConnections` at `+0xC`.

### Full-party threshold sites

Both session refresh paths compare the GameState player count
(`PlayerArray.Num`, `+0x248`) with 3. At 3 or more players, they call
`UpdateHostSessionFullParty`, which disables join in progress and invites. For
a public session, the settings helper then enables advertisement and presence
join again. These sites hold a signed 8-bit immediate value:

| RVA | Function | Original bytes |
|---|---|---|
| `0x163099A` | `UWFGameInstance::CreateHostPc` | `83 BB 48 02 00 00 03` |
| `0x164D2EC` | Host-session refresh dispatcher | `83 BF 48 02 00 00 03` |

With the patch, Wayfinder publishes the full state only at `MaxPlayers`. The
DLL then does not install the full-party hook.

The DLL applies this group only after the session capacity group applies. If
either group does not apply, the DLL keeps the original threshold and installs
the hook as a fallback. Thus a partial match falls back to the earlier tested
configuration. A skipped threshold group writes this message:

```text
[MorePlayersPlus] Full-party threshold patch not attempted: the session capacity patch is not applied
```

Only these two instructions lead to `UpdateHostSessionFullParty`: a call at
`0x1416309A4` and a jump at `0x14164D30C`. No other code, pointer, or
RIP-relative reference refers to the function.

### Patch checks

A site matches when its instruction prefix is correct and its immediate value
is from 3 through 25. Thus a second installation in the same process finds the
value that it wrote earlier.

For each group, the DLL makes these checks before it writes a byte:

1. It confirms that each site is inside the loaded image.
2. It compares each site.
3. It makes each site writable.

If a check fails, the DLL changes no site in that group. A signature failure
writes this message:

```text
[MorePlayersPlus] Session capacity patch unavailable: build signature mismatch at ...; no sites changed
```

Successful patches write these messages:

```text
[MorePlayersPlus] Session capacity patch applied at 4 sites
[MorePlayersPlus] Full-party threshold patch applied at 2 sites
[MorePlayersPlus] MinHook not activated: both instruction patch groups apply
```

Several sites are on the same memory page (`0x14164D000`). The DLL restores
the page protections in reverse order, so that each page receives its original
protection last.

### Update the patch sites

1. Find each function through its log string or its full-party caller.
2. Find the instruction that holds the constant 3.
3. For a capacity site, confirm that the target object uses the
   `FOnlineSessionSettings` vtable.
4. Record the RVA and the instruction bytes before the immediate value.
5. Update `session_capacity_sites` or `full_party_threshold_sites` in
   `dllmain.cpp`.

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
