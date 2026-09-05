local UEHelpers = require("UEHelpers")

local LoadoutUI = {}

local PAGE_CLASS_PATH = "/Game/Mods/Loadouts/UI/WBP_LoadoutsPage.WBP_LoadoutsPage_C"
local AIRSHIP_PAGE_CLASS_PATH = "/Script/AirshipUI.AirshipMenuPage"
local AIRSHIP_MENU_LIBRARY_PATH = "/Script/AirshipUI.Default__AirshipMenuBlueprintFunctionLibrary"
local CHARACTER_PAGE_CLASS = "UI_Page_CharacterLoadout_v2_C"
local CHARACTER_PAGE_CLASS_PATH =
    "/Game/UI/UI_WF_Blueprints/UI_WF_UIPages/" ..
    "UI_Page_CharacterLoadout_v2.UI_Page_CharacterLoadout_v2_C"
local CHARACTER_PAGE_CONSTRUCT_PATH = CHARACTER_PAGE_CLASS_PATH .. ":Construct"
local WAYFINDER_BUTTON_CLASS_PATH =
    "/Game/UI/UI_WF_Blueprints/UI_WF_UIPages/Armory/NewStandalone/" ..
    "UI_CharacterMenu_AccessButton.UI_CharacterMenu_AccessButton_C"
local WAYFINDER_BUTTON_PRESS_PATH = WAYFINDER_BUTTON_CLASS_PATH ..
    ":BndEvt__UI_CharacterMenu_AccessButton_AirshipButton_159_" ..
    "K2Node_ComponentBoundEvent_1_OnButtonPressedEvent__DelegateSignature"

local api = nil
local class_cache = {}
local button_actions = {}
local button_objects = {}
local button_event_owners = {}
local button_event_targets = {}
local button_base_colors = {}
local button_focus_colors = {}
local button_focused = {}
local button_visual_owners = {}
local button_labels = {}
local button_page_scoped = {}
local launcher_by_page = {}
local launcher_pending = {}
local page_action_addresses = {}
local row_action_addresses = {}
local confirmation_action_addresses = {}
local current_page = nil
local current_character_page = nil
local current_character_page_enabled = nil
local current_controls = nil
local current_menu_library = nil
local current_menu_manager = nil
local current_menu_managed = false
local focused_button_address = nil
local action_scheduled = false
local started = false
local lifecycle_watch_started = false
local character_page_hook_registered = false
local button_press_hook_registered = false
local name_keys_registered = false
local asset_registry_helpers = nil
local wayfinder_button_class = nil
local profile_name_buffer = ""

local PROFILE_NAME_LIMIT = 64
local SLATE_VISIBLE = 0
local SLATE_COLLAPSED = 1
local SLATE_HIT_TEST_INVISIBLE = 3
local SLATE_SELF_HIT_TEST_INVISIBLE = 4
local BUTTON_INPUT_DOWN_AND_UP = 0
local BUTTON_PRESS_DOWN_AND_UP = 0

local function log(message)
    api.log("UI: " .. message)
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

local function to_text(value)
    if value == nil then
        return ""
    end
    if type(value) == "string" then
        return value
    end
    local ok, result = pcall(function()
        return value:ToString()
    end)
    if ok then
        return result
    end
    return tostring(value)
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

local function object_address(object)
    if not is_valid(object) then
        return nil
    end
    local ok, address = pcall(function()
        return object:GetAddress()
    end)
    if ok then
        return tostring(address)
    end
    return nil
end

local function find_class(path)
    local cached = class_cache[path]
    if is_valid(cached) then
        return cached
    end
    local ok, result = pcall(StaticFindObject, path)
    if ok and is_valid(result) then
        class_cache[path] = result
        return result
    end
    return nil
end

local function load_class(path)
    local class = find_class(path)
    if class then
        return class
    end
    if LoadAsset then
        local ok, loaded = pcall(LoadAsset, path)
        if ok and is_valid(loaded) then
            class_cache[path] = loaded
            return loaded
        end
    end
    return find_class(path)
end

local function load_wayfinder_button_class()
    if not is_valid(wayfinder_button_class) then
        wayfinder_button_class = load_class(WAYFINDER_BUTTON_CLASS_PATH)
    end
    return is_valid(wayfinder_button_class)
end

local function construct(path, outer)
    local class = find_class(path)
    if not class or not is_valid(outer) then
        return nil
    end
    local ok, object = pcall(StaticConstructObject, class, outer, 0, 0, 0, nil, false, false, nil)
    if ok and is_valid(object) then
        return object
    end
    return nil
end

local function run_ui_step(label, callback)
    local ok, result = pcall(callback)
    if not ok then
        log(label .. " failed: " .. tostring(result))
        return false, nil
    end
    return true, result
end

local function vector(x, y)
    return { X = x, Y = y }
end

local function margin(left, top, right, bottom)
    return { Left = left, Top = top, Right = right, Bottom = bottom }
end

local function color(red, green, blue, alpha)
    return { R = red, G = green, B = blue, A = alpha }
end

local function set_font_size(text_widget, size)
    pcall(function()
        local font = text_widget.Font
        font.Size = size
        text_widget:SetFont(font)
    end)
end

local function make_text(tree, value, size)
    local widget = construct("/Script/AirshipUI.AirshipTextBlock", tree)
        or construct("/Script/UMG.TextBlock", tree)
    if not widget then
        return nil
    end
    pcall(function()
        widget:SetText(FText(value))
        widget:SetAutoWrapText(true)
        widget.bScalingEnabled = true
    end)
    set_font_size(widget, size or 18)
    return widget
end

local function set_status(message, is_error)
    if not current_controls or not is_valid(current_controls.status) then
        return
    end
    pcall(function()
        current_controls.status:SetText(FText(message or ""))
        current_controls.status:SetColorAndOpacity({
            SpecifiedColor = is_error and color(1.0, 0.35, 0.3, 1.0) or color(0.65, 0.85, 1.0, 1.0),
            ColorUseRule = 0
        })
    end)
end

local function update_name_display()
    if not current_controls or not is_valid(current_controls.name_display) then
        return
    end
    local value = profile_name_buffer
    if value == "" then
        value = "TYPE A NAME OR USE AN AUTOMATIC NAME"
    else
        value = value .. "_"
    end
    pcall(function()
        current_controls.name_display:SetText(FText(value))
    end)
end

local function set_name_buffer(value)
    profile_name_buffer = tostring(value or ""):sub(1, PROFILE_NAME_LIMIT)
    update_name_display()
end

local function page_accepts_name_input()
    if not is_valid(current_page) then
        return false
    end
    if not is_valid(current_menu_manager) then
        return true
    end
    local ok, top_page = pcall(function()
        return current_menu_manager:GetTopPage()
    end)
    return ok and object_address(top_page) == object_address(current_page)
end

local function append_name_character(value)
    if not page_accepts_name_input() or #profile_name_buffer >= PROFILE_NAME_LIMIT then
        return
    end
    set_name_buffer(profile_name_buffer .. value)
end

local function remove_name_character()
    if not page_accepts_name_input() or profile_name_buffer == "" then
        return
    end
    set_name_buffer(profile_name_buffer:sub(1, -2))
end

local function clear_action_addresses(addresses)
    for _, address in ipairs(addresses) do
        if focused_button_address == address then
            focused_button_address = nil
        end
        local event_owner = button_event_owners[address]
        if event_owner then
            button_event_targets[event_owner] = nil
        end
        button_actions[address] = nil
        button_objects[address] = nil
        button_event_owners[address] = nil
        button_base_colors[address] = nil
        button_focus_colors[address] = nil
        button_focused[address] = nil
        button_visual_owners[address] = nil
        button_labels[address] = nil
        button_page_scoped[address] = nil
    end
    for index = #addresses, 1, -1 do
        addresses[index] = nil
    end
end

local function run_action(action)
    if action_scheduled then
        return false
    end
    action_scheduled = true
    set_status("Operation in progress.", false)
    ExecuteWithDelay(1, function()
        ExecuteInGameThread(function()
            local ok, action_error = pcall(action)
            if not ok then
                log("Action failed: " .. tostring(action_error))
                set_status("The Loadouts action failed. Check UE4SS.log.", true)
            end
            ExecuteWithDelay(150, function()
                action_scheduled = false
            end)
        end)
    end)
    return true
end

local function activate_button(address, source)
    local action = address and button_actions[address] or nil
    if not action or not run_action(action) then
        return false
    end
    log(string.format("%s activate: %s", source, button_labels[address] or "Button"))
    return true
end

local function bind_button(button, action, addresses, base_color, focus_color, visual_owner, label, event_owner)
    local address = object_address(button)
    if not address then
        return false
    end
    local event_owner_address = nil
    if event_owner ~= nil then
        event_owner_address = object_address(event_owner)
        if not event_owner_address then
            return false
        end
    end
    button_actions[address] = action
    button_objects[address] = button
    button_base_colors[address] = base_color
    button_focus_colors[address] = focus_color
    button_focused[address] = nil
    button_visual_owners[address] = visual_owner
    button_labels[address] = label or "Button"
    button_page_scoped[address] = addresses == page_action_addresses
        or addresses == row_action_addresses
        or addresses == confirmation_action_addresses
    if event_owner_address then
        button_event_owners[address] = event_owner_address
        button_event_targets[event_owner_address] = address
    end
    addresses[#addresses + 1] = address
    return true
end

local function configure_wayfinder_button_input(button, target)
    local ok, input_error = pcall(function()
        local root = button.WidgetTree and button.WidgetTree.RootWidget or nil
        if is_valid(root) then
            root:SetVisibility(SLATE_SELF_HIT_TEST_INVISIBLE)
        end
        button:SetVisibility(SLATE_SELF_HIT_TEST_INVISIBLE)
        button:SetIsEnabled(true)
        target:SetVisibility(SLATE_VISIBLE)
        target:SetIsEnabled(true)
        target:SetFocusable(true)
        target:SetClickMethod(BUTTON_INPUT_DOWN_AND_UP)
        target:SetPressMethod(BUTTON_PRESS_DOWN_AND_UP)
        target.bTakeFocusOnHover = true
    end)
    return ok, input_error
end

local function make_wayfinder_button(label, action, addresses)
    if not load_wayfinder_button_class() then
        return nil
    end
    local context = api.context()
    if not context then
        return nil
    end
    local library = nil
    local button = nil
    local ok = pcall(function()
        library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        if is_valid(library) then
            button = library:Create(context.player_controller, wayfinder_button_class, context.player_controller)
        end
    end)
    if not ok or not is_valid(button) then
        return nil
    end
    local target = nil
    pcall(function()
        button.ButtonLabel = FText(label)
        button.buttonWidth = 180
        button.buttonHeight = 58
        button.centerText = true
        button.useArmoryLock = false
        button.IsUnlocked = true
        button.dev_PermanentLock = false
        if is_valid(button.text_buttonLabel) then
            button.text_buttonLabel:SetText(FText(label))
        end
        if is_valid(button.text_buttonlabel_message) then
            button.text_buttonlabel_message:SetText(FText(""))
        end
        if is_valid(button.text_buttonlabel_special) then
            button.text_buttonlabel_special:SetText(FText(""))
        end
        button:isFeatureLocked(false)
        button:visualSetup()
        target = button.AirshipButton_159
    end)
    if not ok or not is_valid(target) then
        return nil
    end
    local input_ok, input_error = configure_wayfinder_button_input(button, target)
    if not input_ok then
        log("Wayfinder button input setup failed: " .. tostring(input_error))
        return nil
    end
    if not bind_button(target, action, addresses, nil, nil, button, label, button) then
        return nil
    end
    return button
end

local function make_button(_, label, action, addresses)
    return make_wayfinder_button(label, action, addresses)
end

local function set_wayfinder_focus_visual(target, owner, focused)
    local focus_blue = color(0.12, 0.68, 1.0, 1.0)
    local focus_backer = color(0.04, 0.28, 0.48, 1.0)
    local focus_gradient = color(0.1, 0.52, 0.82, 1.0)
    local focus_text = {
        SpecifiedColor = color(1.0, 1.0, 1.0, 1.0),
        ColorUseRule = 0
    }
    pcall(function()
        target:SetAlwaysDrawAsFocused(focused)
    end)
    pcall(function()
        owner.Overlay_focusFrame:SetVisibility(focused and SLATE_HIT_TEST_INVISIBLE or SLATE_COLLAPSED)
    end)
    pcall(function()
        owner.RetainerBox_focus:SetVisibility(focused and SLATE_HIT_TEST_INVISIBLE or SLATE_COLLAPSED)
    end)
    pcall(function()
        owner.Overlay_focusFrame:SetRenderOpacity(focused and 1.0 or 0.0)
        owner.RetainerBox_focus:SetRenderOpacity(focused and 1.0 or 0.0)
        owner.FocusFrame_Large:SetVisibility(focused and SLATE_HIT_TEST_INVISIBLE or SLATE_COLLAPSED)
        owner.FocusFrame_Large:SetRenderOpacity(focused and 1.0 or 0.0)
        owner.focusFrameArt:SetVisibility(focused and SLATE_HIT_TEST_INVISIBLE or SLATE_COLLAPSED)
        owner.focusFrameArt:SetRenderOpacity(focused and 1.0 or 0.0)
        owner.FocusFrameLarge_Retainer:SetVisibility(focused and SLATE_HIT_TEST_INVISIBLE or SLATE_COLLAPSED)
        owner.FocusFrameLarge_Retainer:SetRenderOpacity(focused and 1.0 or 0.0)
    end)
    pcall(function()
        owner.FocusFrame_Large:SetColorAndOpacity(focus_blue)
        owner.focusFrameArt:SetColorAndOpacity(focus_blue)
    end)
    pcall(function()
        owner.text_buttonLabel:SetColorAndOpacity(
            focused and focus_text or owner.inactiveColor_mainText
        )
    end)
    pcall(function()
        owner.buttonIconArt:SetColorAndOpacity(
            focused and color(1.0, 1.0, 1.0, 1.0) or owner.inactiveColor_buttonIcon
        )
    end)
    pcall(function()
        owner.ButtonBacker:SetColorAndOpacity(
            focused and focus_backer or owner.inactiveColor_buttonBackerBase
        )
    end)
    pcall(function()
        owner.ButtonBacker_gradient:SetColorAndOpacity(
            focused and focus_gradient or owner.inactiveColor_buttonBackerGradient
        )
    end)
    pcall(function()
        local rim = focused and focus_blue or owner.inactiveColor_buttonBackerRim
        owner.ButtonOutline:SetColorAndOpacity(rim)
        owner.ButtonOutline_points:SetColorAndOpacity(rim)
    end)
end

local function run_wayfinder_focus_handler(owner, focused)
    if focused then
        pcall(function()
            owner:BndEvt__UI_CharacterMenu_AccessButton_AirshipButton_159_K2Node_ComponentBoundEvent_0_OnButtonFocusEvent__DelegateSignature(true)
        end)
    else
        pcall(function()
            owner:BndEvt__UI_CharacterMenu_AccessButton_AirshipButton_159_K2Node_ComponentBoundEvent_2_OnButtonFocusEvent__DelegateSignature(false)
        end)
    end
end

local function apply_button_focus(address, focused, source)
    local button = address and button_objects[address] or nil
    if not is_valid(button) then
        return false
    end
    button_focused[address] = focused
    local visual_owner = button_visual_owners[address]
    if is_valid(visual_owner) then
        run_wayfinder_focus_handler(visual_owner, focused)
        set_wayfinder_focus_visual(button, visual_owner, focused)
    else
        local background = focused and button_focus_colors[address] or button_base_colors[address]
        if background then
            pcall(function()
                button:SetBackgroundColor(background)
            end)
        end
    end
    if focused then
        log(string.format("Controller highlight: %s source=%s", button_labels[address] or "Button", source))
    end
    return true
end

local function handle_focus_change(widget, source)
    local next_address = object_address(widget)
    if next_address == focused_button_address then
        return
    end
    if focused_button_address then
        apply_button_focus(focused_button_address, false, source)
    end
    focused_button_address = nil
    if next_address and button_actions[next_address] then
        focused_button_address = next_address
        apply_button_focus(next_address, true, source)
    end
end

local function take_airship_focus(menu_manager, target, source)
    if not is_valid(menu_manager) or not is_valid(target) then
        return false
    end
    local call_ok, accepted = pcall(function()
        return menu_manager:TakeFocus(target, true)
    end)
    if not call_ok or accepted ~= true then
        log(string.format("Airship focus rejected: source=%s accepted=%s", source, tostring(accepted)))
        return false
    end
    pcall(function()
        target:SetFocus()
    end)
    handle_focus_change(target, source)
    return true
end

local function focus_target(widget)
    if not is_valid(widget) then
        return nil
    end
    local target = nil
    pcall(function()
        target = widget.AirshipButton_159
    end)
    if is_valid(target) then
        return target
    end
    return widget
end

local function set_ui_focus(context, widget)
    if not context or not is_valid(context.player_controller) or not is_valid(widget) then
        return false
    end
    local library = nil
    local library_ok = pcall(function()
        library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    end)
    if not library_ok or not is_valid(library) then
        return false
    end
    local input_ok = pcall(function()
        library:SetInputMode_UIOnlyEx(context.player_controller, widget, 0)
        widget:SetUserFocus(context.player_controller)
        widget:SetKeyboardFocus()
    end)
    return input_ok
end

local function get_airship_menu(context)
    if not context or not is_valid(context.player_controller) then
        return nil, nil
    end
    local library = nil
    local manager = nil
    local ok = pcall(function()
        library = StaticFindObject(AIRSHIP_MENU_LIBRARY_PATH)
        if is_valid(library) then
            manager = library:GetMenuManagerForController(context.player_controller)
        end
    end)
    if not ok or not is_valid(library) or not is_valid(manager) then
        return nil, nil
    end
    return library, manager
end

local function configure_airship_page(page)
    if not is_valid(page) then
        return false, "invalid page"
    end
    return pcall(function()
        page.bIsRootMenuPage = false
        page.bCanUserBackOut = true
        page.bAllowInputWhileNotTop = false
        page.bStealInputFromBelow = true
        page.bAutoAddBackButtonEvent = true
        page.bHidePagesBelow = true
        page.bHideCursorWhenPageOnStack = false
        page.bPreventDPadInputSuppressionForCustomEvents = false
        page.bPreventWASDInputSuppressionForCustomEvents = false
        page.bBlurUnderMenus = false
    end)
end

local function set_vertical_slot(slot, fill, padding)
    if not is_valid(slot) then
        return
    end
    pcall(function()
        slot:SetPadding(padding or margin(0, 0, 0, 0))
        slot:SetHorizontalAlignment(0)
        slot:SetVerticalAlignment(0)
        slot:SetSize({ Value = fill and 1.0 or 0.0, SizeRule = fill and 1 or 0 })
    end)
end

local function set_horizontal_slot(slot, fill, padding)
    if not is_valid(slot) then
        return
    end
    pcall(function()
        slot:SetPadding(padding or margin(0, 0, 0, 0))
        slot:SetHorizontalAlignment(0)
        slot:SetVerticalAlignment(2)
        slot:SetSize({ Value = fill and 1.0 or 0.0, SizeRule = fill and 1 or 0 })
    end)
end

local function get_pending_confirmation()
    if not api or type(api.pending_confirmation) ~= "function" then
        return nil
    end
    local ok, pending = pcall(api.pending_confirmation)
    if ok and type(pending) == "table" then
        return pending
    end
    return nil
end

local function confirmation_body(pending)
    local body = to_text(pending.body or pending.message)
    if body ~= "" then
        return body
    end
    local name = to_text(pending.profile_name or pending.name)
    if name == "" then
        name = "the selected profile"
    end
    return "Apply available parts from " .. name .. " and skip unavailable parts?"
end

local function update_confirmation_panel()
    if not current_controls then
        return nil
    end
    local pending = get_pending_confirmation()
    local visible = pending ~= nil
    pcall(function()
        current_controls.confirmation_panel:SetVisibility(visible and 0 or 1)
        current_controls.action_bar:SetIsEnabled(not visible)
        current_controls.profile_box:SetIsEnabled(not visible)
        if visible then
            current_controls.confirmation_text:SetText(FText(confirmation_body(pending)))
        end
    end)
    return pending
end

local function focus_rebuilt_action()
    ExecuteWithDelay(1, function()
        ExecuteInGameThread(function()
            if not is_valid(current_page) or not current_controls then
                return
            end
            local pending = get_pending_confirmation()
            local widget = pending and current_controls.confirm_button or current_controls.focus_button
            local target = focus_target(widget)
            if not is_valid(target) then
                return
            end
            local focused = false
            if is_valid(current_menu_manager) then
                focused = take_airship_focus(current_menu_manager, target, "Refresh")
            else
                local context = api.context()
                focused = context and set_ui_focus(context, target) or false
            end
            if focused and not is_valid(current_menu_manager) then
                handle_focus_change(target, "Refresh")
            end
        end)
    end)
end

local function operation_result(ok, message)
    set_status(message, not ok)
    if current_controls then
        LoadoutUI.refresh(true)
    end
end

local function read_name()
    return api.clean_name(profile_name_buffer)
end

local function automatic_profile_name()
    local used = {}
    for _, profile in ipairs(api.list()) do
        used[string.lower(profile.name)] = true
    end
    local index = 1
    while used[string.lower("Loadout " .. tostring(index))] do
        index = index + 1
    end
    return "Loadout " .. tostring(index)
end

local function make_profile_row(tree, profile)
    local border = construct("/Script/UMG.Border", tree)
    local row = construct("/Script/UMG.HorizontalBox", tree)
    if not border or not row then
        return nil
    end
    pcall(function()
        border:SetBrushColor(color(0.08, 0.12, 0.18, 0.96))
        border:SetPadding(margin(12, 8, 12, 8))
        border:SetContent(row)
    end)

    local detail = nil
    if profile.valid then
        detail = string.format(
            "%s\nArmor=%d | Weapons=%d | Style=%d | Echoes=%d | Talents=%d | Abilities=%d",
            profile.name,
            profile.armor,
            profile.weapons,
            profile.style,
            profile.echos,
            profile.talents,
            profile.abilities
        )
    else
        detail = string.format(
            "%s\nRECAPTURE REQUIRED | %d unverified item records",
            profile.name,
            profile.unverified_items
        )
    end
    local label = make_text(tree, detail, 17)
    if label then
        set_horizontal_slot(row:AddChildToHorizontalBox(label), true, margin(0, 0, 12, 0))
    end

    local apply = nil
    if profile.valid then
        apply = make_button(tree, "Apply", function()
            operation_result(api.apply(profile.name))
        end, row_action_addresses)
    end
    if apply then
        set_horizontal_slot(row:AddChildToHorizontalBox(apply), false, margin(4, 0, 4, 0))
    end

    local overwrite = make_button(tree, profile.valid and "Overwrite" or "Recapture", function()
        operation_result(api.save(profile.name))
    end, row_action_addresses)
    if overwrite then
        set_horizontal_slot(row:AddChildToHorizontalBox(overwrite), false, margin(4, 0, 4, 0))
    end

    local rename = make_button(tree, "Rename", function()
        local new_name = read_name()
        if new_name == "" then
            set_status("Enter the new profile name before Rename.", true)
            return
        end
        operation_result(api.rename(profile.name, new_name))
    end, row_action_addresses)
    if rename then
        set_horizontal_slot(row:AddChildToHorizontalBox(rename), false, margin(4, 0, 4, 0))
    end

    local delete = make_button(tree, "Delete", function()
        operation_result(api.delete(profile.name))
    end, row_action_addresses, color(0.45, 0.10, 0.10, 1.0))
    if delete then
        set_horizontal_slot(row:AddChildToHorizontalBox(delete), false, margin(4, 0, 0, 0))
    end
    return border
end

local function make_character_header(tree, character, count)
    local border = construct("/Script/UMG.Border", tree)
    local label = make_text(tree, string.format(
        "%s    %d %s",
        string.upper(character),
        count,
        count == 1 and "LOADOUT" or "LOADOUTS"
    ), 24)
    if not border or not label then
        return nil
    end
    pcall(function()
        border:SetBrushColor(color(0.035, 0.20, 0.30, 1.0))
        border:SetPadding(margin(16, 10, 16, 10))
        border:SetContent(label)
    end)
    return border
end

local function configure_page_navigation()
    local ordered = {}
    if get_pending_confirmation() then
        for _, address in ipairs(confirmation_action_addresses) do
            if is_valid(button_objects[address]) then
                ordered[#ordered + 1] = button_objects[address]
            end
        end
    else
        for _, address in ipairs(page_action_addresses) do
            if is_valid(button_objects[address]) then
                ordered[#ordered + 1] = button_objects[address]
            end
        end
        for _, address in ipairs(row_action_addresses) do
            if is_valid(button_objects[address]) then
                ordered[#ordered + 1] = button_objects[address]
            end
        end
    end
    local configured = 0
    for index, button in ipairs(ordered) do
        local previous = ordered[index > 1 and index - 1 or #ordered]
        local following = ordered[index < #ordered and index + 1 or 1]
        local ok = pcall(function()
            button:SetNavigationRuleExplicit(0, previous)
            button:SetNavigationRuleExplicit(2, previous)
            button:SetNavigationRuleExplicit(5, previous)
            button:SetNavigationRuleExplicit(1, following)
            button:SetNavigationRuleExplicit(3, following)
            button:SetNavigationRuleExplicit(4, following)
        end)
        if ok then
            configured = configured + 1
        end
    end
    log(string.format("Explicit controller navigation buttons=%d/%d", configured, #ordered))
    return configured == #ordered and configured > 0
end

function LoadoutUI.refresh(restore_focus)
    if not current_controls or not is_valid(current_controls.profile_box) then
        return false
    end
    local function finish_refresh()
        update_confirmation_panel()
        configure_page_navigation()
        if restore_focus then
            focus_rebuilt_action()
        end
        return true
    end
    clear_action_addresses(row_action_addresses)
    pcall(function()
        current_controls.profile_box:ClearChildren()
    end)
    local profiles = api.list()
    if #profiles == 0 then
        local empty = make_text(current_controls.tree, "No loadout profiles are saved.", 19)
        if empty then
            set_vertical_slot(current_controls.profile_box:AddChildToVerticalBox(empty), false, margin(4, 18, 4, 18))
        end
        return finish_refresh()
    end
    local groups_by_key = {}
    local groups = {}
    for _, profile in ipairs(profiles) do
        local character = profile.valid
            and (profile.character ~= "" and profile.character or "Unknown Wayfinder")
            or "Recapture required"
        local key = string.lower(character)
        local group = groups_by_key[key]
        if not group then
            group = { character = character, profiles = {} }
            groups_by_key[key] = group
            groups[#groups + 1] = group
        end
        group.profiles[#group.profiles + 1] = profile
    end
    table.sort(groups, function(left, right)
        return string.lower(left.character) < string.lower(right.character)
    end)
    for _, group in ipairs(groups) do
        table.sort(group.profiles, function(left, right)
            return string.lower(left.name) < string.lower(right.name)
        end)
        local header = make_character_header(current_controls.tree, group.character, #group.profiles)
        if header then
            set_vertical_slot(
                current_controls.profile_box:AddChildToVerticalBox(header),
                false,
                margin(0, 14, 0, 8)
            )
        end
        for _, profile in ipairs(group.profiles) do
            local row = make_profile_row(current_controls.tree, profile)
            if row then
                set_vertical_slot(
                    current_controls.profile_box:AddChildToVerticalBox(row),
                    false,
                    margin(18, 0, 0, 8)
                )
            end
        end
    end
    return finish_refresh()
end

local function build_page(page)
    local tree = nil
    pcall(function()
        tree = page.WidgetTree
    end)
    if not is_valid(tree) then
        tree = construct("/Script/UMG.WidgetTree", page)
        if not tree then
            return false, "The page widget tree could not be created."
        end
        pcall(function()
            page.WidgetTree = tree
        end)
    end

    local root = construct("/Script/UMG.CanvasPanel", tree)
    local darkener = construct("/Script/UMG.Border", tree)
    local panel = construct("/Script/UMG.Border", tree)
    local content = construct("/Script/UMG.VerticalBox", tree)
    if not root or not darkener or not panel or not content then
        return false, "The primary UMG widgets could not be created."
    end
    local root_ok = run_ui_step("Page root assignment", function()
        tree.RootWidget = root
    end)
    local root_read_ok, assigned_root = run_ui_step("Page root validation", function()
        return tree.RootWidget
    end)
    if not root_ok or not root_read_ok or not is_valid(assigned_root) then
        return false, "The page root could not be assigned."
    end
    local darkener_ok = run_ui_step("Page background setup", function()
        darkener:SetBrushColor(color(0.008, 0.015, 0.028, 1.0))
    end)
    if not darkener_ok then
        return false, "The page background could not be configured."
    end
    local darkener_slot_ok, darkener_slot = run_ui_step("Page background insertion", function()
        return root:AddChildToCanvas(darkener)
    end)
    if not darkener_slot_ok or not is_valid(darkener_slot) then
        return false, "The page background could not be inserted."
    end
    local darkener_layout_ok = run_ui_step("Page background layout", function()
        darkener_slot:SetMinimum(vector(0, 0))
        darkener_slot:SetMaximum(vector(1, 1))
        darkener_slot:SetOffsets(margin(0, 0, 0, 0))
        darkener_slot:SetZOrder(0)
    end)
    if not darkener_layout_ok then
        return false, "The page background could not be laid out."
    end
    local panel_ok = run_ui_step("Page panel setup", function()
        panel:SetBrushColor(color(0.025, 0.045, 0.075, 0.98))
        panel:SetPadding(margin(72, 48, 72, 48))
        panel:SetContent(content)
    end)
    if not panel_ok then
        return false, "The page panel could not be configured."
    end
    local panel_slot_ok, panel_slot = run_ui_step("Page panel insertion", function()
        return root:AddChildToCanvas(panel)
    end)
    if not panel_slot_ok or not is_valid(panel_slot) then
        return false, "The page panel could not be inserted."
    end
    local panel_layout_ok = run_ui_step("Page panel layout", function()
        panel_slot:SetMinimum(vector(0, 0))
        panel_slot:SetMaximum(vector(1, 1))
        panel_slot:SetAlignment(vector(0, 0))
        panel_slot:SetOffsets(margin(0, 0, 0, 0))
        panel_slot:SetZOrder(1)
    end)
    if not panel_layout_ok then
        return false, "The page panel could not be laid out."
    end

    local header = construct("/Script/UMG.HorizontalBox", tree)
    local title = make_text(tree, "LOADOUT PROFILES", 36)
    local close_button = make_button(tree, "Back", function()
        LoadoutUI.close()
    end, page_action_addresses, color(0.28, 0.10, 0.12, 1.0))
    if not header or not title or not close_button then
        return false, "The Loadouts header could not be created."
    end
    set_horizontal_slot(header:AddChildToHorizontalBox(title), true, margin(0, 0, 12, 0))
    set_horizontal_slot(header:AddChildToHorizontalBox(close_button), false, margin(4, 0, 0, 0))
    set_vertical_slot(content:AddChildToVerticalBox(header), false, margin(0, 0, 0, 14))

    local instruction = make_text(
        tree,
        "Save or apply a complete character setup. Type a profile name anywhere on this page, or use an automatic name.",
        17
    )
    if instruction then
        set_vertical_slot(content:AddChildToVerticalBox(instruction), false, margin(0, 0, 0, 14))
    end

    local name_panel = construct("/Script/UMG.Border", tree)
    local action_bar = construct("/Script/UMG.HorizontalBox", tree)
    local name_label = make_text(tree, "PROFILE NAME", 15)
    local name_display = make_text(tree, "TYPE A NAME OR USE AN AUTOMATIC NAME", 22)
    local save_button = nil
    local automatic_name_button = nil
    local clear_name_button = nil
    local refresh_button = nil
    if not name_panel or not action_bar or not name_label or not name_display then
        return false, "The Loadouts action bar could not be created."
    end
    pcall(function()
        name_panel:SetBrushColor(color(0.055, 0.095, 0.145, 1.0))
        name_panel:SetPadding(margin(18, 10, 18, 10))
        name_panel:SetContent(name_display)
    end)
    save_button = make_button(tree, "Save New", function()
        local name = read_name()
        if name == "" then
            name = automatic_profile_name()
            set_name_buffer(name)
        end
        operation_result(api.save(name))
    end, page_action_addresses)
    automatic_name_button = make_button(tree, "Automatic Name", function()
        local name = automatic_profile_name()
        set_name_buffer(name)
        set_status("Profile name set to " .. name .. ".", false)
    end, page_action_addresses)
    clear_name_button = make_button(tree, "Clear Name", function()
        set_name_buffer("")
        set_status("Profile name cleared.", false)
    end, page_action_addresses)
    refresh_button = make_button(tree, "Refresh", function()
        LoadoutUI.refresh(true)
        set_status("Profile list refreshed.", false)
    end, page_action_addresses)
    if not save_button or not automatic_name_button or not clear_name_button or not refresh_button then
        return false, "The Wayfinder action buttons could not be created."
    end
    set_vertical_slot(content:AddChildToVerticalBox(name_label), false, margin(0, 0, 0, 5))
    set_horizontal_slot(action_bar:AddChildToHorizontalBox(name_panel), true, margin(0, 0, 8, 0))
    if save_button then
        set_horizontal_slot(action_bar:AddChildToHorizontalBox(save_button), false, margin(4, 0, 4, 0))
    end
    if automatic_name_button then
        set_horizontal_slot(action_bar:AddChildToHorizontalBox(automatic_name_button), false, margin(4, 0, 4, 0))
    end
    if clear_name_button then
        set_horizontal_slot(action_bar:AddChildToHorizontalBox(clear_name_button), false, margin(4, 0, 4, 0))
    end
    if refresh_button then
        set_horizontal_slot(action_bar:AddChildToHorizontalBox(refresh_button), false, margin(4, 0, 0, 0))
    end
    set_vertical_slot(content:AddChildToVerticalBox(action_bar), false, margin(0, 0, 0, 12))

    local confirmation_panel = construct("/Script/UMG.Border", tree)
    local confirmation_content = construct("/Script/UMG.VerticalBox", tree)
    local confirmation_title = make_text(tree, "CONFIRM LOADOUT APPLICATION", 22)
    local confirmation_text = make_text(tree, "", 17)
    local confirmation_actions = construct("/Script/UMG.HorizontalBox", tree)
    local confirm_button = make_button(tree, "Confirm Apply", function()
        if type(api.confirm) ~= "function" then
            set_status("The confirmation service is unavailable.", true)
            return
        end
        operation_result(api.confirm())
    end, confirmation_action_addresses)
    local cancel_button = make_button(tree, "Cancel", function()
        if type(api.cancel) ~= "function" then
            set_status("The confirmation service is unavailable.", true)
            return
        end
        operation_result(api.cancel())
    end, confirmation_action_addresses)
    if not confirmation_panel or not confirmation_content or not confirmation_title
        or not confirmation_text or not confirmation_actions or not confirm_button or not cancel_button then
        return false, "The Loadouts confirmation panel could not be created."
    end
    pcall(function()
        confirmation_panel:SetBrushColor(color(0.18, 0.075, 0.055, 1.0))
        confirmation_panel:SetPadding(margin(18, 12, 18, 12))
        confirmation_panel:SetContent(confirmation_content)
        confirmation_panel:SetVisibility(1)
    end)
    set_vertical_slot(confirmation_content:AddChildToVerticalBox(confirmation_title), false, margin(0, 0, 0, 6))
    set_vertical_slot(confirmation_content:AddChildToVerticalBox(confirmation_text), false, margin(0, 0, 0, 10))
    set_horizontal_slot(confirmation_actions:AddChildToHorizontalBox(confirm_button), false, margin(0, 0, 6, 0))
    set_horizontal_slot(confirmation_actions:AddChildToHorizontalBox(cancel_button), false, margin(6, 0, 0, 0))
    set_vertical_slot(confirmation_content:AddChildToVerticalBox(confirmation_actions), false, margin(0, 0, 0, 0))
    set_vertical_slot(content:AddChildToVerticalBox(confirmation_panel), false, margin(0, 0, 0, 12))

    local scroll = construct("/Script/UMG.ScrollBox", tree)
    local profile_box = construct("/Script/UMG.VerticalBox", tree)
    if not scroll or not profile_box then
        return false, "The Loadouts profile list could not be created."
    end
    pcall(function()
        scroll:SetAnimateWheelScrolling(true)
        scroll:SetAllowOverscroll(false)
        scroll:AddChild(profile_box)
    end)
    set_vertical_slot(content:AddChildToVerticalBox(scroll), true, margin(0, 0, 0, 10))

    local status = make_text(tree, "Ready.", 16)
    if status then
        set_vertical_slot(content:AddChildToVerticalBox(status), false, margin(0, 8, 0, 0))
    end

    current_controls = {
        tree = tree,
        name_display = name_display,
        action_bar = action_bar,
        profile_box = profile_box,
        status = status,
        save_button = save_button,
        focus_button = save_button or automatic_name_button or close_button,
        close_button = close_button,
        confirmation_panel = confirmation_panel,
        confirmation_text = confirmation_text,
        confirm_button = confirm_button,
        cancel_button = cancel_button
    }
    update_name_display()
    return true
end

local function load_page_class()
    local class = find_class(PAGE_CLASS_PATH)
    if class then
        return class
    end
    if not is_valid(asset_registry_helpers) then
        local helpers_ok, helpers = pcall(StaticFindObject, "/Script/AssetRegistry.Default__AssetRegistryHelpers")
        if helpers_ok and is_valid(helpers) then
            asset_registry_helpers = helpers
        end
    end
    if is_valid(asset_registry_helpers) then
        local asset_ok, asset = pcall(function()
            return asset_registry_helpers:GetAsset({
                ObjectPath = UEHelpers.FindOrAddFName(PAGE_CLASS_PATH)
            })
        end)
        if asset_ok and is_valid(asset) then
            class_cache[PAGE_CLASS_PATH] = asset
            return asset
        end
    end
    if LoadAsset then
        pcall(LoadAsset, PAGE_CLASS_PATH)
        pcall(LoadAsset, "/Game/Mods/Loadouts/UI/WBP_LoadoutsPage.WBP_LoadoutsPage")
    end
    class = find_class(PAGE_CLASS_PATH)
    if class then
        return class
    end
    local ok, typed = pcall(StaticFindObject, "WidgetBlueprintGeneratedClass " .. PAGE_CLASS_PATH)
    if ok and is_valid(typed) then
        class_cache[PAGE_CLASS_PATH] = typed
        return typed
    end
    return nil
end

local function current_page_is_active()
    if not is_valid(current_page) then
        return false
    end
    if current_menu_managed and is_valid(current_menu_manager) then
        local ok, top_page = pcall(function()
            return current_menu_manager:GetTopPage()
        end)
        if ok then
            return is_valid(top_page) and object_address(top_page) == object_address(current_page)
        end
        return true
    end
    local ok, in_viewport = pcall(function()
        return current_page:IsInViewport()
    end)
    return not ok or in_viewport
end

local function current_page_is_present()
    if not is_valid(current_page) then
        return false
    end
    if current_menu_managed and is_valid(current_menu_manager) then
        local ok, in_stack = pcall(function()
            return current_menu_manager:IsPageInStack(current_page:GetFName())
        end)
        if ok then
            return in_stack
        end
    end
    local ok, in_viewport = pcall(function()
        return current_page:IsInViewport()
    end)
    return not ok or in_viewport
end

local function restore_previous_input(character_page, menu_manager, was_menu_managed)
    local context = api.context()
    if not context then
        return
    end
    local character_address = object_address(character_page)
    local launcher = character_address and launcher_by_page[character_address] or nil
    ExecuteWithDelay(1, function()
        ExecuteInGameThread(function()
            if current_page ~= nil then
                return
            end
            local target = launcher and is_valid(launcher.button) and focus_target(launcher.button) or nil
            if is_valid(target) then
                if was_menu_managed and is_valid(menu_manager) then
                    take_airship_focus(menu_manager, target, "Restore")
                else
                    set_ui_focus(context, target)
                end
                return
            end
            if was_menu_managed then
                return
            end
            if is_valid(character_page) and set_ui_focus(context, character_page) then
                return
            end
            local library = nil
            pcall(function()
                library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
            end)
            if is_valid(library) and is_valid(context.player_controller) then
                pcall(function()
                    library:SetInputMode_GameOnly(context.player_controller)
                end)
            end
        end)
    end)
end

local function release_stale_page()
    local stale_page = current_page
    local stale_character_page = current_character_page
    local stale_character_page_enabled = current_character_page_enabled
    local stale_menu_manager = current_menu_manager
    local stale_menu_managed = current_menu_managed
    if get_pending_confirmation() and type(api.cancel) == "function" then
        pcall(api.cancel)
    end
    if is_valid(stale_page) then
        pcall(function()
            stale_page:RemoveFromParent()
        end)
    end
    clear_action_addresses(page_action_addresses)
    clear_action_addresses(row_action_addresses)
    clear_action_addresses(confirmation_action_addresses)
    if stale_character_page_enabled ~= nil and is_valid(stale_character_page) then
        pcall(function()
            stale_character_page:SetIsEnabled(stale_character_page_enabled)
        end)
    end
    current_page = nil
    current_character_page = nil
    current_character_page_enabled = nil
    current_controls = nil
    current_menu_library = nil
    current_menu_manager = nil
    current_menu_managed = false
    restore_previous_input(stale_character_page, stale_menu_manager, stale_menu_managed)
    log("Page left the menu stack; stale state released")
end

function LoadoutUI.open(character_page)
    if current_page ~= nil then
        if current_page_is_present() then
            return true, "The Loadouts page is already open."
        end
        release_stale_page()
    end
    local context, context_error = api.context()
    if not context then
        return false, context_error
    end
    if not load_wayfinder_button_class() then
        return false, "The Wayfinder access-button class is unavailable."
    end
    current_menu_library = nil
    current_menu_manager = nil
    current_menu_managed = false
    local library = nil
    pcall(function()
        library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    end)
    if not is_valid(library) then
        return false, "The UMG widget library is unavailable."
    end
    clear_action_addresses(page_action_addresses)
    clear_action_addresses(row_action_addresses)
    clear_action_addresses(confirmation_action_addresses)
    current_controls = nil
    profile_name_buffer = ""
    local page = nil
    local airship_page = false
    local page_built = false
    local page_build_error = nil
    local airship_class = find_class(AIRSHIP_PAGE_CLASS_PATH)
    local menu_library, menu_manager = get_airship_menu(context)
    if airship_class and menu_library and menu_manager and is_valid(character_page) then
        local parent_ok, menu_parent = pcall(function()
            return character_page:GetParent()
        end)
        if not parent_ok or not is_valid(menu_parent) then
            menu_parent = nil
            log("The Character page uses the Airship player-screen host")
        end
        local stack_before = nil
        pcall(function()
            stack_before = menu_manager:GetPageStackNum()
        end)
        local create_ok, candidate = pcall(function()
            return library:Create(context.player_controller, airship_class, context.player_controller)
        end)
        if create_ok and is_valid(candidate) then
            local configured, configure_error = configure_airship_page(candidate)
            if configured then
                page_built, page_build_error = build_page(candidate)
            end
            local add_ok = false
            local add_result = nil
            if configured and page_built then
                add_ok, add_result = pcall(function()
                    return menu_library:AddToAirshipMenu(
                        candidate,
                        context.player_controller,
                        menu_parent
                    )
                end)
            end
            local stack_after = nil
            local top_matches = false
            local in_stack = false
            local parent_matches = menu_parent == nil
            local stack_ok = false
            if configured and page_built and add_ok and add_result == true then
                stack_ok = pcall(function()
                    stack_after = menu_manager:GetPageStackNum()
                    top_matches = object_address(menu_manager:GetTopPage()) == object_address(candidate)
                    in_stack = menu_manager:IsPageInStack(candidate:GetFName())
                    if menu_parent ~= nil then
                        parent_matches = object_address(candidate:GetParent()) == object_address(menu_parent)
                    end
                end)
            end
            if stack_ok and top_matches and in_stack and parent_matches then
                page = candidate
                airship_page = true
                current_menu_library = menu_library
                current_menu_manager = menu_manager
                current_menu_managed = true
                log(string.format(
                    "Prebuilt Airship page added: stack=%s->%s top=%s host=%s",
                    tostring(stack_before),
                    tostring(stack_after),
                    tostring(top_matches),
                    menu_parent and "parent" or "player-screen"
                ))
            else
                if add_ok and add_result == true then
                    pcall(function()
                        menu_manager:DebugRemovePage(candidate:GetName())
                    end)
                else
                    pcall(function()
                        candidate:RemoveFromParent()
                    end)
                end
                clear_action_addresses(page_action_addresses)
                clear_action_addresses(row_action_addresses)
                clear_action_addresses(confirmation_action_addresses)
                current_controls = nil
                page_built = false
                log("Prebuilt Airship page insertion failed: " .. tostring(
                    configure_error or page_build_error or add_result or candidate
                ))
            end
        else
            log("Prebuilt Airship page creation failed: " .. tostring(candidate))
        end
    end
    if not is_valid(page) and airship_class then
        local native_ok, native_error = pcall(function()
            page = library:Create(context.player_controller, airship_class, context.player_controller)
        end)
        airship_page = is_valid(page)
        if not native_ok or not airship_page then
            log("Native Airship page creation failed: " .. tostring(native_error or "invalid page"))
        end
    end
    if not is_valid(page) then
        local page_class = load_page_class()
        if not page_class then
            return false, "Loadouts.pak is unavailable or its UMG class could not load."
        end
        pcall(function()
            page = library:Create(context.player_controller, page_class, context.player_controller)
        end)
    end
    if not is_valid(page) then
        return false, "The Loadouts UMG page could not be created."
    end
    current_page = page
    current_character_page = is_valid(character_page) and character_page or nil
    current_character_page_enabled = nil
    if not current_menu_managed then
        current_menu_library = nil
        current_menu_manager = nil
    end
    if airship_page then
        local configured, configure_error = configure_airship_page(page)
        if not configured then
            log("Airship page configuration failed: " .. tostring(configure_error))
        end
    end
    if not page_built then
        clear_action_addresses(page_action_addresses)
        clear_action_addresses(row_action_addresses)
        clear_action_addresses(confirmation_action_addresses)
        current_controls = nil
        page_built, page_build_error = build_page(page)
    end
    if not page_built then
        if current_menu_managed and is_valid(current_menu_manager) then
            pcall(function()
                current_menu_manager:DebugRemovePage(page:GetName())
            end)
        end
        clear_action_addresses(page_action_addresses)
        clear_action_addresses(row_action_addresses)
        clear_action_addresses(confirmation_action_addresses)
        current_page = nil
        current_character_page = nil
        current_character_page_enabled = nil
        current_controls = nil
        current_menu_library = nil
        current_menu_manager = nil
        current_menu_managed = false
        return false, page_build_error
    end
    if not current_menu_managed then
        local viewport_ok = run_ui_step("Page viewport insertion", function()
            page:AddToViewport(500)
        end)
        if not viewport_ok then
            clear_action_addresses(page_action_addresses)
            clear_action_addresses(row_action_addresses)
            clear_action_addresses(confirmation_action_addresses)
            current_page = nil
            current_character_page = nil
            current_character_page_enabled = nil
            current_controls = nil
            current_menu_library = nil
            current_menu_manager = nil
            current_menu_managed = false
            return false, "The Loadouts page could not enter the viewport."
        end
        run_ui_step("Page viewport layout", function()
            local layout_library = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
            if not is_valid(layout_library) then
                return
            end
            local viewport_size = layout_library:GetViewportSize(page)
            page:SetAlignmentInViewport(vector(0, 0))
            page:SetPositionInViewport(vector(0, 0), false)
            page:SetDesiredSizeInViewport(viewport_size)
        end)
    end
    LoadoutUI.refresh()
    if is_valid(current_character_page) then
        pcall(function()
            current_character_page_enabled = current_character_page:GetIsEnabled()
            current_character_page:SetIsEnabled(false)
        end)
    end
    pcall(function()
        page:ForceLayoutPrepass()
    end)
    local initial_widget = current_controls and (
        get_pending_confirmation() and current_controls.confirm_button or current_controls.focus_button
    ) or nil
    local initial_focus = focus_target(initial_widget)
    if is_valid(current_menu_manager) and is_valid(initial_focus) then
        local focus_ok = take_airship_focus(current_menu_manager, initial_focus, "Initial Airship focus")
        if not focus_ok then
            log("The Airship menu could not focus the first Loadouts action")
        end
    elseif not set_ui_focus(context, initial_focus) then
        log("Page input mode could not be set")
    end
    ExecuteWithDelay(50, function()
        ExecuteInGameThread(function()
            if is_valid(current_page) and current_controls then
                local widget = get_pending_confirmation()
                    and current_controls.confirm_button
                    or current_controls.focus_button
                local focus = focus_target(widget)
                if is_valid(current_menu_manager) and is_valid(focus) then
                    take_airship_focus(current_menu_manager, focus, "Delayed Airship focus")
                else
                    set_ui_focus(context, focus)
                end
                local focus_ok, focus_state = pcall(function()
                    local menu_focus = is_valid(current_menu_manager) and current_menu_manager:GetCurrentFocus() or nil
                    return string.format(
                        "keyboard=%s user=%s menu_target=%s",
                        tostring(is_valid(focus) and focus:HasKeyboardFocus()),
                        tostring(is_valid(focus) and focus:HasAnyUserFocus()),
                        tostring(is_valid(menu_focus) and object_address(menu_focus) == object_address(focus))
                    )
                end)
                log("Focus state " .. tostring(focus_ok and focus_state or "unavailable"))
            end
        end)
    end)
    log("Page opened")
    return true, "Loadouts page opened."
end

function LoadoutUI.close()
    if get_pending_confirmation() then
        if type(api.cancel) ~= "function" then
            local message = "The confirmation service is unavailable."
            set_status(message, true)
            return false, message
        end
        local call_ok, ok, message = pcall(api.cancel)
        if not call_ok then
            message = "The confirmation could not be canceled: " .. tostring(ok)
            set_status(message, true)
            return false, message
        end
        operation_result(ok, message)
        return ok, message
    end
    if not is_valid(current_page) then
        release_stale_page()
        return true, "The Loadouts page is closed."
    end
    if current_menu_managed and is_valid(current_menu_manager) then
        local page = current_page
        local menu_manager = current_menu_manager
        local close_ok, close_result = pcall(function()
            return menu_manager:TryBackButton()
        end)
        if close_ok and close_result == false then
            close_ok, close_result = pcall(function()
                return menu_manager:DebugRemovePage(page:GetName())
            end)
        end
        if not close_ok or close_result == false then
            local message = "The Airship menu stack could not close the Loadouts page: " .. tostring(close_result)
            log(message)
            return false, message
        end
        log("Airship page close requested")
        return true, "Loadouts page close requested."
    end
    release_stale_page()
    log("Page closed")
    return true, "Loadouts page closed."
end

local function inject_launcher(character_page)
    if not is_valid(character_page) then
        return false
    end
    if not load_wayfinder_button_class() then
        log("The Wayfinder access-button class could not load")
        return false
    end
    local page_address = object_address(character_page)
    if not page_address then
        return false
    end
    local existing = launcher_by_page[page_address]
    if existing and is_valid(existing.container) then
        return true
    end
    local tree = nil
    local wrap_box = nil
    pcall(function()
        tree = character_page.WidgetTree
        wrap_box = character_page.WrapBox_menuAccessButtons
    end)
    if not is_valid(tree) or not is_valid(wrap_box) then
        return false
    end
    local size_box = construct("/Script/UMG.SizeBox", tree)
    if not size_box then
        return false
    end
    local launcher_addresses = {}
    local button = make_button(tree, "LOADOUTS", function()
        local ok, message = LoadoutUI.open(character_page)
        if not ok then
            log(message)
        end
    end, launcher_addresses, color(0.08, 0.32, 0.48, 1.0))
    if not button then
        return false
    end
    local attached, attach_error = pcall(function()
        size_box:SetMinDesiredWidth(180)
        size_box:SetMinDesiredHeight(72)
        size_box:SetVisibility(SLATE_SELF_HIT_TEST_INVISIBLE)
        size_box:SetContent(button)
        local slot = wrap_box:AddChildToWrapBox(size_box)
        slot:SetPadding(margin(4, 4, 4, 4))
        slot:SetHorizontalAlignment(0)
        slot:SetVerticalAlignment(0)
    end)
    local parent_ok, parent = pcall(function()
        return size_box:GetParent()
    end)
    if not attached or not parent_ok or object_address(parent) ~= object_address(wrap_box) then
        pcall(function()
            size_box:RemoveFromParent()
        end)
        clear_action_addresses(launcher_addresses)
        log("Access button insertion failed: " .. tostring(attach_error or "parent validation failed"))
        return false
    end
    launcher_by_page[page_address] = {
        container = size_box,
        button = button,
        action_addresses = launcher_addresses
    }
    log("Access button added")
    return true
end

local function schedule_launcher(character_page, page_address)
    ExecuteWithDelay(500, function()
        ExecuteInGameThread(function()
            launcher_pending[page_address] = nil
            inject_launcher(character_page)
        end)
    end)
end

local function is_character_page(widget)
    if not is_valid(widget) then
        return false
    end
    local ok, class_name = pcall(function()
        return to_text(widget:GetClass():GetFName())
    end)
    return ok and class_name == CHARACTER_PAGE_CLASS
end

local function discover_character_pages()
    local ok, discovery_error = pcall(function()
        local widgets = FindAllOf(CHARACTER_PAGE_CLASS)
        for _, widget in pairs(widgets or {}) do
            local address = object_address(widget)
            local launcher = address and launcher_by_page[address] or nil
            if launcher and not is_valid(launcher.container) then
                clear_action_addresses(launcher.action_addresses)
                launcher_by_page[address] = nil
                launcher = nil
            end
            if address and not launcher and not launcher_pending[address] then
                launcher_pending[address] = true
                schedule_launcher(widget, address)
            end
        end
    end)
    return ok, discovery_error
end

local function register_character_page_hook()
    if character_page_hook_registered then
        return true
    end
    if not LoadAsset then
        return false, "LoadAsset is unavailable."
    end
    local load_ok, loaded = pcall(LoadAsset, CHARACTER_PAGE_CLASS_PATH)
    if not load_ok then
        return false, loaded
    end
    if is_valid(loaded) then
        class_cache[CHARACTER_PAGE_CLASS_PATH] = loaded
    end
    if not load_class(CHARACTER_PAGE_CLASS_PATH) then
        return false, "The character page class could not load."
    end
    local ok, hook_error = pcall(function()
        RegisterHook(CHARACTER_PAGE_CONSTRUCT_PATH, function(context_parameter)
            local character_page = unwrap_parameter(context_parameter)
            if not is_character_page(character_page) then
                return
            end
            local page_address = object_address(character_page)
            local launcher = page_address and launcher_by_page[page_address] or nil
            if launcher and not is_valid(launcher.container) then
                clear_action_addresses(launcher.action_addresses)
                launcher_by_page[page_address] = nil
                launcher = nil
            end
            if page_address and not launcher and not launcher_pending[page_address] then
                launcher_pending[page_address] = true
                schedule_launcher(character_page, page_address)
            end
        end)
    end)
    if not ok then
        return false, hook_error
    end
    character_page_hook_registered = true
    return true
end

local function register_native_relay()
    _G.LoadoutsNativeFocus = function(_, focus_address)
        ExecuteInGameThread(function()
            local address = tostring(focus_address or "")
            local target_address = button_event_targets[address] or address
            local button = button_objects[target_address]
            if is_valid(button) and button_page_scoped[target_address] == current_page_is_active() then
                handle_focus_change(button, "Native menu event")
            else
                handle_focus_change(nil, "Native menu event")
            end
        end)
    end
    _G.LoadoutsNativePageRemoved = function(page_address)
        ExecuteInGameThread(function()
            if is_valid(current_page) and object_address(current_page) == tostring(page_address or "") then
                release_stale_page()
            end
        end)
    end
    log("Native event endpoints ready")
end

local function register_button_press_hook()
    if button_press_hook_registered then
        return true
    end
    if not load_wayfinder_button_class() then
        return false, "The Wayfinder access-button class could not load."
    end
    local ok, hook_error = pcall(function()
        RegisterHook(WAYFINDER_BUTTON_PRESS_PATH, function(context_parameter)
            local owner = unwrap_parameter(context_parameter)
            local source_address = object_address(owner)
            local target_address = source_address and button_event_targets[source_address] or nil
            ExecuteInGameThread(function()
                if target_address and button_page_scoped[target_address] == current_page_is_active() then
                    activate_button(target_address, "Blueprint button event")
                end
            end)
        end)
    end)
    if ok then
        button_press_hook_registered = true
    end
    return ok, hook_error
end

local function start_page_lifecycle_watch()
    if lifecycle_watch_started then
        return
    end
    lifecycle_watch_started = true
    LoopAsync(100, function()
        ExecuteInGameThread(function()
            if current_page ~= nil and not current_page_is_present() then
                release_stale_page()
            end
        end)
        return false
    end)
end

local function register_name_keys()
    if name_keys_registered then
        return true
    end
    local characters = {
        { Key.A, "A" }, { Key.B, "B" }, { Key.C, "C" }, { Key.D, "D" },
        { Key.E, "E" }, { Key.F, "F" }, { Key.G, "G" }, { Key.H, "H" },
        { Key.I, "I" }, { Key.J, "J" }, { Key.K, "K" }, { Key.L, "L" },
        { Key.M, "M" }, { Key.N, "N" }, { Key.O, "O" }, { Key.P, "P" },
        { Key.Q, "Q" }, { Key.R, "R" }, { Key.S, "S" }, { Key.T, "T" },
        { Key.U, "U" }, { Key.V, "V" }, { Key.W, "W" }, { Key.X, "X" },
        { Key.Y, "Y" }, { Key.Z, "Z" },
        { Key.ZERO, "0" }, { Key.ONE, "1" }, { Key.TWO, "2" },
        { Key.THREE, "3" }, { Key.FOUR, "4" }, { Key.FIVE, "5" },
        { Key.SIX, "6" }, { Key.SEVEN, "7" }, { Key.EIGHT, "8" },
        { Key.NINE, "9" }
    }
    local registered = 0
    for _, entry in ipairs(characters) do
        local key = entry[1]
        local value = entry[2]
        local ok = pcall(function()
            RegisterKeyBind(key, function()
                ExecuteInGameThread(function()
                    append_name_character(value)
                end)
            end)
        end)
        if ok then
            registered = registered + 1
        end
    end
    local space_ok = pcall(function()
        RegisterKeyBind(Key.SPACE, function()
            ExecuteInGameThread(function()
                if profile_name_buffer ~= "" and profile_name_buffer:sub(-1) ~= " " then
                    append_name_character(" ")
                end
            end)
        end)
    end)
    local backspace_ok = pcall(function()
        RegisterKeyBind(Key.BACKSPACE, function()
            ExecuteInGameThread(remove_name_character)
        end)
    end)
    name_keys_registered = registered == #characters and space_ok and backspace_ok
    log(string.format(
        "Name keys registered=%d/%d space=%s backspace=%s",
        registered,
        #characters,
        tostring(space_ok),
        tostring(backspace_ok)
    ))
    return name_keys_registered
end

function LoadoutUI.start(service_api)
    if started then
        return true
    end
    api = service_api
    started = true
    register_name_keys()
    register_native_relay()
    start_page_lifecycle_watch()
    ExecuteInGameThread(function()
        if not load_wayfinder_button_class() then
            log("The Wayfinder access-button class could not load")
        end
        local press_ok, press_error = register_button_press_hook()
        if press_ok then
            log("Blueprint button press hook ready")
        else
            log("Blueprint button press hook unavailable: " .. tostring(press_error))
        end
        local hook_ok, hook_error = register_character_page_hook()
        if hook_ok then
            log("Character page Construct hook ready")
        else
            log("Character page Construct hook unavailable: " .. tostring(hook_error))
        end
        local discovery_ok, discovery_error = discover_character_pages()
        if not discovery_ok then
            log("Character page discovery is unavailable: " .. tostring(discovery_error))
        end
    end)
    log("Bridge ready")
    return true
end

return LoadoutUI
