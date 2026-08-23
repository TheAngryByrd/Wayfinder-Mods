local MAX_PLAYERS = 25
local CONFIG_PATH = "Mods/MorePlayers/config.ini"

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

    for line in file:lines() do
        local value = line:match("^%s*MaxPlayers%s*=%s*(%d+)%s*$")
        if value then
            local parsed = tonumber(value)
            if parsed and parsed >= 3 and parsed <= 25 then
                MAX_PLAYERS = parsed
                file:close()
                print(string.format("[MorePlayers] Config MaxPlayers=%d\n", MAX_PLAYERS))
                return
            end
        end
    end

    file:close()
    print("[MorePlayers] Config missing/invalid MaxPlayers; using 25\n")
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
