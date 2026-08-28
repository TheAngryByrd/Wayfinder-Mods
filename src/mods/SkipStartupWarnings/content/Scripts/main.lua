local CONFIG_PATH = "Mods/SkipStartupWarnings/config.ini"
local SKIP_EPILEPSY_WARNING = true
local SKIP_AUTO_SAVE_WARNING = true
local menu_library = nil

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
    "[SkipStartupWarnings] Config epilepsy=%s autosave=%s\n",
    setting_text(SKIP_EPILEPSY_WARNING),
    setting_text(SKIP_AUTO_SAVE_WARNING)
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
    else
        print("[SkipStartupWarnings] Epilepsy warning skip disabled\n")
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
    else
        print("[SkipStartupWarnings] Autosave warning skip disabled\n")
    end
end)

print("[SkipStartupWarnings] Mod loaded\n")
