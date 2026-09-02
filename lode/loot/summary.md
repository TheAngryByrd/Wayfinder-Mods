# Loot summary

MoreDrops changes loot records before Wayfinder generates loot. The mod has
independent core probability, final probability, minimum amount, and maximum
amount multipliers. Post-roll rules can block selected item stacks. Version
0.10.0 rejects disallowed accessory and relic rarities in the item manifest.
It rejects disallowed Echo rarities before inventory entries are appended.

```mermaid
flowchart LR
    Config[Multipliers and filter rules] --> Reload[Runtime config reload]
    UE4SS[UE4SS mod discovery] --> Unreal[Unreal initialization]
    Unreal --> EventLoop[Event-loop update after five seconds]
    EventLoop --> Native
    Reload --> Native[MoreDrops native DLL]
    Source[Loot source] --> Spawner[WFLootSpawner]
    Native --> FinalHook[Final wrapper hook]
    Native --> CoreHook[Core probability hook]
    FinalHook --> Record[Loot record]
    CoreHook --> Record
    Record --> Spawner
    Spawner --> Result[Loot result]
    Result --> Diagnostic[Result diagnostic]
    Result --> ItemFilter[Item probability filter]
    ItemFilter --> ItemLog[Item diagnostic keys]
    Config --> EchoSetting[Echo rarity allow-list]
    EchoSetting --> EchoRoll[Temporary Echo rarity roll]
    EchoRoll --> EchoReject[Normal pre-append rejection]
    Config --> AccessorySetting[Accessory rarity allow-list]
    AccessorySetting --> ItemFilter
    Lua[MoreDrops Lua] --> Disabled[Catalog scan disabled]
    Lua --> Trace[Gameplay-stage traces]
```

## Contract

- `CoreProbabilityMultiplier` defaults to `2.0`.
- `FinalProbabilityMultiplier` defaults to `1.0`.
- `MinAmountMultiplier` defaults to `1.0`.
- `MaxAmountMultiplier` defaults to `1.0`.
- Each multiplier supports values from `1.0` through `100.0`.
- Each item probability supports values from `0` through `100`.
- An item probability applies to one complete selected item stack.
- The filter checks a full item key before it checks a row-only key.
- The Lua item-catalog scan is disabled because UE4SS reflected array conversion crashes.
- Item diagnostics provide stable keys for observed loot items.
- The Echo rarity setting accepts `Common`, `Uncommon`, `Rare`, and `Epic`.
- The native log reports the requested Echo rarity value.
- Version 0.10.0 applies the Echo allow-list during synchronous central loot spawning.
- Rare Echoes are blue. Epic Echoes are purple.
- A disallowed Echo follows Wayfinder's normal temporary-item cleanup path.
- Echo filtering fails open when a rarity, call path, or hook signature is not verified.
- MoreDrops does not compact or destroy generated inventory entries.
- The accessory rarity setting accepts `Common`, `Uncommon`, `Rare`, and `Epic`.
- The accessory filter applies only to `Accessory_` and `Relic_` rows in
  `AccessoryInventoryItems`.
- Accessory recipe rows bypass the accessory filter.
- An unknown accessory or relic row fails open.
- MoreDrops checks `config.ini` before valid loot calls, but no more than once per second.
- A successful reload applies one complete settings object before scaling and filtering.
- A missing or unreadable configuration leaves the active settings unchanged.
- The mod changes loot processed by all callers of the core `WFLootSpawner` generator.
- The mod does not change item identities or loot distribution types.
- The mod raises a scaled maximum when it is less than the scaled minimum.
- The native hook restores source record values after each synchronous loot call.
- The mod logs the first 40 changed loot entries for each native hook.
- The mod logs result counts and item units for the first 200 loot calls.
- The mod logs the first 1,000 selected item results.
- The mod logs the first 1,000 Echo rarity rolls.
- The mod logs the first ten calls for each selected gameplay loot stage.
- Every native hook target requires a matching Wayfinder build signature.
- Native hook installation runs from the event loop five seconds after Unreal
  initialization and after UE4SS finishes `enabled.txt` mod discovery.

## Configuration example

```ini
[General]
CoreProbabilityMultiplier=2.0
FinalProbabilityMultiplier=1.0
MinAmountMultiplier=1.0
MaxAmountMultiplier=1.0

[ItemProbability]
DataTableName:ItemRowName=0

[EchoFilter]
AllowedRarities=All

[AccessoryFilter]
AllowedRarities=Epic
```

A successful runtime update has this form:

```text
[MoreDropsNative] Config reloaded core_probability=2.00 final_probability=1.00 minimum=1.00 maximum=1.00 item_probability_rules=1 echo_rarities_requested=All echo_filter=active accessory_rarities=Epic path=...
```

Related: [Drop scaling](drop-scaling.md), [Item filtering](item-filtering.md),
[Item catalog](item-catalog.md), [Runtime reflection](../runtime/reflection.md), and
[Build system](../distribution/build-system.md).
