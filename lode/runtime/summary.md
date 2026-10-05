# Runtime summary

UE4SS loads the Lua script and native DLL from the same `MorePlayers` mod. Both
components read `Mods/MorePlayers/config.ini` at process startup.

```mermaid
sequenceDiagram
    participant UE4SS
    participant Lua
    participant DLL
    participant Game as Wayfinder
    UE4SS->>Lua: Load main.lua
    UE4SS->>DLL: Call start_mod
    UE4SS->>DLL: Schedule native installation
    UE4SS->>UE4SS: Finish enabled.txt discovery
    UE4SS->>DLL: First event-loop update
    Lua->>Game: Set GameSession MaxPlayers
    DLL->>Game: Activate native hook batches
```

## Runtime files

```text
Mods/MorePlayers/Scripts/main.lua
Mods/MorePlayers/dlls/main.dll
Mods/MorePlayers/config.ini
```

## Invariants

- Lua changes Unreal object properties.
- C++ changes external online-service calls and six Wayfinder instructions:
  four session-capacity sites and two full-party threshold sites.
- C++ does not activate MinHook from the UE4SS startup callback.
- The first event-loop update applies the instruction patches, then activates the
  Steam hook and the optional full-party fallback hook as one batch.
- The native DLL keeps its separate diagnostic log.
- UE4SS records Lua output in `UE4SS.log`.

```cpp
virtual void on_program_start() { g_install_requested = true; }
```

Related: [Session capacity](session-capacity.md), [Party UI](party-ui.md), [Runtime diagnostics](diagnostics.md), and [Project summary](../summary.md).
