# Loadouts UMG source

Open `Atlas.uproject` with Unreal Engine 4.27.
Keep every runtime asset below `/Game/Mods/Loadouts`.

The required assets are:

```text
/Game/Mods/Loadouts/ModActor
/Game/Mods/Loadouts/UI/WBP_LoadoutsPage
/Game/Mods/Loadouts/UI/WBP_LoadoutProfileRow
/Game/Mods/Loadouts/UI/WBP_LoadoutNameDialog
```

Create `ModActor` as an Actor Blueprint.
Create each `WBP_` asset as a Widget Blueprint.
Use only standard Unreal Engine classes inside these assets.

The build creates the Blueprint assets in its staged project.
`Content/Python/generate_loadouts_assets.py` creates each required asset.
The Lua UI bridge creates and controls the widget content at runtime.

Build the Pak from the repository root:

```powershell
.\build.ps1 -Mod Loadouts -UnrealRoot "C:\Program Files\Epic Games\UE_4.27"
```

You can set `WAYFINDER_UE427_ROOT` instead of the command parameter.
The build does not install the Pak into Wayfinder.
