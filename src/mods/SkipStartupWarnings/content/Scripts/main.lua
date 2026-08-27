local CONFIG_PATH = "Mods/SkipStartupWarnings/config.ini"
local SKIP_EPILEPSY_WARNING = true
local SKIP_AUTO_SAVE_WARNING = true
local AUTO_LOAD_PROFILE = 1
local AUTO_LOAD_RETRY_LIMIT = 30
local AUTO_LOAD_RETRY_DELAY = 100
local menu_library = nil
local auto_load_scheduled = false

local function setting_text(value)
    return value and "enabled" or "disabled"
end

local function load_config()
    if not io or not io.open then
        print("[SkipStartupWarnings] Lua file I/O unavailable; using defaults\n")
        return
    end

    local file = io.open(CONFIG_PATH, "r")
    if not file then
        print(string.format(
            "[SkipStartupWarnings] Config not found at %s; using defaults\n",
            CONFIG_PATH
        ))
        return
    end

    for line in file:lines() do
        local epilepsy = line:match("^%s*SkipEpilepsyWarning%s*=%s*([01])%s*$")
        if epilepsy then
            SKIP_EPILEPSY_WARNING = epilepsy == "1"
        end

        local autosave = line:match("^%s*SkipAutoSaveWarning%s*=%s*([01])%s*$")
        if autosave then
            SKIP_AUTO_SAVE_WARNING = autosave == "1"
        end

        local auto_load_profile = line:match("^%s*AutoLoadProfile%s*=%s*(%d+)%s*$")
        if auto_load_profile then
            AUTO_LOAD_PROFILE = tonumber(auto_load_profile) or AUTO_LOAD_PROFILE
        end
    end

    file:close()
end

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

local function is_valid(object)
    if object == nil then
        return false
    end

    local ok, valid = pcall(function()
        return object:IsValid()
    end)
    return ok and valid
end

local function read_member(object, member)
    if object == nil then
        return nil
    end

    local ok, value = pcall(function()
        return object[member]
    end)
    if not ok then
        return nil
    end
    return unwrap_parameter(value)
end

local function to_boolean(value)
    value = unwrap_parameter(value)
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "number" then
        return value ~= 0
    end
    if type(value) == "string" then
        value = value:lower()
        return value == "1" or value == "true"
    end
    return false
end

local function selected_profile_matches(page, target_index)
    local index_ok, selected_index = pcall(function()
        return page:GetSelectedProfileIndex()
    end)
    local data_ok, has_data = pcall(function()
        return page:GetSelectedProfileHasData()
    end)
    if not index_ok or not data_ok then
        return false
    end

    selected_index = tonumber(unwrap_parameter(selected_index))
    return selected_index == target_index and to_boolean(has_data)
end

local function request_profile_load(page, profile_number)
    local load_ok, load_error = pcall(function()
        page:CreateOrLoadProfile()
    end)
    if not load_ok then
        print(string.format(
            "[SkipStartupWarnings] Unable to load profile %d: %s\n",
            profile_number,
            tostring(load_error)
        ))
        return
    end

    print(string.format(
        "[SkipStartupWarnings] Load requested: profile %d\n",
        profile_number
    ))
end

local function finish_profile_selection(page, target_index, attempt)
    if not is_valid(page) then
        print(string.format(
            "[SkipStartupWarnings] Profile action accepted: profile %d\n",
            AUTO_LOAD_PROFILE
        ))
        return
    end

    if selected_profile_matches(page, target_index) then
        request_profile_load(page, AUTO_LOAD_PROFILE)
        return
    end

    if attempt >= 10 then
        print(string.format(
            "[SkipStartupWarnings] Profile %d was not selected; leaving the profile selector open\n",
            AUTO_LOAD_PROFILE
        ))
        return
    end

    ExecuteWithDelay(AUTO_LOAD_RETRY_DELAY, function()
        ExecuteInGameThread(function()
            finish_profile_selection(page, target_index, attempt + 1)
        end)
    end)
end

local function find_profile_widget(target_index)
    if not FindAllOf then
        return nil, false, false
    end

    local find_ok, widgets = pcall(FindAllOf, "WFSaveProfileWidget")
    if not find_ok or not widgets then
        return nil, false, false
    end

    for _, widget in ipairs(widgets) do
        if is_valid(widget) then
            local profile_data = read_member(widget, "ProfileData")
            local profile_index = tonumber(read_member(profile_data, "ProfileIndex"))
            if profile_index == target_index then
                return widget,
                    to_boolean(read_member(profile_data, "bHasData")),
                    to_boolean(read_member(profile_data, "bLaodFailed"))
            end
        end
    end
    return nil, false, false
end

local function try_auto_load_profile(page, target_index, attempt)
    if not is_valid(page) then
        return
    end

    local widget, has_data, load_failed = find_profile_widget(target_index)
    if not widget then
        if attempt < AUTO_LOAD_RETRY_LIMIT then
            ExecuteWithDelay(AUTO_LOAD_RETRY_DELAY, function()
                ExecuteInGameThread(function()
                    try_auto_load_profile(page, target_index, attempt + 1)
                end)
            end)
            return
        end

        print(string.format(
            "[SkipStartupWarnings] Profile %d was not found; leaving the profile selector open\n",
            AUTO_LOAD_PROFILE
        ))
        return
    end

    if load_failed then
        print(string.format(
            "[SkipStartupWarnings] Profile %d could not be read; leaving the profile selector open\n",
            AUTO_LOAD_PROFILE
        ))
        return
    end

    if not has_data then
        if attempt < AUTO_LOAD_RETRY_LIMIT then
            ExecuteWithDelay(AUTO_LOAD_RETRY_DELAY, function()
                ExecuteInGameThread(function()
                    try_auto_load_profile(page, target_index, attempt + 1)
                end)
            end)
            return
        end

        print(string.format(
            "[SkipStartupWarnings] Profile %d did not become ready; leaving the profile selector open\n",
            AUTO_LOAD_PROFILE
        ))
        return
    end

    if selected_profile_matches(page, target_index) then
        request_profile_load(page, AUTO_LOAD_PROFILE)
        return
    end

    local click_ok, click_error = pcall(function()
        widget:OnBaseButtonClicked()
    end)
    if not click_ok then
        print(string.format(
            "[SkipStartupWarnings] Unable to select profile %d: %s\n",
            AUTO_LOAD_PROFILE,
            tostring(click_error)
        ))
        return
    end

    ExecuteWithDelay(1, function()
        ExecuteInGameThread(function()
            finish_profile_selection(page, target_index, 1)
        end)
    end)
end

local function register_profile_auto_load()
    local function_path = "/Script/Wayfinder.WFProfileSelectPage:InternalProfileInitialized"
    local ok, hook_error = pcall(function()
        RegisterHook(function_path, function(context_parameter, profile_parameter)
            if auto_load_scheduled then
                return
            end

            local target_index = AUTO_LOAD_PROFILE - 1
            local profile_data = unwrap_parameter(profile_parameter)
            local profile_index = tonumber(read_member(profile_data, "ProfileIndex"))
            if profile_index ~= target_index then
                return
            end

            local page = unwrap_parameter(context_parameter)
            if not is_valid(page) then
                return
            end

            auto_load_scheduled = true
            if to_boolean(read_member(profile_data, "bLaodFailed")) then
                print(string.format(
                    "[SkipStartupWarnings] Profile %d could not be read; leaving the profile selector open\n",
                    AUTO_LOAD_PROFILE
                ))
                return
            end
            if not to_boolean(read_member(profile_data, "bHasData")) then
                print(string.format(
                    "[SkipStartupWarnings] Profile %d is empty; leaving the profile selector open\n",
                    AUTO_LOAD_PROFILE
                ))
                return
            end

            ExecuteWithDelay(1, function()
                ExecuteInGameThread(function()
                    try_auto_load_profile(page, target_index, 1)
                end)
            end)
        end)
    end)
    if ok then
        print(string.format(
            "[SkipStartupWarnings] Profile auto-load ready: profile %d\n",
            AUTO_LOAD_PROFILE
        ))
    else
        print(string.format(
            "[SkipStartupWarnings] Profile auto-load unavailable: %s\n",
            tostring(hook_error)
        ))
    end
end

local function get_menu_library()
    if is_valid(menu_library) then
        return menu_library
    end

    local ok, library = pcall(
        StaticFindObject,
        "/Script/AirshipUI.Default__AirshipMenuBlueprintFunctionLibrary"
    )
    if ok and is_valid(library) then
        menu_library = library
        return menu_library
    end
    return nil
end

local function skip_warning(context_parameter, label)
    local page = unwrap_parameter(context_parameter)
    ExecuteWithDelay(1, function()
        ExecuteInGameThread(function()
            if not is_valid(page) then
                print(string.format(
                    "[SkipStartupWarnings] Skip canceled because the %s page is unavailable\n",
                    label
                ))
                return
            end

            local library = get_menu_library()
            if not library then
                print(string.format(
                    "[SkipStartupWarnings] Unable to skip %s; the Airship menu library is unavailable\n",
                    label
                ))
                return
            end

            local transition_ok, transition_error = pcall(function()
                page:FinishTransitionAnimation()
            end)
            if not transition_ok then
                print(string.format(
                    "[SkipStartupWarnings] Unable to finish the %s transition: %s\n",
                    label,
                    tostring(transition_error)
                ))
                return
            end

            local removal_ok, removed = pcall(function()
                return library:RemoveFromAirshipMenu(page, false)
            end)
            if not removal_ok then
                print(string.format(
                    "[SkipStartupWarnings] Unable to remove the %s page: %s\n",
                    label,
                    tostring(removed)
                ))
                return
            end
            if not removed then
                print(string.format(
                    "[SkipStartupWarnings] Wayfinder did not remove the %s page\n",
                    label
                ))
                return
            end

            print(string.format("[SkipStartupWarnings] Skipped: %s\n", label))
        end)
    end)
end

local function register_warning(function_path, label)
    local ok, hook_error = pcall(function()
        RegisterHook(function_path, function(context_parameter)
            skip_warning(context_parameter, label)
        end)
    end)
    if ok then
        print(string.format("[SkipStartupWarnings] Hook ready: %s\n", label))
    else
        print(string.format(
            "[SkipStartupWarnings] Hook unavailable: %s error=%s\n",
            label,
            tostring(hook_error)
        ))
    end
end

local function load_warning_asset(asset_path, label)
    if not LoadAsset then
        return
    end

    local ok, load_error = pcall(LoadAsset, asset_path)
    if not ok then
        print(string.format(
            "[SkipStartupWarnings] Unable to load the %s warning asset: %s\n",
            label,
            tostring(load_error)
        ))
    end
end

load_config()

print(string.format(
    "[SkipStartupWarnings] Config epilepsy=%s autosave=%s profile=%d\n",
    setting_text(SKIP_EPILEPSY_WARNING),
    setting_text(SKIP_AUTO_SAVE_WARNING),
    AUTO_LOAD_PROFILE
))

ExecuteInGameThread(function()
    if SKIP_EPILEPSY_WARNING then
        load_warning_asset(
            "/Game/UI/UI_WF_Blueprints/AutoSave/UI_EpilepsyWarningPage.UI_EpilepsyWarningPage_C",
            "epilepsy"
        )
        register_warning(
            "/Game/UI/UI_WF_Blueprints/AutoSave/UI_EpilepsyWarningPage.UI_EpilepsyWarningPage_C:Construct",
            "epilepsy"
        )
    end

    if SKIP_AUTO_SAVE_WARNING then
        load_warning_asset(
            "/Game/UI/UI_WF_Blueprints/AutoSave/UI_AutoSaveWarningPage.UI_AutoSaveWarningPage_C",
            "autosave"
        )
        register_warning(
            "/Game/UI/UI_WF_Blueprints/AutoSave/UI_AutoSaveWarningPage.UI_AutoSaveWarningPage_C:Construct",
            "autosave"
        )
    end

    if AUTO_LOAD_PROFILE > 0 then
        register_profile_auto_load()
    else
        print("[SkipStartupWarnings] Profile auto-load disabled\n")
    end
end)

print("[SkipStartupWarnings] Mod loaded\n")
