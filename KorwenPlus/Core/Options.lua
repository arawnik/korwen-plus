-- Core/Options.lua
-- Settings page under Options > AddOns, built on Blizzard's Settings API.

local ADDON_NAME, Korwen = ...

local category
local loginValues = {} -- values of reload-required settings as they were at login

StaticPopupDialogs.KORWENPLUS_RELOAD = {
    text = "KorwenPlus: some changes take effect after a UI reload.",
    button1 = RELOADUI or "Reload UI",
    button2 = LATER or "Later",
    OnAccept = ReloadUI,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function differs(a, b)
    if type(a) == "number" and type(b) == "number" then
        return math.abs(a - b) > 0.001 -- slider values aren't exact
    end
    return a ~= b
end

local function updateReloadPopup()
    local needed = false
    for key, value in pairs(loginValues) do
        if differs(Korwen.db[key], value) then
            needed = true
            break
        end
    end
    local shown = StaticPopup_Visible("KORWENPLUS_RELOAD")
    if needed and not shown then
        StaticPopup_Show("KORWENPLUS_RELOAD")
    elseif not needed and shown then
        StaticPopup_Hide("KORWENPLUS_RELOAD")
    end
end

-- Sliders fire on every step while dragged, so check once they've settled.
local checkPending = false
local function checkReloadNeeded()
    if checkPending then return end
    checkPending = true
    C_Timer.After(0.3, function()
        checkPending = false
        updateReloadPopup()
    end)
end

-- Binds a setting directly to a top-level key in Korwen.db (default from Korwen.defaults).
-- opts.perLayout: bind to the active Edit Mode layout's settings instead (Korwen.layoutDefaults).
-- opts.requiresReload: prompt for a UI reload when changed from its login value.
-- opts.onChange: called after the value changes, for settings applied live.
local function register(key, varType, label, tooltip, opts)
    local variable = ADDON_NAME .. "_" .. key
    local setting
    if opts.perLayout then
        local default = Korwen.layoutDefaults[key]
        setting = Settings.RegisterProxySetting(category, variable, varType, label, default,
            function()
                local layout = Korwen:LayoutSettings()
                return layout and layout[key] or default
            end,
            function(value)
                local layout = Korwen:LayoutSettings()
                if layout then
                    layout[key] = value
                end
            end)

    else
        setting = Settings.RegisterAddOnSetting(
            category, variable, key, Korwen.db, varType, label, Korwen.defaults[key]
        )
    end
    if opts.requiresReload then
        loginValues[key] = Korwen.db[key]
        tooltip = tooltip .. "\n\nRequires a UI reload."
        Settings.SetOnValueChangedCallback(variable, checkReloadNeeded)
    end
    if opts.onChange then
        Settings.SetOnValueChangedCallback(variable, opts.onChange)
    end
    return setting, tooltip
end

local function addCheckbox(key, label, tooltip, opts)
    local setting, fullTooltip = register(key, "boolean", label, tooltip, opts or {})
    return Settings.CreateCheckbox(category, setting, fullTooltip)
end

-- Percentage slider for a number where 1 = 100%; opts.min/max/step use the same units.
local function addPercentSlider(key, label, tooltip, opts)
    local setting, fullTooltip = register(key, "number", label, tooltip, opts)
    local options = Settings.CreateSliderOptions(opts.min, opts.max, opts.step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return string.format("%d%%", value * 100 + 0.5)
    end)
    return Settings.CreateSlider(category, setting, options, fullTooltip)
end


-- Indents `child` under `parent` and disables it while the parent checkbox is off.
local function nestUnder(child, parent, parentKey)
    child:SetParentInitializer(parent, function() return Korwen.db[parentKey] end)
end

-- Disables `child` while the checkbox for `key` is off, without indenting it.
local function enabledBy(child, key)
    child:AddModifyPredicate(function() return Korwen.db[key] end)
end

local function addHeader(layout, name, tooltip)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name, tooltip))
end

StaticPopupDialogs.KORWENPLUS_COPY = {
    text = "Copy KorwenPlus settings from %s? Frame sizes and positions (saved per Edit Mode layout) aren't affected. The UI will reload.",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, characterKey)
        Korwen:CopySettingsFrom(characterKey)
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Picking a character asks for confirmation, copies and reloads; the dropdown itself never
-- holds a value, so it's a proxy setting rather than one stored in Korwen.db.
local function addCopyDropdown()
    local setting = Settings.RegisterProxySetting(category, ADDON_NAME .. "_copyFrom",
        Settings.VarType.String, "Copy settings from", "",
        function() return "" end,
        function(characterKey)
            if characterKey ~= "" then
                StaticPopup_Show("KORWENPLUS_COPY", characterKey, nil, characterKey)
            end
        end)
    local function options()
        local container = Settings.CreateControlTextContainer()
        container:Add("", "Choose a character")
        local keys = {}
        for key in pairs(KorwenPlusDB.characters) do
            if key ~= Korwen.characterKey then
                table.insert(keys, key)
            end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            container:Add(key, key)
        end
        return container:GetData()
    end
    Settings.CreateDropdown(category, setting, options,
        "Replace this character's settings with another character's. Frame sizes and positions are saved per Edit Mode layout, so they aren't copied.")
end

Korwen:On("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME then return end
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

    addHeader(layout, "Character", "Saved separately for each character.")

    addCheckbox("portrait3D", "Use 3D portraits",
        "Show an animated 3D model instead of the flat portrait on the player, target, focus and pet frames.",
        { requiresReload = true })

    local tot = addCheckbox("totEnabled", "Improved Target of Target",
        "Removes the portrait from the Target of Target frame and lets you move it by dragging it while Edit Mode is open.",
        { requiresReload = true })
    local function updateText() Korwen:UpdateTargetOfTargetText() end
    nestUnder(addCheckbox("totHealthText", "Show health %",
        "Show the health percentage on the Target of Target health bar.",
        { onChange = updateText }),
        tot, "totEnabled")
    nestUnder(addCheckbox("totPowerText", "Show power %",
        "Show the power (mana, rage, energy...) percentage on the Target of Target power bar.",
        { onChange = updateText }),
        tot, "totEnabled")

    addCopyDropdown()

    addHeader(layout, "Edit Mode layout",
        "Saved per Edit Mode layout, together with frame positions. Switching layouts switches these too.")

    enabledBy(addPercentSlider("totScale", "Target of Target size",
        "Size of the Target of Target frame.",
        { min = 0.8, max = 1.6, step = 0.05, perLayout = true,
          onChange = function() Korwen:UpdateTargetOfTargetScale() end }),
        "totEnabled")
    enabledBy(addPercentSlider("totWidth", "Target of Target width",
        "Width of the Target of Target bars, extended to the left.",
        { min = 1, max = 1.5, step = 0.05, perLayout = true,
          onChange = function() Korwen:UpdateTargetOfTargetWidth() end }),
        "totEnabled")

    Settings.RegisterAddOnCategory(category)
end)

function Korwen:OpenOptions()
    Settings.OpenToCategory(category:GetID())
end
