-- Core/Init.lua
-- Addon namespace, saved variable defaults, and the shared event dispatcher.
-- Every other file attaches to this table instead of using globals.

local ADDON_NAME, Korwen = ...
_G.KorwenPlus = Korwen -- exposed for /dump and in-game debugging only; code should use the Korwen upvalue

Korwen.name = ADDON_NAME

local defaults = {
    portrait3D = false,
    totEnabled = true,
    totHealthText = true,
    totPowerText = false,
}
Korwen.defaults = defaults

-- Settings saved per Edit Mode layout instead of per character (frame sizes and positions).
local layoutDefaults = {
    totScale = 1.2,
    totWidth = 1.3,
}
Korwen.layoutDefaults = layoutDefaults

-- Recursively fills missing keys in `db` from `defaults` without overwriting existing values.
local function applyDefaults(db, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(db[key]) ~= "table" then
                db[key] = {}
            end
            applyDefaults(db[key], value)
        elseif db[key] == nil then
            db[key] = value
        end
    end
    return db
end
Korwen.applyDefaults = applyDefaults

-- Simple event bus: modules call Korwen:On("EVENT", handler) in their own file.
-- Avoids every module creating its own frame and duplicating RegisterEvent/OnEvent boilerplate.
local eventFrame = CreateFrame("Frame")
local handlers = {}

function Korwen:On(event, handler)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], handler)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, handler in ipairs(list) do
        handler(Korwen, ...)
    end
end)

-- KorwenPlusDB is account-wide so characters can copy each other's settings, but every
-- character has its own table in KorwenPlusDB.characters, exposed as Korwen.db.
Korwen:On("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME then return end
    if type(KorwenPlusDB) ~= "table" or type(KorwenPlusDB.characters) ~= "table" then
        KorwenPlusDB = { characters = {} } -- also drops settings from before they were per character
    end
    KorwenPlusDB.layouts = KorwenPlusDB.layouts or {}
    Korwen.characterKey = UnitName("player") .. " - " .. GetRealmName()
    local characters = KorwenPlusDB.characters
    characters[Korwen.characterKey] = applyDefaults(characters[Korwen.characterKey] or {}, defaults)
    Korwen.db = characters[Korwen.characterKey]
end)

-- Settings for the active Edit Mode layout, or nil until Blizzard has loaded the layouts
-- (EDIT_MODE_LAYOUTS_UPDATED). Layouts are matched by name; character-specific layouts
-- are prefixed with the character, since other characters can have layouts with the same name.
function Korwen:LayoutSettings()
    if not (EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutInfo) then return end
    local ok, info = pcall(EditModeManagerFrame.GetActiveLayoutInfo, EditModeManagerFrame)
    if not ok or not info or not info.layoutName then return end
    local key = info.layoutName
    if info.layoutType == Enum.EditModeLayoutType.Character then
        key = self.characterKey .. ": " .. key
    end
    KorwenPlusDB.layouts[key] = applyDefaults(KorwenPlusDB.layouts[key] or {}, layoutDefaults)
    return KorwenPlusDB.layouts[key]
end

-- Copies another character's settings over this character's. Only keys in defaults are copied;
-- sizes and positions are saved per Edit Mode layout, not per character.
function Korwen:CopySettingsFrom(characterKey)
    local source = KorwenPlusDB.characters[characterKey]
    if not source or characterKey == self.characterKey then return end
    for key in pairs(defaults) do
        if source[key] ~= nil then
            self.db[key] = source[key]
        end
    end
end

SLASH_KORWENPLUS1 = "/korwenplus"
SLASH_KORWENPLUS2 = "/kp"
SlashCmdList.KORWENPLUS = function(msg)
    if Korwen.OpenOptions then
        Korwen:OpenOptions()
    end
end
