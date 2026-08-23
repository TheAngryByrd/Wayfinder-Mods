local MAX_PLAYERS = 25
local CONFIG_PATH = "Mods/MorePlayers/config.ini"
local PARTY_UI_DIAGNOSTICS = true

local function load_max_players()
    if not io or not io.open then
        print("[MorePlayers] Lua file I/O unavailable; using MaxPlayers=25\n")
        return
    end

    local file = io.open(CONFIG_PATH, "r")
    if not file then
        print(string.format("[MorePlayers] Config not found at %s; using MaxPlayers=25\n", CONFIG_PATH))
        return
    end

    local max_players_found = false
    for line in file:lines() do
        local value = line:match("^%s*MaxPlayers%s*=%s*(%d+)%s*$")
        if value then
            local parsed = tonumber(value)
            if parsed and parsed >= 3 and parsed <= 25 then
                MAX_PLAYERS = parsed
                max_players_found = true
            end
        end

        local diagnostics = line:match("^%s*PartyUiDiagnostics%s*=%s*(%d+)%s*$")
        if diagnostics then
            PARTY_UI_DIAGNOSTICS = diagnostics ~= "0"
        end
    end

    file:close()
    if max_players_found then
        print(string.format("[MorePlayers] Config MaxPlayers=%d\n", MAX_PLAYERS))
    else
        print("[MorePlayers] Config missing/invalid MaxPlayers; using 25\n")
    end
end

local function get_object_text(object, member)
    local ok, value = pcall(function()
        return object[member]
    end)
    if not ok then
        return "<unavailable>"
    end
    return tostring(value)
end

local function dump_party_ui(reason)
    if not PARTY_UI_DIAGNOSTICS then
        return
    end

    ExecuteInGameThread(function()
        local widgets = FindAllOf("Widget") or {}
        local matched = 0
        print(string.format("[MorePlayers] Party UI snapshot begin reason=%s widgets=%d\n", reason, #widgets))

        for _, widget in ipairs(widgets) do
            local ok, full_name = pcall(function()
                return widget:GetFullName()
            end)
            if ok and full_name then
                local lower_name = full_name:lower()
                if lower_name:find("party", 1, true)
                    or lower_name:find("invite", 1, true)
                    or lower_name:find("sessioncode", 1, true)
                    or lower_name:find("session_code", 1, true)
                then
                    matched = matched + 1
                    print(string.format(
                        "[MorePlayers] Party UI widget name=%s visibility=%s enabled=%s\n",
                        full_name,
                        get_object_text(widget, "Visibility"),
                        get_object_text(widget, "bIsEnabled")
                    ))
                end
            end
        end

        print(string.format("[MorePlayers] Party UI snapshot end matched=%d\n", matched))
    end)
end

load_max_players()

print("[MorePlayers] Mod loaded\n")

local function update_session(context, label)
    context.MaxPlayers = MAX_PLAYERS
    print(string.format(
        "[MorePlayers] %s MaxPlayers: %d\n",
        label,
        context.MaxPlayers
    ))
end

NotifyOnNewObject("/Script/Engine.GameSession", function(context)
    update_session(context, "Engine")
end)

NotifyOnNewObject("/Script/AirshipUtil.AirshipGameSession", function(context)
    update_session(context, "Airship")
end)

NotifyOnNewObject("/Script/Wayfinder.WFGameSession", function(context)
    update_session(context, "Wayfinder")
end)

NotifyOnNewObject("/Script/Wayfinder.MayhemGameSession", function(context)
    update_session(context, "Mayhem")
end)

if PARTY_UI_DIAGNOSTICS then
    RegisterHook("/Script/Engine.GameStateBase:AddPlayerState", function()
        ExecuteWithDelay(1000, function()
            dump_party_ui("AddPlayerState")
        end)
    end)

    RegisterKeyBind(Key.F9, function()
        dump_party_ui("F9")
    end)

    print("[MorePlayers] Party UI diagnostics enabled; press F9 for a snapshot\n")
end
