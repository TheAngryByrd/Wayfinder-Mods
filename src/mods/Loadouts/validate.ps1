[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Source', 'Package')]
    [string] $Phase,

    [Parameter(Mandatory)]
    [string] $RepositoryDirectory,

    [Parameter(Mandatory)]
    [string] $ModDirectory,

    [string] $DistributionDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Find-CMake {
    $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    foreach ($root in @(
        'C:\Program Files\Microsoft Visual Studio\2022',
        'C:\Program Files (x86)\Microsoft Visual Studio\2022'
    )) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        $bundled = Get-ChildItem -LiteralPath $root -Recurse -Filter cmake.exe -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like '*CommonExtensions*Microsoft*CMake*bin*' } |
            Select-Object -First 1 -ExpandProperty FullName
        if ($bundled) {
            return $bundled
        }
    }

    throw 'CMake was not found. Install Visual Studio 2022 with Desktop development with C++, or add CMake to PATH.'
}

function Assert-LuaSources {
    param(
        [Parameter(Mandatory)][string] $Repository,
        [Parameter(Mandatory)][string] $Mod
    )

    $toolSource = Join-Path $Repository 'tools\lua\5.4.4'
    $versionHeader = Join-Path $toolSource 'include\lua.h'
    if (-not (Test-Path -LiteralPath $versionHeader)) {
        throw "The vendored Lua 5.4.4 source was not found: $versionHeader"
    }
    $versionText = Get-Content -LiteralPath $versionHeader -Raw
    foreach ($versionPart in @(
        '#define LUA_VERSION_MAJOR\s+"5"',
        '#define LUA_VERSION_MINOR\s+"4"',
        '#define LUA_VERSION_RELEASE\s+"4"'
    )) {
        if ($versionText -notmatch $versionPart) {
            throw "The vendored Lua source is not version 5.4.4: $versionHeader"
        }
    }

    $cmake = Find-CMake
    $toolBuild = Join-Path $Repository 'build\tools\lua-5.4.4'
    & $cmake -S $toolSource -B $toolBuild -G 'Visual Studio 17 2022' -A x64
    if ($LASTEXITCODE -ne 0) {
        throw "Lua syntax tool configuration failed with exit code $LASTEXITCODE."
    }
    & $cmake --build $toolBuild --config Release --target luac
    if ($LASTEXITCODE -ne 0) {
        throw "Lua syntax tool compilation failed with exit code $LASTEXITCODE."
    }

    $luac = Join-Path $toolBuild 'Release\luac.exe'
    if (-not (Test-Path -LiteralPath $luac)) {
        throw "The Lua syntax tool was not created: $luac"
    }
    $version = (& $luac -v 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^Lua 5\.4\.4\b') {
        throw "The Lua syntax tool did not report Lua 5.4.4: $version"
    }

    $contentDirectory = Join-Path $Mod 'content'
    $luaFiles = @(Get-ChildItem -LiteralPath $contentDirectory -Recurse -File -Filter '*.lua' | Sort-Object FullName)
    if ($luaFiles.Count -eq 0) {
        throw "The Loadouts package contains no Lua source: $contentDirectory"
    }
    foreach ($luaFile in $luaFiles) {
        & $luac -p $luaFile.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "Lua 5.4.4 rejected the source file: $($luaFile.FullName)"
        }
        Write-Host "Lua 5.4.4 syntax valid: $($luaFile.FullName)"
    }
}

function Test-OrdinalContains {
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $Value
    )

    return $Text.IndexOf($Value, [System.StringComparison]::Ordinal) -ge 0
}

function Join-LuaStringSegments {
    param([Parameter(Mandatory)][string] $Source)

    while ($true) {
        $joined = [regex]::Replace($Source, '"\s*\.\.\s*"', '')
        if ($joined -ceq $Source) {
            return $Source
        }
        $Source = $joined
    }
}

function Find-LuaStringConstant {
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Value
    )

    $pattern = '\blocal\s+(?<Name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*"' + [regex]::Escape($Value) + '"'
    $match = [regex]::Match($Source, $pattern)
    if ($match.Success) {
        return $match.Groups['Name'].Value
    }
    return $null
}

function Assert-LuaRuntimeContracts {
    param([Parameter(Mandatory)][string] $Mod)

    $mainPath = Join-Path $Mod 'content\Scripts\main.lua'
    $uiPath = Join-Path $Mod 'content\Scripts\loadout_ui.lua'
    foreach ($path in @($mainPath, $uiPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "The Loadouts runtime source was not found: $path"
        }
    }

    $mainSource = Get-Content -LiteralPath $mainPath -Raw
    foreach ($legacyApi in @(
        'GetUnlockedTalentNodeIDs',
        'FindEquipmentSlotsForItem',
        'FogSoul_GetSlots',
        'ShowYesNoPopup'
    )) {
        if (Test-OrdinalContains -Text $mainSource -Value $legacyApi) {
            throw "The Loadouts service references the unsafe legacy API $legacyApi`: $mainPath"
        }
    }

    foreach ($apiEntry in @('pending_confirmation', 'confirm', 'cancel')) {
        $entryPattern = '(?m)^\s*' + [regex]::Escape($apiEntry) + '\s*=\s*[A-Za-z_][A-Za-z0-9_]*\s*,'
        if ($mainSource -notmatch $entryPattern) {
            throw "The Loadouts service does not expose the $apiEntry confirmation API: $mainPath"
        }
    }
    foreach ($bridgeName in @('LoadoutsNativeApplyDye', 'LoadoutsNativeDyeReady')) {
        if (-not (Test-OrdinalContains -Text $mainSource -Value $bridgeName)) {
            throw "The Loadouts service does not use the native dye bridge $bridgeName`: $mainPath"
        }
    }
    if (Test-OrdinalContains -Text $mainSource -Value 'context.inventory:GetAddress()') {
        throw "The Loadouts service passes a raw inventory pointer to the native dye bridge: $mainPath"
    }
    if (-not (Test-OrdinalContains -Text $mainSource -Value 'object_path(context.inventory)')) {
        throw "The Loadouts service does not pass a resolvable inventory object path to the native dye bridge: $mainPath"
    }
    foreach ($guidContract in @(
        'local UINT32_MAX = 4294967295',
        'local function normalize_guid_word',
        'local function normalize_guid_key_text',
        'local function engine_guid_word',
        'local function handle_identity',
        'local function handle_has_zero_id'
    )) {
        if (-not (Test-OrdinalContains -Text $mainSource -Value $guidContract)) {
            throw "The Loadouts service does not contain the signed-GUID compatibility contract: $guidContract"
        }
    }

    $handleIdentityMatch = [regex]::Match(
        $mainSource,
        '(?ms)^local function handle_identity\b.*?(?=^local function handle_has_zero_id\b)'
    )
    foreach ($identityPart in @(
        'snapshot.table_path',
        'snapshot.row',
        'snapshot.a',
        'snapshot.b',
        'snapshot.c',
        'snapshot.d'
    )) {
        if (-not $handleIdentityMatch.Success -or
            -not (Test-OrdinalContains -Text $handleIdentityMatch.Value -Value $identityPart)) {
            throw "The Loadouts item identity does not include $identityPart`: $mainPath"
        }
    }

    $itemLookupMatch = [regex]::Match(
        $mainSource,
        '(?ms)^local function parse_native_item\b.*?(?=^local function item_label\b)'
    )
    foreach ($lookupContract in @(
        'local function parse_native_item(payload)',
        'EchoItems = {}',
        'TalentPool = pool',
        'entry.Spec.EchoItems[handle_key(echo)] = echo',
        'local function native_capture_ready()',
        'type(_G.LoadoutsNativeCaptureReady) ~= "function"',
        'type(_G.LoadoutsNativeCaptureItem) ~= "function"',
        '_G.LoadoutsNativeCaptureItem,',
        'handle_identity(actual) ~= handle_identity(expected)'
    )) {
        if (-not $itemLookupMatch.Success -or
            -not (Test-OrdinalContains -Text $itemLookupMatch.Value -Value $lookupContract)) {
            throw "The Loadouts item lookup does not preserve $lookupContract`: $mainPath"
        }
    }
    foreach ($unsafeInventoryScan in @(
        'm_DataReplicators',
        '.m_ItemData.m_Items',
        'GetInitialChangesForAllItems',
        'get_indexed_item_entry',
        'inventory:FindItem',
        'FindItemFromId',
        'FindEquippedItem',
        'GetTalentPoolForTalent',
        'GetCurrentLoadout('
    )) {
        if (Test-OrdinalContains -Text $mainSource -Value $unsafeInventoryScan) {
            throw "The Loadouts service uses an unsafe reflected inventory scan: $unsafeInventoryScan`: $mainPath"
        }
    }
    $directLookupMatch = [regex]::Match(
        $mainSource,
        '(?ms)^local function get_item_entry\b.*?(?=^local function item_label\b)'
    )
    if (-not $directLookupMatch.Success) {
        throw "The Loadouts native item lookup was not found: $mainPath"
    }
    foreach ($unsafeItemLabelLookup in @(
        'GetDisplayName(entry)',
        'GetItemDefinition(handle',
        'GetItemDefinitionFromData'
    )) {
        if (Test-OrdinalContains -Text $mainSource -Value $unsafeItemLabelLookup) {
            throw "The Loadouts service passes complex item data through an unsafe label lookup: $unsafeItemLabelLookup`: $mainPath"
        }
    }
    $captureItemMatch = [regex]::Match(
        $mainSource,
        '(?ms)^local function capture_item\b.*?(?=^local function each_unlocked_archetype_node\b)'
    )
    foreach ($captureLookupContract in @(
        'if handle_has_zero_id(snapshot) then',
        'local identity = handle_identity(snapshot)',
        'get_item_entry(context.inventory, handle)',
        'entry.Spec.EquippedToSlotName',
        'entry.Spec.EquippedToSlotName ~= "None"',
        'entry.Spec.EchoItems[echo_id_key]'
    )) {
        if (-not $captureItemMatch.Success -or
            -not (Test-OrdinalContains -Text $captureItemMatch.Value -Value $captureLookupContract)) {
            throw "The Loadouts equipped-item capture does not preserve $captureLookupContract`: $mainPath"
        }
    }
    if (Test-OrdinalContains -Text $mainSource -Value '.AttachedFogSouls') {
        throw "The Loadouts service reads the transient loadout Echo array instead of the resolved item spec: $mainPath"
    }
    if (-not (Test-OrdinalContains -Text $captureItemMatch.Value -Value 'entry.Spec.FogSouls')) {
        throw "The Loadouts capture does not read Echo IDs from the resolved item spec: $mainPath"
    }
    foreach ($captureSnapshotContract in @(
        'loadout_items[#loadout_items + 1] = snapshot',
        'loadout_items_by_key[key] = true',
        'equipment_slots[#equipment_slots + 1] = copied',
        'for _, slot in ipairs(equipment_slots) do',
        'current_weapon_styles',
        'current_armor_styles'
    )) {
        if (-not (Test-OrdinalContains -Text $mainSource -Value $captureSnapshotContract)) {
            throw "The Loadouts capture does not preserve the plain snapshot contract $captureSnapshotContract`: $mainPath"
        }
    }
    $saveProfileMatch = [regex]::Match(
        $mainSource,
        '(?ms)^local function save_named_profile\b.*?(?=^local function delete_named_profile\b)'
    )
    $readyIndex = $saveProfileMatch.Value.IndexOf('local capture_ready, capture_error = native_capture_ready()', [StringComparison]::Ordinal)
    $contextIndex = $saveProfileMatch.Value.IndexOf('local context, context_error = get_context()', [StringComparison]::Ordinal)
    if (-not $saveProfileMatch.Success -or $readyIndex -lt 0 -or $contextIndex -le $readyIndex) {
        throw "The Loadouts save path does not fail closed before capture bridge use: $mainPath"
    }
    $applyEchosMatch = [regex]::Match(
        $mainSource,
        '(?ms)^local function apply_echos\b.*?(?=^local function apply_abilities\b)'
    )
    foreach ($echoApplyContract in @(
        'get_item_entry(context.inventory, holder)',
        'entry.Spec.FogSouls'
    )) {
        if (-not $applyEchosMatch.Success -or
            -not (Test-OrdinalContains -Text $applyEchosMatch.Value -Value $echoApplyContract)) {
            throw "The Loadouts Echo application does not preserve $echoApplyContract`: $mainPath"
        }
    }

    $uiSource = Get-Content -LiteralPath $uiPath -Raw
    foreach ($unsafeUiApi in @('NotifyOnNewObject', 'UserWidget:Construct')) {
        if (Test-OrdinalContains -Text $uiSource -Value $unsafeUiApi) {
            throw "The Loadouts UI references the unsafe discovery endpoint $unsafeUiApi`: $uiPath"
        }
    }
    foreach ($apiUsage in @('api.pending_confirmation', 'api.confirm', 'api.cancel')) {
        if (-not (Test-OrdinalContains -Text $uiSource -Value $apiUsage)) {
            throw "The Loadouts UI does not use the $apiUsage confirmation API: $uiPath"
        }
    }

    $normalizedUiSource = Join-LuaStringSegments -Source $uiSource
    $characterPagePath = '/Game/UI/UI_WF_Blueprints/UI_WF_UIPages/UI_Page_CharacterLoadout_v2.UI_Page_CharacterLoadout_v2_C'
    $invalidCharacterPagePath = '/Game/UI/UI_WF_Blueprints/UI_WF_UIPages/Armory/NewStandalone/UI_Page_CharacterLoadout_v2'
    if (Test-OrdinalContains -Text $normalizedUiSource -Value $invalidCharacterPagePath) {
        throw "The Loadouts UI uses the known invalid Character Loadout page directory: $uiPath"
    }
    if (-not (Test-OrdinalContains -Text $normalizedUiSource -Value 'WrapBox_menuAccessButtons')) {
        throw "The Loadouts UI does not target the live Character Loadout access-button container: $uiPath"
    }
    $characterHookPath = $characterPagePath + ':Construct'
    $characterPageConstant = Find-LuaStringConstant -Source $normalizedUiSource -Value $characterPagePath
    $hasCharacterHook = $normalizedUiSource -match (
        'RegisterHook\s*\(\s*"' + [regex]::Escape($characterHookPath) + '"\s*,'
    )
    if (-not $hasCharacterHook -and $characterPageConstant) {
        $escapedPageConstant = [regex]::Escape($characterPageConstant)
        $hasCharacterHook = $normalizedUiSource -match (
            'RegisterHook\s*\(\s*' + $escapedPageConstant + '\s*\.\.\s*":Construct"\s*,'
        )
        if (-not $hasCharacterHook) {
            $constructConstantPattern = '\blocal\s+(?<Name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*' +
                $escapedPageConstant + '\s*\.\.\s*":Construct"'
            $constructConstant = [regex]::Match($normalizedUiSource, $constructConstantPattern)
            if ($constructConstant.Success) {
                $hasCharacterHook = $normalizedUiSource -match (
                    'RegisterHook\s*\(\s*' + [regex]::Escape($constructConstant.Groups['Name'].Value) + '\s*,'
                )
            }
        }
    }
    if (-not $hasCharacterHook) {
        throw "The Loadouts UI does not register the exact Character Loadout Blueprint Construct hook: $uiPath"
    }

    $accessButtonPath = '/Game/UI/UI_WF_Blueprints/UI_WF_UIPages/Armory/NewStandalone/UI_CharacterMenu_AccessButton.UI_CharacterMenu_AccessButton_C'
    $accessButtonConstant = Find-LuaStringConstant -Source $normalizedUiSource -Value $accessButtonPath
    $hasAccessButtonClass = $normalizedUiSource -match (
        'load_class\s*\(\s*"' + [regex]::Escape($accessButtonPath) + '"\s*\)'
    )
    if (-not $hasAccessButtonClass -and $accessButtonConstant) {
        $hasAccessButtonClass = $normalizedUiSource -match (
            'load_class\s*\(\s*' + [regex]::Escape($accessButtonConstant) + '\s*\)'
        )
    }
    if (-not $hasAccessButtonClass) {
        throw "The Loadouts UI does not load the exact Character Loadout access-button class: $uiPath"
    }
    $buttonPressSuffix = ':BndEvt__UI_CharacterMenu_AccessButton_AirshipButton_159_K2Node_ComponentBoundEvent_1_OnButtonPressedEvent__DelegateSignature'
    if (-not (Test-OrdinalContains -Text $normalizedUiSource -Value $buttonPressSuffix) -or
        $normalizedUiSource -notmatch 'RegisterHook\s*\(\s*WAYFINDER_BUTTON_PRESS_PATH\s*,') {
        throw "The Loadouts UI does not hook the exact Blueprint access-button press event: $uiPath"
    }
    foreach ($inputEnumContract in @(
        'local SLATE_VISIBLE = 0',
        'local SLATE_COLLAPSED = 1',
        'local SLATE_HIT_TEST_INVISIBLE = 3',
        'local SLATE_SELF_HIT_TEST_INVISIBLE = 4',
        'local BUTTON_INPUT_DOWN_AND_UP = 0',
        'local BUTTON_PRESS_DOWN_AND_UP = 0'
    )) {
        if (-not (Test-OrdinalContains -Text $normalizedUiSource -Value $inputEnumContract)) {
            throw "The Loadouts UI does not define the required input enum $inputEnumContract`: $uiPath"
        }
    }

    $inputHelperMatch = [regex]::Match(
        $normalizedUiSource,
        '(?ms)^local function configure_wayfinder_button_input\b.*?(?=^local function make_wayfinder_button\b)'
    )
    if (-not $inputHelperMatch.Success) {
        throw "The Loadouts UI does not define the scoped Wayfinder button input helper: $uiPath"
    }

    $airshipConfigMatch = [regex]::Match(
        $normalizedUiSource,
        '(?ms)^local function configure_airship_page\b.*?(?=^local function set_vertical_slot\b)'
    )
    foreach ($pageInputContract in @(
        'page.bStealInputFromBelow = true',
        'page.bAllowInputWhileNotTop = false',
        'page.bPreventDPadInputSuppressionForCustomEvents = false',
        'page.bPreventWASDInputSuppressionForCustomEvents = false'
    )) {
        if (-not $airshipConfigMatch.Success -or
            -not (Test-OrdinalContains -Text $airshipConfigMatch.Value -Value $pageInputContract)) {
            throw "The Loadouts Airship page does not preserve $pageInputContract`: $uiPath"
        }
    }
    if (Test-OrdinalContains -Text $normalizedUiSource -Value 'CreateAndAddPageToPlayer(') {
        throw "The Loadouts page enters the Airship stack before its input ownership is configured: $uiPath"
    }
    $openPageMatch = [regex]::Match(
        $normalizedUiSource,
        '(?ms)^function LoadoutUI\.open\b.*?(?=^function LoadoutUI\.close\b)'
    )
    $createPageIndex = $openPageMatch.Value.IndexOf(
        'library:Create(context.player_controller, airship_class, context.player_controller)',
        [StringComparison]::Ordinal
    )
    $parentPageIndex = $openPageMatch.Value.IndexOf('return character_page:GetParent()', [StringComparison]::Ordinal)
    $configurePageIndex = $openPageMatch.Value.IndexOf('configure_airship_page(candidate)', [StringComparison]::Ordinal)
    $buildPageIndex = $openPageMatch.Value.IndexOf('page_built, page_build_error = build_page(candidate)', [StringComparison]::Ordinal)
    $addPageIndex = $openPageMatch.Value.IndexOf('menu_library:AddToAirshipMenu(', [StringComparison]::Ordinal)
    if (-not $openPageMatch.Success -or $parentPageIndex -lt 0 -or
        $createPageIndex -le $parentPageIndex -or $configurePageIndex -le $createPageIndex -or
        $buildPageIndex -le $configurePageIndex -or $addPageIndex -le $buildPageIndex) {
        throw "The Loadouts page must resolve its optional host, then be created, configured, and built before Airship stack insertion: $uiPath"
    }
    if (Test-OrdinalContains -Text $openPageMatch.Value -Value 'if parent_ok and is_valid(menu_parent) then') {
        throw "The Loadouts page blocks Airship's nil-parent player-screen fallback: $uiPath"
    }
    foreach ($playerScreenContract in @(
        'if not parent_ok or not is_valid(menu_parent) then',
        'menu_parent = nil',
        'menu_parent and "parent" or "player-screen"'
    )) {
        if (-not (Test-OrdinalContains -Text $openPageMatch.Value -Value $playerScreenContract)) {
            throw "The Loadouts page does not preserve the player-screen host contract $playerScreenContract`: $uiPath"
        }
    }
    foreach ($stackValidationContract in @(
        'menu_parent',
        'add_result == true',
        'object_address(menu_manager:GetTopPage()) == object_address(candidate)',
        'menu_manager:IsPageInStack(candidate:GetFName())',
        'object_address(candidate:GetParent()) == object_address(menu_parent)',
        'if stack_ok and top_matches and in_stack and parent_matches then'
    )) {
        if (-not (Test-OrdinalContains -Text $openPageMatch.Value -Value $stackValidationContract)) {
            throw "The Loadouts page does not validate Airship stack insertion with $stackValidationContract`: $uiPath"
        }
    }
    if (Test-OrdinalContains -Text $openPageMatch.Value -Value 'staging_parent') {
        throw "The Loadouts managed page uses a detached staging parent: $uiPath"
    }
    if (Test-OrdinalContains -Text $openPageMatch.Value -Value 'page:RemoveFromParent()') {
        throw "The Loadouts managed page can be detached from its Airship parent: $uiPath"
    }
    $unmanagedViewportIndex = $openPageMatch.Value.IndexOf('if not current_menu_managed then', [StringComparison]::Ordinal)
    $viewportInsertIndex = $openPageMatch.Value.IndexOf('page:AddToViewport(500)', [StringComparison]::Ordinal)
    if ($unmanagedViewportIndex -lt 0 -or $viewportInsertIndex -le $unmanagedViewportIndex) {
        throw "The Loadouts viewport fallback is not restricted to unmanaged pages: $uiPath"
    }
    foreach ($buttonInputContract in @(
        'root:SetVisibility(SLATE_SELF_HIT_TEST_INVISIBLE)',
        'button:SetVisibility(SLATE_SELF_HIT_TEST_INVISIBLE)',
        'button:SetIsEnabled(true)',
        'target:SetVisibility(SLATE_VISIBLE)',
        'target:SetIsEnabled(true)',
        'target:SetFocusable(true)',
        'target:SetClickMethod(BUTTON_INPUT_DOWN_AND_UP)',
        'target:SetPressMethod(BUTTON_PRESS_DOWN_AND_UP)',
        'target.bTakeFocusOnHover = true'
    )) {
        if (-not (Test-OrdinalContains -Text $inputHelperMatch.Value -Value $buttonInputContract)) {
            throw "The Loadouts UI input helper does not apply $buttonInputContract`: $uiPath"
        }
    }

    $buttonFactoryMatch = [regex]::Match(
        $normalizedUiSource,
        '(?ms)^local function make_wayfinder_button\b.*?(?=^local function make_button\b)'
    )
    if (-not $buttonFactoryMatch.Success) {
        throw "The Loadouts UI does not define the scoped Wayfinder button factory: $uiPath"
    }
    $factorySource = $buttonFactoryMatch.Value
    $lockIndex = $factorySource.IndexOf('button:isFeatureLocked(false)', [StringComparison]::Ordinal)
    $visualSetupIndex = $factorySource.IndexOf('button:visualSetup()', [StringComparison]::Ordinal)
    $inputSetupCall = 'local input_ok, input_error = configure_wayfinder_button_input(button, target)'
    $inputSetupIndex = $factorySource.IndexOf($inputSetupCall, [StringComparison]::Ordinal)
    if ($lockIndex -lt 0 -or $visualSetupIndex -le $lockIndex -or $inputSetupIndex -le $visualSetupIndex) {
        throw "The Loadouts UI must apply its lock, visual, and final input setup in order: $uiPath"
    }
    foreach ($factoryFailureContract in @('if not input_ok then', 'return nil')) {
        if (-not (Test-OrdinalContains -Text $factorySource -Value $factoryFailureContract)) {
            throw "The Loadouts UI button factory does not reject failed input setup: $uiPath"
        }
    }
    $focusHelperMatch = [regex]::Match(
        $normalizedUiSource,
        '(?ms)^local function take_airship_focus\b.*?(?=^local function focus_target\b)'
    )
    foreach ($focusContract in @(
        'local call_ok, accepted = pcall',
        'return menu_manager:TakeFocus(target, true)',
        'if not call_ok or accepted ~= true then',
        'handle_focus_change(target, source)'
    )) {
        if (-not $focusHelperMatch.Success -or
            -not (Test-OrdinalContains -Text $focusHelperMatch.Value -Value $focusContract)) {
            throw "The Loadouts Airship focus helper does not preserve $focusContract`: $uiPath"
        }
    }

    $focusVisualMatch = [regex]::Match(
        $normalizedUiSource,
        '(?ms)^local function set_wayfinder_focus_visual\b.*?(?=^local function run_wayfinder_focus_handler\b)'
    )
    $focusVisibilityPattern = 'SetVisibility\(focused and SLATE_HIT_TEST_INVISIBLE or SLATE_COLLAPSED\)'
    if (-not $focusVisualMatch.Success -or
        [regex]::Matches($focusVisualMatch.Value, $focusVisibilityPattern).Count -lt 5) {
        throw "The Loadouts focus artwork can consume the inner button mouse hit: $uiPath"
    }
    if ($focusVisualMatch.Value -match 'SetVisibility\(focused and 0 or 1\)') {
        throw "The Loadouts focus artwork uses mouse-blocking Visible state: $uiPath"
    }

    $launcherMatch = [regex]::Match(
        $normalizedUiSource,
        '(?ms)^local function inject_launcher\b.*?(?=^local function schedule_launcher\b)'
    )
    if (-not $launcherMatch.Success -or
        -not (Test-OrdinalContains -Text $launcherMatch.Value -Value 'size_box:SetVisibility(SLATE_SELF_HIT_TEST_INVISIBLE)')) {
        throw "The Loadouts launcher container does not pass mouse hit tests to its button: $uiPath"
    }

    $bindMatch = [regex]::Match(
        $normalizedUiSource,
        '(?ms)^local function bind_button\b.*?(?=^local function configure_wayfinder_button_input\b)'
    )
    foreach ($ownerMappingContract in @(
        'if event_owner ~= nil then',
        'if not event_owner_address then',
        'button_event_owners[address] = event_owner_address',
        'button_event_targets[event_owner_address] = address'
    )) {
        if (-not $bindMatch.Success -or
            -not (Test-OrdinalContains -Text $bindMatch.Value -Value $ownerMappingContract)) {
            throw "The Loadouts button owner map does not enforce $ownerMappingContract`: $uiPath"
        }
    }

    $pressHookMatch = [regex]::Match(
        $normalizedUiSource,
        '(?ms)^local function register_button_press_hook\b.*?(?=^local function start_page_lifecycle_watch\b)'
    )
    foreach ($pressDispatchContract in @(
        'local target_address = source_address and button_event_targets[source_address] or nil',
        'button_page_scoped[target_address] == current_page_is_active()',
        'activate_button(target_address, "Blueprint button event")'
    )) {
        if (-not $pressHookMatch.Success -or
            -not (Test-OrdinalContains -Text $pressHookMatch.Value -Value $pressDispatchContract)) {
            throw "The Loadouts press hook does not preserve $pressDispatchContract`: $uiPath"
        }
    }
    $targetCaptureIndex = $pressHookMatch.Value.IndexOf('local target_address =', [StringComparison]::Ordinal)
    $deferIndex = $pressHookMatch.Value.IndexOf('ExecuteInGameThread(function()', [StringComparison]::Ordinal)
    if ($targetCaptureIndex -lt 0 -or $deferIndex -le $targetCaptureIndex) {
        throw "The Loadouts press hook does not capture its target before deferred dispatch: $uiPath"
    }

    Write-Host "Loadouts Lua runtime contract guards passed: $mainPath, $uiPath"
}

function Assert-NativeSource {
    param([Parameter(Mandatory)][string] $Mod)

    $sourcePath = Join-Path $Mod 'native\dllmain.cpp'
    $cmakePath = Join-Path $Mod 'native\CMakeLists.txt'
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "The Loadouts native relay source was not found: $sourcePath"
    }
    if (-not (Test-Path -LiteralPath $cmakePath)) {
        throw "The Loadouts native CMake project was not found: $cmakePath"
    }
    $source = Get-Content -LiteralPath $sourcePath -Raw
    $cmake = Get-Content -LiteralPath $cmakePath -Raw
    if ($source -match '(?m)^\s*virtual\b[^\r\n]*\bon_ui_init\s*\(') {
        throw 'LoadoutsEventRelay declares on_ui_init, which is not in the UE4SS 3.0.1 CppUserModBase ABI.'
    }
    $virtualMethods = @([regex]::Matches($source, '(?m)^\s*virtual\b'))
    if ($virtualMethods.Count -ne 10) {
        throw "LoadoutsEventRelay must declare exactly 10 UE4SS 3.0.1 virtual entries. Found: $($virtualMethods.Count)"
    }
    foreach ($bridgeContract in @(
        'LoadoutsNativeApplyDye',
        'LoadoutsNativeDyeReady',
        'LoadoutsNativeCaptureItem',
        'LoadoutsNativeCaptureReady',
        '/Script/Wayfinder.PlayerInventoryComponent:ApplyDyeToItem',
        '/Script/Wayfinder.PlayerInventoryComponent:FindItem',
        '/Script/Wayfinder.PlayerInventoryComponent:FindItemFromId',
        '/Script/Wayfinder.PlayerInventoryComponent:GetTalentPoolForTalent',
        '?InitializeStruct@UStruct@Unreal@RC@@QEBAXPEAXH@Z',
        '?DestroyStruct@UStruct@Unreal@RC@@QEBAXPEAXH@Z',
        '?GetParmsSize@UFunction@Unreal@RC@@QEBAAEBGXZ',
        '?GetReturnValueOffset@UFunction@Unreal@RC@@QEBAAEBGXZ'
    )) {
        if (-not (Test-OrdinalContains -Text $source -Value $bridgeContract)) {
            throw "LoadoutsEventRelay does not contain the required native dye bridge contract: $bridgeContract"
        }
    }
    foreach ($luaArgumentContract in @(
        'take_lua_string(lua, 1, inventory_object_path)',
        'take_lua_string(lua, 2, item_table_path)',
        'take_lua_string(lua, 3, item_row_name)',
        'take_lua_integer(lua, static_cast<int>(index + 4), part)',
        'take_lua_string(lua, 8, dye_table_path)',
        'take_lua_string(lua, 9, dye_row_name)',
        'for (int index = 10; index <= stack_size; ++index)',
        'take_lua_integer(lua, index, value)'
    )) {
        if (-not (Test-OrdinalContains -Text $source -Value $luaArgumentContract)) {
            throw "LoadoutsEventRelay does not read its Lua arguments by index: $luaArgumentContract"
        }
    }
    if (Test-OrdinalContains -Text $source -Value 'while (g_lua_get_stack_size(&lua) > 0)') {
        throw 'LoadoutsEventRelay expects Lua argument reads to remove values from the stack.'
    }
    $reloadSafetyContracts = [ordered]@{
        'GET_MODULE_HANDLE_EX_FLAG_PIN' = 'module pinning'
        'std::uint64_t generation{};' = 'RelayEvent generation field'
        'const auto generation = g_generation.load();' = 'ProcessEvent generation snapshot'
        'event.generation = generation;' = 'queued-event generation stamp'
        'event.generation != g_generation.load()' = 'dispatch generation check'
        'if (!g_callback_registered.exchange(true))' = 'one-time ProcessEvent callback guard'
        'g_is_a(inventory, inventory_class)' = 'resolved inventory type check'
        'g_is_a(item_table, data_table_class)' = 'item data-table type check'
        'g_is_a(dye_table, data_table_class)' = 'dye data-table type check'
        'g_initialized.load(std::memory_order_acquire)' = 'one-time export initialization guard'
        'pcall(LoadoutsNativeFocus' = 'Lua endpoint exception boundary'
        'relay_queue_capacity = 256' = 'bounded native relay queue'
        'events.swap(g_events)' = 'lock-released relay drain'
        'LOADOUTS_DEBUG_CONFIGURATION' = 'Debug configuration rejection'
        '_ITERATOR_DEBUG_LEVEL != 0' = 'Debug ABI rejection'
    }
    if (Test-OrdinalContains -Text $source -Value '?queue_event@UE4SSProgram') {
        throw 'LoadoutsEventRelay uses the deadlock-prone UE4SS event queue.'
    }
    foreach ($assetOwnedPressContract in @('button_event_path', 'LoadoutsNativePress')) {
        if (Test-OrdinalContains -Text $source -Value $assetOwnedPressContract) {
            throw "LoadoutsEventRelay handles the asset-owned Blueprint press path natively: $assetOwnedPressContract"
        }
    }
    if (-not (Test-OrdinalContains -Text $cmake -Value '$<$<CONFIG:Debug>:LOADOUTS_DEBUG_CONFIGURATION>')) {
        throw 'LoadoutsEventRelay does not reject the ABI-incompatible Debug configuration.'
    }
    foreach ($reloadSafetyContract in $reloadSafetyContracts.GetEnumerator()) {
        if (-not (Test-OrdinalContains -Text $source -Value $reloadSafetyContract.Key)) {
            throw "LoadoutsEventRelay does not contain the required reload-safety contract $($reloadSafetyContract.Value): $($reloadSafetyContract.Key)"
        }
    }
    if ($source -notmatch 'using\s+ProcessEventCallback\s*=\s*std::function<void\s*\(\s*RC::Unreal::UObject\s*\*\s*,\s*RC::Unreal::UFunction\s*\*\s*,\s*void\s*\*\s*\)\s*>') {
        throw 'LoadoutsEventRelay does not use the exact UE4SS 3.0.1 ProcessEvent callback template type.'
    }
    foreach ($export in @('start_mod', 'uninstall_mod')) {
        if ($source -notmatch ('extern\s+"C"\s+__declspec\(dllexport\)[^\r\n]*\b' + $export + '\s*\(')) {
            throw "LoadoutsEventRelay does not declare the required export: $export"
        }
    }
    Write-Host "Loadouts native ABI source guard passed: $sourcePath"
}

function Convert-RvaToFileOffset {
    param(
        [Parameter(Mandatory)][uint32] $Rva,
        [Parameter(Mandatory)][object[]] $Sections
    )

    foreach ($section in $Sections) {
        $size = [Math]::Max([uint64]$section.VirtualSize, [uint64]$section.RawSize)
        if ([uint64]$Rva -ge [uint64]$section.VirtualAddress -and
            [uint64]$Rva -lt [uint64]$section.VirtualAddress + $size) {
            return [uint64]$section.RawOffset + ([uint64]$Rva - [uint64]$section.VirtualAddress)
        }
    }
    throw ('The PE RVA 0x{0:X8} is outside every section.' -f $Rva)
}

function Read-AsciiString {
    param(
        [Parameter(Mandatory)][System.IO.BinaryReader] $Reader,
        [Parameter(Mandatory)][uint64] $Offset
    )

    $Reader.BaseStream.Position = [int64]$Offset
    $bytes = [System.Collections.Generic.List[byte]]::new()
    while ($bytes.Count -lt 4096) {
        $value = $Reader.ReadByte()
        if ($value -eq 0) {
            return [System.Text.Encoding]::ASCII.GetString($bytes.ToArray())
        }
        $bytes.Add($value)
    }
    throw "The PE export name at offset $Offset is not terminated."
}

function Get-PeExportNames {
    param([Parameter(Mandatory)][string] $Path)

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "The packaged relay is not a PE file: $Path"
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "The packaged relay has no PE signature: $Path"
        }
        $reader.ReadUInt16() | Out-Null
        $sectionCount = $reader.ReadUInt16()
        $stream.Position += 12
        $optionalHeaderSize = $reader.ReadUInt16()
        $reader.ReadUInt16() | Out-Null
        $optionalHeaderOffset = $stream.Position
        $magic = $reader.ReadUInt16()
        $dataDirectoryOffset = if ($magic -eq 0x20B) { 112 } elseif ($magic -eq 0x10B) { 96 } else {
            throw ('The packaged relay has an unsupported PE optional-header value: 0x{0:X4}' -f $magic)
        }
        $stream.Position = $optionalHeaderOffset + $dataDirectoryOffset
        $exportRva = $reader.ReadUInt32()
        $reader.ReadUInt32() | Out-Null
        if ($exportRva -eq 0) {
            return @()
        }

        $sections = [System.Collections.Generic.List[object]]::new()
        $sectionTableOffset = $optionalHeaderOffset + $optionalHeaderSize
        for ($index = 0; $index -lt $sectionCount; $index++) {
            $stream.Position = $sectionTableOffset + ($index * 40)
            $reader.ReadBytes(8) | Out-Null
            $virtualSize = $reader.ReadUInt32()
            $virtualAddress = $reader.ReadUInt32()
            $rawSize = $reader.ReadUInt32()
            $rawOffset = $reader.ReadUInt32()
            $sections.Add([pscustomobject]@{
                VirtualSize = $virtualSize
                VirtualAddress = $virtualAddress
                RawSize = $rawSize
                RawOffset = $rawOffset
            })
        }

        $exportOffset = Convert-RvaToFileOffset -Rva $exportRva -Sections $sections
        $stream.Position = [int64]$exportOffset + 24
        $nameCount = $reader.ReadUInt32()
        $stream.Position = [int64]$exportOffset + 32
        $namesRva = $reader.ReadUInt32()
        $namesOffset = Convert-RvaToFileOffset -Rva $namesRva -Sections $sections
        $names = [System.Collections.Generic.List[string]]::new()
        for ($index = 0; $index -lt $nameCount; $index++) {
            $stream.Position = [int64]$namesOffset + ($index * 4)
            $nameRva = $reader.ReadUInt32()
            $nameOffset = Convert-RvaToFileOffset -Rva $nameRva -Sections $sections
            $names.Add((Read-AsciiString -Reader $reader -Offset $nameOffset))
        }
        return @($names)
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Assert-Package {
    param(
        [Parameter(Mandatory)][string] $Mod,
        [Parameter(Mandatory)][string] $Distribution
    )

    if ([string]::IsNullOrWhiteSpace($Distribution) -or -not (Test-Path -LiteralPath $Distribution)) {
        throw "The Loadouts distribution directory was not found: $Distribution"
    }
    $requiredPaths = @(
        'Atlas\Binaries\Win64\Mods\Loadouts\config.ini',
        'Atlas\Binaries\Win64\Mods\Loadouts\enabled.txt',
        'Atlas\Binaries\Win64\Mods\Loadouts\Scripts\main.lua',
        'Atlas\Binaries\Win64\Mods\Loadouts\Scripts\loadout_ui.lua',
        'Atlas\Binaries\Win64\Mods\Loadouts\dlls\main.dll',
        'Atlas\Binaries\Win64\UE4SS_Signatures\GUObjectArray.lua',
        'Atlas\Content\Paks\LogicMods\Loadouts.pak',
        'README.md'
    )
    foreach ($relativePath in $requiredPaths) {
        $path = Join-Path $Distribution $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
            throw "The Loadouts distribution is missing a required file: $path"
        }
    }

    $sourceContent = Join-Path $Mod 'content'
    $packageContent = Join-Path $Distribution 'Atlas\Binaries\Win64\Mods\Loadouts'
    foreach ($sourceFile in (Get-ChildItem -LiteralPath $sourceContent -Recurse -File -Filter '*.lua')) {
        $relativePath = $sourceFile.FullName.Substring($sourceContent.Length).TrimStart('\')
        $packageFile = Join-Path $packageContent $relativePath
        $sourceHash = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash
        $packageHash = (Get-FileHash -LiteralPath $packageFile -Algorithm SHA256).Hash
        if (-not $sourceHash.Equals($packageHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "The packaged Lua source differs from its validated source: $packageFile"
        }
    }

    $relayPath = Join-Path $packageContent 'dlls\main.dll'
    $exports = @(Get-PeExportNames -Path $relayPath | Sort-Object -Unique)
    $requiredExports = @('start_mod', 'uninstall_mod')
    $difference = @(Compare-Object -ReferenceObject $requiredExports -DifferenceObject $exports)
    if ($difference.Count -ne 0) {
        throw "The packaged Loadouts relay exports are invalid. Expected: $($requiredExports -join ', '). Actual: $($exports -join ', ')."
    }
    Write-Host "Loadouts package validation passed: $Distribution"
}

$resolvedRepository = (Resolve-Path -LiteralPath $RepositoryDirectory).Path
$resolvedMod = (Resolve-Path -LiteralPath $ModDirectory).Path
if ($Phase -eq 'Source') {
    Assert-LuaSources -Repository $resolvedRepository -Mod $resolvedMod
    Assert-LuaRuntimeContracts -Mod $resolvedMod
    Assert-NativeSource -Mod $resolvedMod
}
else {
    Assert-Package -Mod $resolvedMod -Distribution $DistributionDirectory
}
