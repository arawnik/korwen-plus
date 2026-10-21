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

local function checkReloadNeeded()
    for key, value in pairs(loginValues) do
        if Korwen.db[key] ~= value then
            StaticPopup_Show("KORWENPLUS_RELOAD")
            return
        end
    end
    StaticPopup_Hide("KORWENPLUS_RELOAD")
end

-- Binds a checkbox directly to a top-level boolean in Korwen.db.
-- Settings with `requiresReload` prompt for a UI reload when changed from their login value.
local function addCheckbox(key, label, tooltip, requiresReload)
    local variable = ADDON_NAME .. "_" .. key
    local setting = Settings.RegisterAddOnSetting(
        category, variable, key, Korwen.db, "boolean", label, Korwen.defaults[key]
    )
    if requiresReload then
        loginValues[key] = Korwen.db[key]
        tooltip = tooltip .. "\n\nRequires a UI reload."
        Settings.SetOnValueChangedCallback(variable, checkReloadNeeded)
    end
    Settings.CreateCheckbox(category, setting, tooltip)
end

Korwen:On("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME then return end
    category = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

    addCheckbox("portrait3D", "Use 3D portraits",
        "Show an animated 3D model instead of the flat portrait on the player, target, focus and pet frames.",
        true)

    Settings.RegisterAddOnCategory(category)
end)

function Korwen:OpenOptions()
    Settings.OpenToCategory(category:GetID())
end
