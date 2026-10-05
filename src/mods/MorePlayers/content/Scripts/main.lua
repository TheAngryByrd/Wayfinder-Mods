local MAX_PLAYERS = 25
local CONFIG_PATH = "Mods/MorePlayers/config.ini"
local PARTY_UI_DIAGNOSTICS = false

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
    context.MaxPartySize = MAX_PLAYERS
    print(string.format(
        "[MorePlayers] %s limits: players=%d party=%d\n",
        label,
        context.MaxPlayers,
        context.MaxPartySize
    ))
end

local function update_social_settings(context)
    context.DefaultMaxPartySize = MAX_PLAYERS
    print(string.format(
        "[MorePlayers] Social default party size: %d\n",
        context.DefaultMaxPartySize
    ))
end

local function update_game_user_settings(context, phase)
    local previous = context.MaxGroupSize
    context.MaxGroupSize = MAX_PLAYERS
    if previous ~= context.MaxGroupSize then
        print(string.format(
            "[MorePlayers] Online party maximum phase=%s group_size=%s->%s\n",
            phase,
            tostring(previous),
            tostring(context.MaxGroupSize)
        ))
    end
end

local function update_all_game_user_settings(phase)
    local settings_objects = FindAllOf("WFGameUserSettings") or {}
    for _, settings in ipairs(settings_objects) do
        local ok, update_error = pcall(update_game_user_settings, settings, phase)
        if not ok then
            print(string.format(
                "[MorePlayers] Unable to update online party maximum phase=%s error=%s\n",
                phase,
                tostring(update_error)
            ))
        end
    end
end

local function update_lobby_beacon_state(context, phase)
    local previous = context.MaxPlayers
    context.MaxPlayers = MAX_PLAYERS
    print(string.format(
        "[MorePlayers] Lobby beacon limit phase=%s players=%s->%d\n",
        phase,
        tostring(previous),
        context.MaxPlayers
    ))
end

local function update_party_beacon_state(context, phase)
    local previous_reservations = context.MaxReservations
    local previous_team_size = context.NumPlayersPerTeam
    context.MaxReservations = MAX_PLAYERS
    if previous_team_size and previous_team_size > 0 and previous_team_size < MAX_PLAYERS then
        context.NumPlayersPerTeam = MAX_PLAYERS
    end
    print(string.format(
        "[MorePlayers] Party beacon limits phase=%s reservations=%s->%d team_size=%s->%s consumed=%s\n",
        phase,
        tostring(previous_reservations),
        context.MaxReservations,
        tostring(previous_team_size),
        tostring(context.NumPlayersPerTeam),
        tostring(context.NumConsumedReservations)
    ))
end

local function schedule_beacon_recheck(context, label, updater)
    ExecuteWithDelay(1000, function()
        ExecuteInGameThread(function()
            local valid_ok, valid = pcall(function()
                return context:IsValid()
            end)
            if not valid_ok or not valid then
                print(string.format("[MorePlayers] %s beacon recheck skipped: object unavailable\n", label))
                return
            end

            local update_ok, update_error = pcall(updater, context, "recheck")
            if not update_ok then
                print(string.format(
                    "[MorePlayers] Unable to update %s beacon during recheck: %s\n",
                    label,
                    tostring(update_error)
                ))
            end
        end)
    end)
end

local function try_update_default_social_settings()
    local ok, context = pcall(
        StaticFindObject,
        "/Script/Party.Default__SocialSettings"
    )
    if ok and context and context:IsValid() then
        local update_ok, update_error = pcall(update_social_settings, context)
        if not update_ok then
            print(string.format(
                "[MorePlayers] Unable to update default SocialSettings: %s\n",
                tostring(update_error)
            ))
        end
    else
        print("[MorePlayers] Default SocialSettings object not found\n")
    end
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

NotifyOnNewObject("/Script/Party.SocialSettings", function(context)
    update_social_settings(context)
end)

NotifyOnNewObject("/Script/Wayfinder.WFGameUserSettings", function(context)
    update_game_user_settings(context, "created")
end)

NotifyOnNewObject("/Script/Lobby.LobbyBeaconState", function(context)
    update_lobby_beacon_state(context, "created")
    schedule_beacon_recheck(context, "lobby", update_lobby_beacon_state)
end)

NotifyOnNewObject("/Script/OnlineSubsystemUtils.PartyBeaconState", function(context)
    update_party_beacon_state(context, "created")
    schedule_beacon_recheck(context, "party", update_party_beacon_state)
end)

try_update_default_social_settings()
update_all_game_user_settings("startup")

local JOIN_DIAGNOSTIC_SEQUENCE = 0

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

local function diagnostic_value(parameter)
    local value = unwrap_parameter(parameter)
    if value == nil then
        return "<nil>"
    end

    local value_type = type(value)
    if value_type == "string" or value_type == "number" or value_type == "boolean" then
        return tostring(value)
    end

    local text_ok, text = pcall(function()
        return value:ToString()
    end)
    if text_ok and text then
        return tostring(text)
    end

    local name_ok, name = pcall(function()
        return value:GetFullName()
    end)
    if name_ok and name then
        return tostring(name)
    end

    return tostring(value)
end

local function log_join_event(event, fields)
    JOIN_DIAGNOSTIC_SEQUENCE = JOIN_DIAGNOSTIC_SEQUENCE + 1
    local message = string.format(
        "[MorePlayers] Join diagnostic sequence=%d event=%s",
        JOIN_DIAGNOSTIC_SEQUENCE,
        event
    )
    for _, field in ipairs(fields or {}) do
        message = message .. string.format(" %s=%s", field[1], diagnostic_value(field[2]))
    end
    print(message .. "\n")
end

local function register_join_hook(path, event, callback)
    local ok, hook_error = pcall(function()
        RegisterHook(path, callback)
    end)
    if ok then
        print(string.format("[MorePlayers] Join diagnostic hook ready: %s\n", event))
    else
        print(string.format(
            "[MorePlayers] Join diagnostic hook unavailable: %s error=%s\n",
            event,
            tostring(hook_error)
        ))
    end
end

register_join_hook(
    "/Script/Wayfinder.WFGameState:UpdateSessionSettingsHelper",
    "session-settings-publication",
    function(context)
        update_all_game_user_settings("session-publication")
        log_join_event("session-settings-publication", {
            {"game_state", context},
            {"max_group_size", MAX_PLAYERS},
        })
    end
)

register_join_hook(
    "/Script/Wayfinder.WFRichPresenceSubsystem:OnPartyCreatedOrJoined",
    "party-created-or-joined-publication",
    function(context, session_name)
        update_all_game_user_settings("party-created-or-joined")
        log_join_event("party-created-or-joined-publication", {
            {"subsystem", context},
            {"session", session_name},
            {"max_group_size", MAX_PLAYERS},
        })
    end
)

register_join_hook(
    "/Script/Wayfinder.WFRichPresenceSubsystem:OnPartyUpdated",
    "party-update-publication",
    function(context, session_name)
        update_all_game_user_settings("party-update")
        log_join_event("party-update-publication", {
            {"subsystem", context},
            {"session", session_name},
            {"max_group_size", MAX_PLAYERS},
        })
    end
)

register_join_hook(
    "/Script/Engine.GameModeBase:K2_PostLogin",
    "post-login",
    function(context, new_player)
        log_join_event("post-login", {
            {"game_mode", context},
            {"player", new_player},
        })
    end
)

register_join_hook(
    "/Script/Engine.GameModeBase:K2_OnLogout",
    "logout",
    function(context, exiting_controller)
        log_join_event("logout", {
            {"game_mode", context},
            {"player", exiting_controller},
        })
    end
)

register_join_hook(
    "/Script/Engine.PlayerController:ClientWasKicked",
    "client-kicked",
    function(context, reason)
        log_join_event("client-kicked", {
            {"player", context},
            {"reason", reason},
        })
    end
)

register_join_hook(
    "/Script/Lobby.LobbyBeaconClient:ClientWasKicked",
    "lobby-beacon-client-kicked",
    function(context, reason)
        log_join_event("lobby-beacon-client-kicked", {
            {"beacon", context},
            {"reason", reason},
        })
    end
)

register_join_hook(
    "/Script/Lobby.LobbyBeaconClient:ServerLoginPlayer",
    "lobby-beacon-login",
    function(context, session_id)
        log_join_event("lobby-beacon-login", {
            {"beacon", context},
            {"session", session_id},
        })
    end
)

register_join_hook(
    "/Script/Lobby.LobbyBeaconClient:ClientLoginComplete",
    "lobby-beacon-login-complete",
    function(context, unique_id, was_successful)
        log_join_event("lobby-beacon-login-complete", {
            {"beacon", context},
            {"success", was_successful},
        })
    end
)

register_join_hook(
    "/Script/Lobby.LobbyBeaconClient:ClientSetInviteFlags",
    "joinability-settings",
    function(context, settings_parameter)
        local settings = unwrap_parameter(settings_parameter)
        local previous_max_players = "<unavailable>"
        local previous_max_party_size = "<unavailable>"
        local previous_allow_invites = "<unavailable>"
        local previous_join_presence = "<unavailable>"
        local settings_ok, settings_error = pcall(function()
            previous_max_players = settings.MaxPlayers
            previous_max_party_size = settings.MaxPartySize
            previous_allow_invites = settings.bAllowInvites
            previous_join_presence = settings.bJoinViaPresence
            settings.MaxPlayers = MAX_PLAYERS
            settings.MaxPartySize = MAX_PLAYERS
            settings.bAllowInvites = true
            settings.bJoinViaPresence = true
        end)
        if not settings_ok then
            log_join_event("joinability-update-failed", {
                {"beacon", context},
                {"error", tostring(settings_error)},
            })
            return
        end
        log_join_event("joinability-settings", {
            {"beacon", context},
            {"max_players", tostring(previous_max_players) .. "->" .. tostring(settings.MaxPlayers)},
            {"max_party_size", tostring(previous_max_party_size) .. "->" .. tostring(settings.MaxPartySize)},
            {"allow_invites", tostring(previous_allow_invites) .. "->" .. tostring(settings.bAllowInvites)},
            {"join_presence", tostring(previous_join_presence) .. "->" .. tostring(settings.bJoinViaPresence)},
        })
    end
)

register_join_hook(
    "/Script/OnlineSubsystemUtils.PartyBeaconClient:ClientReservationResponse",
    "party-reservation-response",
    function(context, reservation_response)
        log_join_event("party-reservation-response", {
            {"beacon", context},
            {"result", reservation_response},
        })
    end
)

register_join_hook(
    "/Script/OnlineSubsystemUtils.PartyBeaconClient:ClientSendReservationFull",
    "party-reservation-full",
    function(context)
        log_join_event("party-reservation-full", {
            {"beacon", context},
        })
    end
)

register_join_hook(
    "/Script/Engine.GameInstance:HandleNetworkError",
    "network-error",
    function(context, failure_type, is_server)
        log_join_event("network-error", {
            {"game_instance", context},
            {"failure_type", failure_type},
            {"is_server", is_server},
        })
    end
)

register_join_hook(
    "/Script/Engine.GameInstance:HandleTravelError",
    "travel-error",
    function(context, failure_type)
        log_join_event("travel-error", {
            {"game_instance", context},
            {"failure_type", failure_type},
        })
    end
)

register_join_hook(
    "/Script/Wayfinder.WFPlayerController:HardcoreClientWasKicked",
    "hardcore-client-kicked",
    function(context, reason)
        log_join_event("hardcore-client-kicked", {
            {"player", context},
            {"reason", reason},
        })
    end
)

register_join_hook(
    "/Script/Wayfinder.WFPlayerController:SERVER_AntiCheatRegisterPlayer",
    "anti-cheat-register",
    function(context)
        log_join_event("anti-cheat-register", {
            {"player", context},
        })
    end
)

register_join_hook(
    "/Script/Wayfinder.WFPlayerController:SERVER_ClientLevelLoadingComplete",
    "client-loading-complete",
    function(context)
        log_join_event("client-loading-complete", {
            {"player", context},
        })
    end
)

register_join_hook(
    "/Script/Wayfinder.WFPlayerController:OnPlayerCountChanged",
    "player-count-changed",
    function(context, new_player_count)
        log_join_event("player-count-changed", {
            {"player", context},
            {"count", new_player_count},
        })
    end
)

register_join_hook(
    "/Script/Wayfinder.PartyComponent:CLIENT_RefreshParty",
    "party-refresh",
    function(context)
        local party = unwrap_parameter(context)
        local count = "<unavailable>"
        local count_ok, current_count = pcall(function()
            return party:GetPlayerCount()
        end)
        if count_ok then
            count = current_count
        end
        log_join_event("party-refresh", {
            {"party", context},
            {"count", count},
        })
    end
)

-- PauseMenuPartyWidget_C "Update Component Visibility" collapses the
-- +Party Member and Code controls when Player Array Size is 3 or more. The 3 is
-- a constant in the Blueprint, so the session limits do not change it. UE4SS
-- runs Blueprint hooks after the function body, so this hook shows both
-- controls again below MAX_PLAYERS. PartySettingsBtn is shown exactly when the
-- other Blueprint conditions are true: party settings visible and host.
local PARTY_WIDGET_CLASS = "/Game/UI/UI_WF_Blueprints/UI_WF_UIPages/Coop/PauseMenuPartyWidget.PauseMenuPartyWidget_C"
local BLUEPRINT_PARTY_LIMIT = 3
-- ESlateVisibility::SelfHitTestInvisible, the value the Blueprint uses for a shown control.
local SLATE_SHOWN = 4
local party_invite_controls_hook_called = false

local function show_party_invite_controls(widget)
    if widget.PartySettingsBtn.Visibility ~= SLATE_SHOWN then
        return "party-settings-hidden"
    end
    widget.UI_AddPlayerWidget:SetVisibility(SLATE_SHOWN)
    widget.Button_InviteCodePopup:SetVisibility(SLATE_SHOWN)
    return "shown"
end

local function restore_party_invite_controls(context, player_array_size, is_player_host)
    local size = unwrap_parameter(player_array_size)
    local host = unwrap_parameter(is_player_host)
    -- The first call proves the hook, its parameter types, and the restore path
    -- without a 3-player session. Below 3 players the Blueprint already shows
    -- both controls for the host, so the probe changes nothing on screen.
    if not party_invite_controls_hook_called then
        party_invite_controls_hook_called = true
        local probe = "skipped"
        if host == true and type(size) == "number" and size < BLUEPRINT_PARTY_LIMIT then
            local probe_ok, probe_result = pcall(show_party_invite_controls, unwrap_parameter(context))
            probe = probe_ok and probe_result or ("error " .. tostring(probe_result))
        end
        print(string.format(
            "[MorePlayers] Party invite controls first call players=%s (%s) host=%s (%s) probe=%s\n",
            tostring(size),
            type(size),
            tostring(host),
            type(host),
            probe
        ))
    end
    if host ~= true or type(size) ~= "number" or size < BLUEPRINT_PARTY_LIMIT or size >= MAX_PLAYERS then
        return
    end

    local ok, result = pcall(show_party_invite_controls, unwrap_parameter(context))
    print(string.format(
        "[MorePlayers] Party invite controls players=%d limit=%d result=%s\n",
        size,
        MAX_PLAYERS,
        ok and result or ("error " .. tostring(result))
    ))
end

ExecuteInGameThread(function()
    if LoadAsset then
        local load_ok, load_error = pcall(LoadAsset, PARTY_WIDGET_CLASS)
        if not load_ok then
            print(string.format(
                "[MorePlayers] Unable to load the party widget asset: %s\n",
                tostring(load_error)
            ))
        end
    end

    local hook_ok, hook_error = pcall(function()
        RegisterHook(PARTY_WIDGET_CLASS .. ":Update Component Visibility", restore_party_invite_controls)
    end)
    if hook_ok then
        print("[MorePlayers] Party invite controls hook ready\n")
    else
        print(string.format(
            "[MorePlayers] Party invite controls hook unavailable: %s\n",
            tostring(hook_error)
        ))
    end
end)

if PARTY_UI_DIAGNOSTICS then
    local hook_ok, hook_error = pcall(function()
        RegisterHook("/Script/Wayfinder.PartyComponent:CLIENT_RefreshParty", function()
            ExecuteWithDelay(1000, function()
                dump_party_ui("CLIENT_RefreshParty")
            end)
        end)
    end)

    if not hook_ok then
        print(string.format(
            "[MorePlayers] Party UI diagnostic hook unavailable: %s\n",
            tostring(hook_error)
        ))
    end

    RegisterKeyBind(Key.F9, function()
        dump_party_ui("F9")
    end)

    print("[MorePlayers] Party UI diagnostics enabled; press F9 for a snapshot\n")
end
