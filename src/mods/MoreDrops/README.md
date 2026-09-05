# Wayfinder MoreDrops

MoreDrops increases loot probability and item amounts in Wayfinder. Four
independent multipliers control core probability, final probability, minimum
amounts, and maximum amounts. Item probability rules can reduce or block
specific selected items. Rarity rules can reject disallowed Echoes,
accessories, and relics. An optional boss rule can guarantee eligible items
from each boss-specific unique pool. Resource-backed overrides can change
boss, world-boss, elite, and miniboss Echoes to Epic.

The mod changes loot processed by Wayfinder's central loot spawner. It does not
change shop inventories or crafting costs.

The mod installs a native UE4SS companion, a Lua diagnostic script, and the
Wayfinder UE4SS signature. It does not replace the Wayfinder executable, game
packages, or save files.

## Contents

<!-- toc:start -->
- [Configuration](#configuration)
  - [Hot reload](#hot-reload)
  - [Item probability](#item-probability)
  - [Echo rarity](#echo-rarity)
  - [Echo rarity override](#echo-rarity-override)
  - [Accessory rarity](#accessory-rarity)
  - [Boss unique drops](#boss-unique-drops)
  - [Item catalog](#item-catalog)
  - [Probability examples](#probability-examples)
  - [Amount examples](#amount-examples)
  - [Configuration examples](#configuration-examples)
  - [Invalid amount ranges](#invalid-amount-ranges)
- [Install](#install)
  - [Install UE4SS 3.0.1](#install-ue4ss-301)
  - [Install MoreDrops](#install-moredrops)
- [Confirm the mod is working](#confirm-the-mod-is-working)
- [Build](#build)
- [Technical notes](#technical-notes)
<!-- toc:end -->

## Configuration

Edit this installed file. Wayfinder can remain open:

```text
Wayfinder\Atlas\Binaries\Win64\Mods\MoreDrops\config.ini
```

The default configuration increases probability, preserves item amounts, and
keeps only Epic accessory and relic equipment:

```ini
[General]
CoreProbabilityMultiplier=2.0
FinalProbabilityMultiplier=1.0
MinAmountMultiplier=1.0
MaxAmountMultiplier=1.0

[ItemProbability]
# DataTableName:ItemRowName=0

[EchoFilter]
AllowedRarities=All

[AccessoryFilter]
AllowedRarities=Epic

[BossDrops]
DropAllUniques=false

[EchoRarityOverride]
Bosses=Original
WorldBosses=Original
RareEnemies=Original
```

`CoreProbabilityMultiplier` changes every core loot probability roll.
`FinalProbabilityMultiplier` changes records that use the final wrapper.
`MinAmountMultiplier` changes its minimum item amount.
`MaxAmountMultiplier` changes its maximum item amount.

The final wrapper calls the core generator. Thus, wrapper calls use both
probability multipliers. Direct core calls use only `CoreProbabilityMultiplier`.

Each multiplier supports values from `1.0` through `100.0`.

MoreDrops raises a scaled maximum when it is less than the scaled minimum. This
rule keeps every loot amount range valid.

### Hot reload

Save `config.ini` after you change a multiplier or filter rule. MoreDrops
checks the file timestamp before valid loot calls, but no more than once per
second. The first valid loot call that performs the next check uses the new
values. You do not need to restart Wayfinder.

A successful reload adds this line to `MoreDropsNative.log`:

```text
[MoreDropsNative] Config reloaded core_probability=2.00 final_probability=1.00 minimum=1.00 maximum=1.00 item_probability_rules=1 echo_rarities_requested=All echo_filter=active accessory_rarities=Epic boss_drop_all_uniques=true echo_override_bosses=Epic echo_override_world_bosses=Epic echo_override_rare_enemies=Epic boss_drop_hooks=active path=...
```

If the file is unavailable, the current settings remain active. MoreDrops tries
again during a later check. An invalid value produces an error and keeps the
previous value for that key.

### Item probability

The `[ItemProbability]` section controls selected item stacks. Each key uses a
stable `DataTable:RowName` value from an `Item diagnostic` log line.

```ini
[ItemProbability]
DataTableName:ItemRowName=0
```

Replace the example key with an exact `item_key` from `MoreDropsNative.log`.

| Value | Result |
| ---: | --- |
| `0` | Remove every selected stack for this item |
| `25` | Keep approximately 25% of selected stacks |
| `50` | Keep approximately 50% of selected stacks |
| `100` | Keep every selected stack |

An item probability is an absolute post-roll percentage. It does not multiply
the global probability values. One probability roll applies to the complete
selected stack.

MoreDrops checks the full `DataTable:RowName` key first. It also accepts only
the row name. Use the full key to prevent matches in another data table.

### Echo rarity

The `[EchoFilter]` section is an allow-list. MoreDrops keeps an Echo only when
its rolled rarity is in `AllowedRarities`.

```ini
[EchoFilter]
AllowedRarities=Epic
```

This example keeps Epic Echoes and rejects Common, Uncommon, and Rare Echoes.
Rare is blue. Epic is purple.

| Value | Result |
| --- | --- |
| `All` | Keep every Echo rarity |
| `None` | Reject every assigned Echo rarity |
| `Rare` | Keep only blue Rare Echoes |
| `Epic` | Keep only purple Epic Echoes |
| `Rare,Epic` | Keep blue Rare and purple Epic Echoes |

MoreDrops records the rarity after Wayfinder rolls it. For a disallowed Echo,
the mod makes Wayfinder use its normal temporary-item rejection path before the
item is appended. The filter does not compact the inventory array and does not
destroy a live inventory entry.

The filter applies only during the synchronous central loot spawn. An unknown
rarity, an unexpected call path, or a hook signature mismatch keeps the Echo.
This fail-open rule prevents the filter from acting on an unverified object.

Use an `[ItemProbability]` rule when you want to block all stacks for one Echo
item key, regardless of rarity.

### Echo rarity override

The `[EchoRarityOverride]` section can force resource-classified Echo groups
to purple Epic after Wayfinder rolls their rarity.

```ini
[EchoRarityOverride]
Bosses=Epic
WorldBosses=Epic
RareEnemies=Epic
```

Each setting accepts `Original` or `Epic`. `Original` preserves Wayfinder's
roll. `Epic` changes a matching Echo to Epic before `[EchoFilter]` checks it.

`Bosses` covers the exact Echo rows used by normal and Mythic boss sources.
`WorldBosses` covers the current overland minibosses: Ancient One, Bone
Crusher, and Howler. `RareEnemies` covers all current resource assets marked
as elites or minibosses, including Grim Morningstar.

The groups use exact `CreatureEchoItems` row names extracted from the current
Wayfinder resources. Unknown rows keep their original rarity. A game update
that adds Echo rows requires an updated MoreDrops classifier.

The override does not bypass filters. If `[EchoFilter]` excludes Epic, a
forced Epic Echo is rejected. An `[ItemProbability]` value of `0` also blocks
the item.

### Accessory rarity

The `[AccessoryFilter]` section is an allow-list for accessory equipment and
relic drops.

```ini
[AccessoryFilter]
AllowedRarities=Epic
```

This example keeps only purple Epic accessories and relics. The setting
accepts the same values as `[EchoFilter]`: `All`, `None`, `Common`,
`Uncommon`, `Rare`, `Epic`, or a comma-separated list such as `Rare,Epic`.

The filter uses rarity names encoded by Wayfinder's
`AccessoryInventoryItems` data. It recognizes the 522 accessory and relic
rows in the current game data. The two accessory recipe rows are not
filtered.

The filter runs after Wayfinder selects the item and before it grants the
item. An unknown accessory or relic name stays in the loot result and uses
the `kept-fail-open` diagnostic action. This rule prevents a game update from
silently removing a new item.

When an `[ItemProbability]` rule and `[AccessoryFilter]` both apply, both
filters must keep the item. Either filter can remove the complete selected
stack.

### Boss unique drops

The `[BossDrops]` section can guarantee eligible items from each
boss-specific unique pool.

```ini
[BossDrops]
DropAllUniques=true
```

This rule applies to normal and Mythic boss chests. It does not apply to named
elites or normal enemy loot.

The rule includes boss-specific weapons, armor, accessories, relics,
cosmetics, resources, pets, trophies, titles, and Echoes. The rule excludes
shared currency, spectra, gloomstone, summoning stones, and quest items.

Wayfinder still evaluates tag queries, level rules, and other preconditions.
An ineligible or disabled item stays excluded.

The boss rule creates candidate drops. The existing filters remain
authoritative. `ItemProbability`, `AccessoryFilter`, and `EchoFilter` can
still remove an applicable item.

For example, these settings guarantee each eligible boss unique and keep only

```ini
[BossDrops]
DropAllUniques=true

[EchoRarityOverride]
Bosses=Epic
WorldBosses=Epic
RareEnemies=Epic

[EchoFilter]
AllowedRarities=Epic

[AccessoryFilter]
AllowedRarities=Epic
```

This configuration does not restore a Rare accessory after its rarity filter
removes it. The Echo overrides run before the Echo filter. An
`[ItemProbability]` value of `0` also remains a complete block.

### Item catalog

MoreDrops does not generate `ItemCatalog.tsv` in this release. The UE4SS Lua
bridge crashed while it converted reflected data-table arrays.

```text
[MoreDrops] Item catalog disabled; UE4SS reflected array conversion is unsafe
```

Use `Item diagnostic` lines to find item keys. Copy the complete `item_key`
value into `[ItemProbability]`. The filter and diagnostics remain active.

### Probability examples

Probability decides whether a loot entry drops. MoreDrops uses this
calculation for a direct core call:

```text
scaled probability = original probability * CoreProbabilityMultiplier
```

MoreDrops uses this calculation for a final wrapper call:

```text
scaled probability = original probability * FinalProbabilityMultiplier * CoreProbabilityMultiplier
```

Wayfinder treats a probability of `100` as guaranteed in the observed loot
records. A value above `100` remains guaranteed and does not create extra
copies.

CAUTION: Do not set both probability multipliers to `100.0` for normal play.
The combined multiplier is `10000.0`. This value can create an excessive
inventory workload and make the game unstable.

MoreDrops writes this warning when the combined multiplier is greater than
`100.0`:

```text
[MoreDropsNative] High loot workload warning combined_probability_multiplier=10000.00 Reduce CoreProbabilityMultiplier or FinalProbabilityMultiplier
```

With `CoreProbabilityMultiplier=20.0` and
`FinalProbabilityMultiplier=1.0`:

| Original probability | Scaled probability | Result |
| ---: | ---: | --- |
| `0.5` | `10` | Approximately 10% |
| `1` | `20` | Approximately 20% |
| `2.5` | `50` | Approximately 50% |
| `5` | `100` | Guaranteed |
| `10` | `200` | Guaranteed |
| `100` | `2000` | Still guaranteed |

Thus, a multiplier of `20.0` guarantees each entry with an original
probability of `5` or higher.

For another example, use these values:

```ini
CoreProbabilityMultiplier=10.0
FinalProbabilityMultiplier=2.0
```

A direct core call changes a probability of `5` to `50`. A final wrapper call
changes the same probability to `100` because it uses both values.

The final wrapper often receives entries that already have a probability of
`100`. Increasing these entries does not increase their drop chance.

### Amount examples

Minimum and maximum amounts decide the quantity after a probability roll
succeeds. MoreDrops uses these calculations:

```text
scaled minimum = original minimum * MinAmountMultiplier
scaled maximum = original maximum * MaxAmountMultiplier
```

With `MinAmountMultiplier=5.0` and `MaxAmountMultiplier=10.0`:

| Original range | Scaled range | Possible amount |
| --- | --- | --- |
| `1-1` | `5-10` | 5 through 10 |
| `1-2` | `5-20` | 5 through 20 |
| `2-4` | `10-40` | 10 through 40 |
| `5-10` | `25-100` | 25 through 100 |

Runtime diagnostics confirmed that original `1-1` entries produced amounts
from `5` through `10` with these settings.

### Configuration examples

Increase probability without changing amounts:

```ini
[General]
CoreProbabilityMultiplier=2.0
FinalProbabilityMultiplier=1.0
MinAmountMultiplier=1.0
MaxAmountMultiplier=1.0
```

A 25% entry becomes 50%. An original `1-3` amount remains `1-3`.

Double probability and amounts:

```ini
[General]
CoreProbabilityMultiplier=2.0
FinalProbabilityMultiplier=1.0
MinAmountMultiplier=2.0
MaxAmountMultiplier=2.0
```

A 25% entry becomes 50%. An original `1-3` amount becomes `2-6`.

Increase maximum amounts more than minimum amounts:

```ini
[General]
CoreProbabilityMultiplier=5.0
FinalProbabilityMultiplier=1.0
MinAmountMultiplier=2.0
MaxAmountMultiplier=5.0
```

A 10% entry becomes 50%. An original `1-3` amount becomes `2-15`.

### Invalid amount ranges

Independent multipliers can make the scaled maximum smaller than the scaled
minimum. MoreDrops sets the maximum equal to the minimum in this condition.

```text
Original range: 3-4
MinAmountMultiplier: 10
MaxAmountMultiplier: 1
Calculated range: 30-4
Corrected range: 30-30
```

## Install

This package does not contain UE4SS. Install the compatible Wayfinder UE4SS
3.0.1 setup first.

### Install UE4SS 3.0.1

1. Download [`UE4SS_v3.0.1.zip`](https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip).
2. Close Wayfinder.
3. Open the Wayfinder installation directory in Steam.
4. Open `Atlas\Binaries\Win64`.
5. Remove an old `xinput1_3.dll` file from this directory.
6. Extract the UE4SS archive contents into `Atlas\Binaries\Win64`.
7. Do not start Wayfinder until you install MoreDrops.

The MoreDrops archive includes the required `GUObjectArray.lua` signature.
UE4SS uses this signature to find Wayfinder objects.

### Install MoreDrops

1. Close Wayfinder.
2. Extract the MoreDrops archive into the Wayfinder installation directory.
3. Permit file replacement when Windows asks for confirmation.

Confirm that these files exist:

```text
Wayfinder\Atlas\Binaries\Win64\Mods\MoreDrops\enabled.txt
Wayfinder\Atlas\Binaries\Win64\Mods\MoreDrops\config.ini
Wayfinder\Atlas\Binaries\Win64\Mods\MoreDrops\Scripts\main.lua
Wayfinder\Atlas\Binaries\Win64\Mods\MoreDrops\dlls\main.dll
```

Start Wayfinder. Confirm that `UE4SS.log` contains `[MoreDrops] Mod loaded`.
Also confirm that `Mods\MoreDrops\MoreDropsNative.log` contains `Native scaler active`.

## Confirm the mod is working

Start Wayfinder and defeat an enemy that can generate loot. Open these files:

```text
Wayfinder\Atlas\Binaries\Win64\UE4SS.log
Wayfinder\Atlas\Binaries\Win64\Mods\MoreDrops\MoreDropsNative.log
```

`MoreDropsNative.log` must contain the configured multiplier values and this
message:

```text
[MoreDropsNative] Native companion installation deferred until Unreal startup settles
[MoreDropsNative] Unreal initialization complete; native hook installation delayed 5000 ms
[MoreDropsNative] Native scaler active core=Wayfinder+0x1B12B40 result=Wayfinder+0x1B09200
```

After you save a configuration change, generate loot and confirm that the log
contains `Config reloaded` with the new values.

`UE4SS.log` must confirm that the unsafe catalog scan is disabled:

```text
[MoreDrops] Item catalog disabled; UE4SS reflected array conversion is unsafe
```

Generate loot, then find `Core Entry diagnostic`, `Final Entry diagnostic`,
`Item diagnostic`, `Accessory diagnostic`, `Echo roll diagnostic`,
`Echo filter diagnostic`, `Boss unique diagnostic`, `Core result diagnostic`,
and `Result diagnostic` in `MoreDropsNative.log`. Core lines cover all core
calls. Final lines cover final wrapper calls. The other lines identify
guarantees and filter actions.

```text
[MoreDropsNative] Final Entry diagnostic call=1 entry=0 probability=0.05->0.1 minimum=1->1 maximum=1->1
[MoreDropsNative] Core Entry diagnostic call=1 entry=0 probability=0.1->1 minimum=1->5 maximum=1->10
[MoreDropsNative] Item diagnostic call=1 destination=inventory item_key=DataTableName:ItemRowName amount=5 level=1 item_probability=0.00 action=removed
[MoreDropsNative] Item filter diagnostic call=1 examined=1 removed=1 removed_units=5 rules=1
[MoreDropsNative] Accessory diagnostic call=1 destination=inventory item_key=AccessoryInventoryItems:Accessory_Name_Rare1 amount=1 level=1 rarity=Rare allowed_rarities=Epic action=removed
[MoreDropsNative] Accessory filter diagnostic call=1 examined=1 removed=1 unknown=0 allowed_rarities=Epic
[MoreDropsNative] Boss unique diagnostic call=1 action=boss-context-detected variables=11
[MoreDropsNative] Boss unique diagnostic call=1 distribution=weighted mode=selective normal_entries=0 guaranteed_entries=2 router_entries=1
[MoreDropsNative] Core result diagnostic call=1 source=0x... entries=3 changed=3 manifest_items=0 manifest_item_units=0 ...
[MoreDropsNative] Result diagnostic call=1 source=0x... entries=3 player_items=0 player_item_units=0 ...
```

The startup and loot logs must confirm the pre-append Echo filter is active:

```text
[MoreDropsNative] Echo rarity filter active roll=Wayfinder+0x178C0F0 gate=Wayfinder+0x177E1A0 cleanup=Wayfinder+0x177E38D mode=pre-append-fail-open allowed_rarities=Epic
[MoreDropsNative] Echo roll diagnostic call=1 item_key=DataTableName:ItemRowName rarity=Rare allowed_rarities=Epic decision=reject-pending
[MoreDropsNative] Echo filter diagnostic call=1 item_key=DataTableName:ItemRowName rarity=Rare action=rejected-before-append
[MoreDropsNative] Echo rarity override diagnostic call=2 item_key=CreatureEchoItems:GrimMorningstarEcho group=RareEnemies rolled_rarity=Rare forced_rarity=Epic action=forced
```

MoreDrops logs the first 40 changed entries for each hook. It also logs the
first 1,000 selected items, the first 1,000 selected accessories and relics,
the first 1,000 Echo rarity rolls, and 200 loot results after each game start.
The limits prevent continuous log growth. Loot changes remain active after
the diagnostic limits.

MoreDrops also logs bounded `Loot trace` events for gameplay loot stages. These
events identify paths that bypass the central Blueprint loot wrapper.

```text
[MoreDrops] Loot trace event=resource-grant count=1 context=...
```

Each trace event logs at most ten calls after each game start.

If the hook fails, the log tells you to verify the Wayfinder version.

## Build

Run this command from the repository root:

```powershell
.\build.ps1 -Mod MoreDrops
```

The build creates these outputs:

```text
dist\NexusMods\MoreDrops
dist\Wayfinder-MoreDrops-NexusMods.zip
```

Use `-NoArchive` to create only the unpacked package.

## Technical notes

The native companion schedules MinHook installation during `on_program_start`.
It installs the hooks from the UE4SS event loop five seconds after Unreal
initialization. This sequence lets UE4SS finish all `enabled.txt` mod discovery
and lets Unreal startup settle before MoreDrops changes game code.

MoreDrops hooks the core probability generator and the final result function:

```text
/Script/Wayfinder.WFLootSpawner:BP_SpawnLoot
Core probability generator: Wayfinder+0x1B12B40
Final result function: Wayfinder+0x1B09200
Item name conversion: Wayfinder+0x1F08B30
Echo rarity assignment: Wayfinder+0x178C0F0
Inventory append gate: Wayfinder+0x177E1A0
Temporary cleanup branch: Wayfinder+0x177E38D
Inventory distribution helper: Wayfinder+0x1B0D5D0
Uniform distribution helper: Wayfinder+0x1B0DCD0
Weighted distribution helper: Wayfinder+0x1B0E5D0
```

The final hook temporarily changes `Probability` for final wrapper calls. The
core hook temporarily changes `Probability`, `MinAmount`, and `MaxAmount` for
all core calls. Each hook restores the source record after its function
returns. The mod does not change item identities or loot distribution types.

The core hook reads each selected `FInventoryItemCreationParams` row handle.
It records the stable item key in diagnostics before it applies post-roll item
rules. The filter compacts the three item manifest arrays before Wayfinder
grants them. Nested loot tables use one item probability roll at the outer core
result.

The accessory filter uses the same item manifest stage. It checks only rows
from `AccessoryInventoryItems` whose names start with `Accessory_` or
`Relic_`. It reads the static rarity suffix used by the current Wayfinder
resource. Three internal talent tester rows use an explicit Rare mapping.
Recipe rows bypass the filter. An unrecognized equipment row fails open.

The boss rule identifies boss contexts through their `CreatureEcho` and
`CosmeticSet` loot variables. These two variables identify all 50 boss-chest
sources in the current game data and no other source.

The boss rule calls Wayfinder's normal distribution helpers once for each
eligible unique entry. This expands weighted and uniform groups without direct
result-array allocation. The `AP_Enemy_Boss` router keeps one generic
selection and separately expands its source-specific accessory pools.

The Echo rarity override uses exact `CreatureEchoItems` row names extracted
from Wayfinder resources. The current classifier contains 57 boss rows, three
overland world-boss rows, and 102 elite or miniboss rows. It classifies the
item after Wayfinder assigns rarity, so delayed Echo creation does not depend
on an earlier boss-call scope.

MoreDrops does not move or destroy an `FInventoryItemEntry` value. The Echo
filter records rarity on the temporary item specification. A guarded assembly
gate runs immediately before Wayfinder increments the output-array count. A
matching disallowed Echo uses Wayfinder's existing cleanup branch. An allowed
item continues through the MinHook trampoline. This design replaces the
crash-prone array compaction from version 0.8.0.

The Lua script does not scan loaded `DataTable` objects. UE4SS cannot safely
convert the reflected output arrays used by the catalog implementation.

Both loot hooks check the configuration timestamp inside their shared recursive
mutex. A successful reload replaces the complete active settings object before
the loot record is scaled or filtered.

Each hook verifies its target and related call-site byte signatures before it
starts. If the Echo signatures do not match, global scaling and item rules stay
active, but Echo filtering fails open. A changed core or final signature
disables native scaling and writes a build signature error.

Wayfinder controls the final random result. A multiplier does not guarantee a
specific item unless the scaled probability reaches the game's guarantee
threshold.
