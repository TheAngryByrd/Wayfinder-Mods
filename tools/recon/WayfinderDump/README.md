# Wayfinder object dump

Copy `WayfinderDump` into `Atlas/Binaries/Win64/Mods`, then start Wayfinder.
The diagnostic creates `Atlas/Binaries/Win64/UE4SS_ObjectDump.txt` after 15
seconds. Press `Ctrl+F8` to request the dump manually during the same run.

Remove `enabled.txt` from the installed copy after the dump completes. Keep the
repository copy unchanged so the tool remains reusable.

Use UE4SS's built-in `Ctrl+H` key binding to generate `CXXHeaderDump`.
