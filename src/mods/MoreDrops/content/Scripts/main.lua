local TRACE_EVENT_LIMIT = 10
local trace_event_counts = {}

local function unwrap_parameter(parameter)
    if parameter == nil then
        return nil
    end

    local ok, value = pcall(function()
        return parameter:get()
    end)
    if ok then
        return value
    end
    return parameter
end

local function get_object_name(parameter)
    local value = unwrap_parameter(parameter)
    if value == nil then
        return "<nil>"
    end

    local ok, name = pcall(function()
        return value:GetFullName()
    end)
    if ok and name then
        return tostring(name)
    end
    return tostring(value)
end

local function handle_trace(event, context_parameter)
    local count = (trace_event_counts[event] or 0) + 1
    trace_event_counts[event] = count
    if count <= TRACE_EVENT_LIMIT then
        print(string.format(
            "[MoreDrops] Loot trace event=%s count=%d context=%s\n",
            event,
            count,
            get_object_name(context_parameter)
        ))
    end
end

local function register_trace_hook(path, event)
    local ok, trace_error = pcall(function()
        RegisterHook(path, function(context_parameter)
            handle_trace(event, context_parameter)
        end)
    end)

    if ok then
        print(string.format("[MoreDrops] Loot trace ready event=%s\n", event))
    else
        print(string.format(
            "[MoreDrops] Loot trace unavailable event=%s error=%s\n",
            event,
            tostring(trace_error)
        ))
    end
end

local TRACE_HOOKS = {
    { "/Script/Wayfinder.WFBreakableComponent:AUTH_Break", "breakable-auth-break" },
    { "/Script/Wayfinder.WFPlayerController:SERVER_SpawnLootForClientSideBreakable", "breakable-loot-request" },
    { "/Script/Wayfinder.ResourceContainerComponent:AUTH_CheckAndGrantContents", "resource-check-and-grant" },
    { "/Script/Wayfinder.ResourceContainerComponent:AUTH_GrantContents", "resource-grant" },
    { "/Script/Wayfinder.ResourceContainerComponent:AUTH_GrantContentsToPawns", "resource-grant-pawns" },
    { "/Script/Wayfinder.ResourceContainerComponent:NETMULTICAST_OnLootGrantedToPlayer", "resource-loot-granted" },
    { "/Script/Wayfinder.WFPickup:OnLootUpdated", "pickup-loot-updated" },
    { "/Script/Wayfinder.WFPickup:OnAwarded", "pickup-awarded" },
    { "/Script/Wayfinder.WFPickup:OnPickedUp", "pickup-picked-up" },
    { "/Script/Wayfinder.WFPlayerController:SERVER_ConsumeLootManifest", "loot-manifest-server-consume" },
    { "/Script/Wayfinder.WFPlayerController:TryConsumeLootManifest", "loot-manifest-try-consume" },
    { "/Script/Wayfinder.WFCharacter:BP_AuthOnDeath", "character-auth-death" },
}

for _, trace_hook in ipairs(TRACE_HOOKS) do
    register_trace_hook(trace_hook[1], trace_hook[2])
end

print("[MoreDrops] Item catalog disabled; UE4SS reflected array conversion is unsafe\n")

print("[MoreDrops] Mod loaded; native scaler handles loot changes and result diagnostics\n")
