# Wayfinder Mods

This repository contains mods for Wayfinder.
Select a mod to see its installation, configuration, build, and troubleshooting instructions.

## Contents

<!-- toc:start -->
- [Mods](#mods)
  - [MorePlayers](#moreplayers)
  - [MoreDrops](#moredrops)
  - [Loadouts](#loadouts)
  - [SkipStartupWarnings](#skipstartupwarnings)
- [Add another mod](#add-another-mod)
- [Build](#build)
  - [Build options](#build-options)
- [Project layout](#project-layout)
<!-- toc:end -->

## Mods

### MorePlayers

MorePlayers lets a Wayfinder host play with more than three people.
The host can set the maximum player count from 3 through 25.
Joining players do not need the mod.
Wayfinder automatically scales the game for the number of connected players.

The mod keeps Steam invitations and public joining available beyond the normal three-player limit.

See the [MorePlayers documentation](src/mods/MorePlayers/README.md).

### MoreDrops

MoreDrops increases loot probability and item amounts. Each value uses an
independent multiplier, so users can change probability and amount ranges
separately.

See the [MoreDrops documentation](src/mods/MoreDrops/README.md).

### Loadouts

> [!WARNING]
> **WIP:** Loadouts does not currently work. Do not install or use this mod.
> Saving a loadout can crash Wayfinder.

The Loadouts design stores named style, armor, weapon, Echo, talent, and
ability configurations. It is intended to validate saved parts before application.

See the [Loadouts documentation](src/mods/Loadouts/README.md).

### SkipStartupWarnings

SkipStartupWarnings closes the epilepsy and autosave warning pages during
startup. It can also load a configured existing profile. It preserves the
normal in-game autosave indicator.

See the [SkipStartupWarnings documentation](src/mods/SkipStartupWarnings/README.md).

## Add another mod

1. Create `src\mods\<ModName>`.
2. Copy the [MorePlayers manifest](src/mods/MorePlayers/mod.json) to the new directory.
3. Set the new mod identity and archive name in `mod.json`.
4. Create `src\mods\<ModName>\README.md` with the complete mod documentation.
5. Put installable mod files in `src\mods\<ModName>\content`.
6. Put an optional CMake project in `src\mods\<ModName>\native`.
7. Add the native CMake target to `mod.json` when the mod uses a DLL.

Use the [manifest schema](schemas/mod.schema.json) to validate `mod.json`.

## Build

`build.ps1` discovers each `src\mods\<ModName>\mod.json` manifest.
Without `-Mod`, the script builds every discovered mod.

For each selected mod, the script:

1. Validates manifest values and unique package names.
2. Updates the root, mod, and native README tables of contents.
3. Compiles the optional native CMake target.
4. Cooks and verifies an optional UMG Pak.
5. Recreates the mod's unpacked package directory.
6. Copies the content, compiled files, shared signature, and mod README.
7. Creates the ZIP archive unless `-NoArchive` is set.

Native output uses `build\native\<ModName>\<Configuration>`.
Unpacked packages use `dist\NexusMods\<ModName>`.
Archive names come from each mod manifest.

Build all discovered mods:

```powershell
.\build.ps1
```

Build one mod:

```powershell
.\build.ps1 -Mod <ModName>
```

Build multiple selected mods:

```powershell
.\build.ps1 -Mod MorePlayers,AnotherMod
```

List discovered mods without building them:

```powershell
.\build.ps1 -ListMods
```

### Build options

| Option | Effect |
| --- | --- |
| `-Mod <Name>` | Builds only the selected mod. Supply a comma-separated list for multiple mods. |
| `-Configuration <Name>` | Selects `Debug`, `Release`, `RelWithDebInfo`, or `MinSizeRel`. The default is `Release`. |
| `-SkipNativeBuild` | Reuses an existing native DLL from the selected configuration. |
| `-SkipUmgBuild` | Reuses an existing UMG Pak from `build\umg\<ModName>\pak`. |
| `-UnrealRoot <Path>` | Supplies the Unreal Engine 4.27 installation for a UMG build. |
| `-NoArchive` | Creates the unpacked package without creating its ZIP archive. |
| `-ListMods` | Lists discovered manifests without building packages. |

Native builds require Visual Studio 2022 with Desktop development with C++.
They also require CMake 3.22 or newer.
UMG builds require Unreal Engine 4.27. You can set `WAYFINDER_UE427_ROOT`
instead of using `-UnrealRoot`.

## Project layout

```text
AGENTS.md                              Project instructions for coding agents
README.md                              Mod catalog and shared contributor guide
build.ps1                              Manifest-based package builder
schemas\mod.schema.json                Mod manifest schema
scripts\build-native.ps1               Shared CMake build tool
scripts\build-umg.ps1                  Shared Unreal cook and Pak build tool
scripts\update-toc.ps1                 Markdown TOC generator
src\mods\<ModName>\mod.json            Package definition
src\mods\<ModName>\README.md           Complete mod documentation
src\mods\<ModName>\content             Files installed in the UE4SS mod directory
src\mods\<ModName>\native              Optional C++ source
src\mods\<ModName>\umg                 Optional Unreal Engine 4.27 project
src\mods\<ModName>\validate.ps1        Optional offline source and package validation
src\shared\UE4SS_Signatures             Shared Wayfinder UE4SS signature
tools\lua\5.4.4                         Vendored Lua 5.4.4 syntax tool source
tools\recon\WayfinderDump               Reusable reflection diagnostic
lode                                   Persistent project knowledge
lode\tmp                               Ignored session handoffs and temporary notes
build\native\<ModName>                  Generated native build files
build\tools                              Generated offline validation tools
build\umg\<ModName>                     Generated UMG cook and Pak files
dist\NexusMods\<ModName>                Generated package directory
dist\<ArchiveName>.zip                  Generated package archive
```

Commit source files, build tools, and permanent Lode files.
Do not commit `lode\tmp` or generated files under `build` and `dist`.
