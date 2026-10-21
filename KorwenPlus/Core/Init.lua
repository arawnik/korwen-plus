-- Core/Init.lua
-- Addon namespace, saved variable defaults, and the shared event dispatcher.
-- Every other file attaches to this table instead of using globals.

local ADDON_NAME, Korwen = ...
_G.KorwenPlus = Korwen -- exposed for /dump and in-game debugging only; code should use the Korwen upvalue

Korwen.name = ADDON_NAME

local defaults = {
    portrait3D = false,
}
Korwen.defaults = defaults

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

Korwen:On("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME then return end
    KorwenPlusDB = applyDefaults(KorwenPlusDB or {}, defaults)
    Korwen.db = KorwenPlusDB
end)

SLASH_KORWENPLUS1 = "/korwenplus"
SLASH_KORWENPLUS2 = "/kp"
SlashCmdList.KORWENPLUS = function(msg)
    if Korwen.OpenOptions then
        Korwen:OpenOptions()
    end
end
