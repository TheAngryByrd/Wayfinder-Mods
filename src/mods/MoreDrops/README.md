# Wayfinder MoreDrops

MoreDrops increases loot probability and item amounts in Wayfinder. Each value
uses an independent multiplier.

The mod changes loot processed by Wayfinder's central loot spawner. It does not
change shop inventories or crafting costs.

The mod installs a Lua script and the Wayfinder UE4SS signature. It does not
replace the Wayfinder executable, game packages, or save files.

## Contents

<!-- toc:start -->
- [Configuration](#configuration)
- [Install](#install)
  - [Install UE4SS 3.0.1](#install-ue4ss-301)
  - [Install MoreDrops](#install-moredrops)
- [Confirm the mod is working](#confirm-the-mod-is-working)
- [Build](#build)
- [Technical notes](#technical-notes)
<!-- toc:end -->

## Configuration

Close Wayfinder. Then edit this installed file:

```text
Wayfinder\Atlas\Binaries\Win64\Mods\MoreDrops\config.ini
```

The default configuration increases probability and preserves item amounts:

```ini
ProbabilityMultiplier=2.0
MinAmountMultiplier=1.0
MaxAmountMultiplier=1.0
```

`ProbabilityMultiplier` changes each loot entry's probability.
`MinAmountMultiplier` changes its minimum item amount.
`MaxAmountMultiplier` changes its maximum item amount.

Each multiplier supports values from `1.0` through `100.0`. Restart Wayfinder
after each configuration change.

MoreDrops raises a scaled maximum when it is less than the scaled minimum. This
rule keeps every loot amount range valid.

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
```

Start Wayfinder. Confirm that `UE4SS.log` contains `[MoreDrops] Mod loaded`.

## Confirm the mod is working

Start Wayfinder and defeat an enemy that can generate loot. Open this file:

```text
Wayfinder\Atlas\Binaries\Win64\UE4SS.log
```

The file must contain the configured multiplier values and this message:

```text
[MoreDrops] Mod loaded
```

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

MoreDrops hooks this reflected Wayfinder function before loot generation:

```text
/Script/Wayfinder.WFLootSpawner:BP_SpawnLoot
```

The script changes `Probability`, `MinAmount`, and `MaxAmount` in each
`FWFLootTableRecordEntry`. The script does not change item identities or loot
distribution types.

Wayfinder controls the final random result. A multiplier does not guarantee a
specific item unless the scaled probability reaches the game's guarantee
threshold.
