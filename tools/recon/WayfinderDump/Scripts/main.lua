local dumped = false

local function dump_objects()
    if dumped then
        return
    end

    dumped = true
    print("[WayfinderDump] Starting UE4SS object dump\n")
    DumpAllObjects()
    print("[WayfinderDump] UE4SS object dump complete\n")
end

ExecuteWithDelay(15000, dump_objects)

RegisterKeyBind(Key.F8, { ModifierKey.CONTROL }, dump_objects)

print("[WayfinderDump] Loaded; automatic dump starts in 15 seconds\n")
