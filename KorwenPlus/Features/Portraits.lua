-- Features/Portraits.lua
-- When `portrait3D` is on at login, shows 3D models over the flat 2D portraits of
-- Blizzard's unit frames. The 2D portrait is only made transparent while a model
-- can be shown, so it remains the fallback for out-of-range units.

local ADDON_NAME, Korwen = ...

local FRAMES = {
    player = "PlayerFrame",
    target = "TargetFrame",
    focus = "FocusFrame",
    pet = "PetFrame",
}

local models = {}

local function asTexture(region)
    if region and region.GetObjectType and region:GetObjectType() == "Texture" then
        return region
    end
end

-- Modern frames keep the portrait texture in different places.
local function findPortrait(frame)
    return asTexture(frame.PlayerFrameContainer and frame.PlayerFrameContainer.PlayerPortrait)
        or asTexture(frame.TargetFrameContainer and frame.TargetFrameContainer.Portrait)
        or asTexture(frame.Portrait)
        or asTexture(frame.portrait)
end

-- Created on first use rather than at load, so Blizzard has finished setting up
-- the frame levels the model is placed relative to.
local function getModel(unit)
    if models[unit] then return models[unit] end
    local frame = _G[FRAMES[unit]]
    local portrait = frame and findPortrait(frame)
    if not portrait then return end

    local model = CreateFrame("PlayerModel", nil, frame)
    model:SetPoint("TOPLEFT", portrait, 4, -4)
    model:SetPoint("BOTTOMRIGHT", portrait, -4, 4)
    -- Below the portrait's container so the frame's ring art draws over the model.
    model:SetFrameLevel(math.max(0, (portrait:GetParent() or frame):GetFrameLevel() - 1))

    -- Round dark backdrop in place of the transparent 2D portrait.
    local backdrop = model:CreateTexture(nil, "BACKGROUND")
    backdrop:SetPoint("TOPLEFT", portrait, 1, -1)
    backdrop:SetPoint("BOTTOMRIGHT", portrait, -1, 1)
    backdrop:SetColorTexture(0.06, 0.06, 0.08, 0.9)
    local mask = model:CreateMaskTexture()
    mask:SetAllPoints(backdrop)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    backdrop:AddMaskTexture(mask)

    model.portrait = portrait
    models[unit] = model
    return model
end

local function update(unit, refresh)
    local model = getModel(unit)
    if not model then return end

    local visible = UnitIsVisible(unit)
    model:SetShown(visible)
    model.portrait:SetAlpha(visible and 0 or 1)
    if not visible then
        model.guid = nil
        return
    end

    -- SetUnit restarts the animation, so only call it when the unit changes.
    local guid = UnitGUID(unit)
    if refresh or model.guid ~= guid then
        model.guid = guid
        model:SetUnit(unit)
        model:SetPortraitZoom(1)
    end
end

local function refreshUnit(_, unit)
    if FRAMES[unit] then
        update(unit, true)
    end
end

Korwen:On("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME or not Korwen.db.portrait3D then return end

    Korwen:On("PLAYER_ENTERING_WORLD", function()
        for unit in pairs(FRAMES) do
            update(unit, true)
        end
    end)
    Korwen:On("PLAYER_TARGET_CHANGED", function() update("target") end)
    Korwen:On("PLAYER_FOCUS_CHANGED", function() update("focus") end)
    Korwen:On("UNIT_PET", function() update("pet") end)
    Korwen:On("UNIT_PORTRAIT_UPDATE", refreshUnit)
    Korwen:On("UNIT_MODEL_CHANGED", refreshUnit)
end)
