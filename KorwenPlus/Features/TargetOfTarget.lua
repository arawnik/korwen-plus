-- Features/TargetOfTarget.lua
-- "Improved Target of Target" (Korwen.db.totEnabled, applied at login): removes the portrait,
-- replaces the portrait's ring art with the art's right end mirrored onto the left around the
-- bars, and lets the frame be moved while Edit Mode is open. Blizzard's ToT frame belongs to the
-- target frame, so Edit Mode can't move it by itself: we show a drag handle over the visible
-- frame and save its center in the active Edit Mode layout's settings (Korwen:LayoutSettings();
-- UIParent coordinates, so scale changes don't move it). Until moved in a layout, the frame
-- stays where Blizzard puts it.
-- Size (totScale) and width (totWidth) come from the active Edit Mode layout and apply live.
-- Optionally shows health and power percentages on the bars.

local ADDON_NAME, Korwen = ...

local tot = TargetFrameToT
if not tot then return end

local NAME_FONT_SCALE = 0.8

local active = false
local handle
local applying = false

-- Regions moved into this frame stay invisible whatever Blizzard does to them.
local hidden = CreateFrame("Frame", nil, tot)
hidden:Hide()

local function textureSource(texture)
    local atlas = texture:GetAtlas()
    local info = atlas and C_Texture.GetAtlasInfo(atlas)
    if info then
        return info.file or info.filename, info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    end
    local ulx, uly, _, _, _, _, lrx, lry = texture:GetTexCoord()
    return texture:GetTexture(), ulx, lrx, uly, lry
end

-- The bar art doesn't fill its frame exactly: the health art starts about 1.5 units in from the
-- bar's left edge and ends about 4 short of its right, and the power art (which differs per
-- power type, e.g. rounded rage ends) is inset a few units on both sides. So both bars are
-- stretched past a shared span by these amounts and clipped to it, giving flat, matching ends.
local HEALTH_OVERHANG_LEFT, HEALTH_OVERHANG_RIGHT = 2, 5
local POWER_OVERHANG = 5
-- Gap between the bars and the inside of the box.
local SPAN_GAP = 1

-- Blizzard's name font is large for a frame this small.
local function shrinkName()
    local font, size, flags = tot.Name:GetFont()
    if font and size then
        tot.Name:SetFont(font, size * NAME_FONT_SCALE, flags)
    end
end

-- Replaces Blizzard's fill masks (shaped for the portrait layout) with a rectangle that
-- trims the bar's overhangs; it's anchored to the bar, so it follows any resizing.
local function clipFill(bar, overhangLeft, overhangRight)
    local fill = bar:GetStatusBarTexture()
    if not (fill and fill.GetNumMaskTextures) then return end
    for i = fill:GetNumMaskTextures(), 1, -1 do
        fill:RemoveMaskTexture(fill:GetMaskTexture(i))
    end
    local mask = bar:CreateMaskTexture()
    mask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", bar, "TOPLEFT", overhangLeft, 0)
    mask:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -overhangRight, 0)
    fill:AddMaskTexture(mask)
end

-- Health and power percentages (Korwen.db.totHealthText/totPowerText) in the middle of the visible part of
-- each bar. Blizzard updates the ToT every frame and no health events fire for targettarget,
-- so the text is refreshed on a short timer, only while the frame is shown. Percentages are
-- secret values: they're only passed straight into SetFormattedText.
local PERCENT_INTERVAL = 0.2
local healthText, powerText, percentTicker
-- Blizzard rounds percentages up (math.ceil), which can't be done on a secret value; scaling
-- to 0-100 shifted up by just under half and letting "%.0f" round gives the same result.
local CEIL_SHIFT = 0.499
local percentCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
    percentCurve = C_CurveUtil.CreateCurve()
    percentCurve:SetType(Enum.LuaCurveType.Linear)
    percentCurve:AddPoint(0, CEIL_SHIFT)
    percentCurve:AddPoint(1, 100 + CEIL_SHIFT)
end

local function createPercentText(bar, size, overhangLeft, overhangRight)
    local text = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    local font, _, flags = text:GetFont()
    text:SetFont(font, size, flags)
    text:SetPoint("CENTER", bar, "CENTER", (overhangLeft - overhangRight) / 2, 0)
    return text
end

local function setPercent(text, getPercent, ...)
    local ok, percent = pcall(getPercent, ...)
    if not (ok and percent and pcall(text.SetFormattedText, text, "%.0f%%", percent)) then
        text:SetText("")
    end
end

local function updatePercents()
    local unit = tot.unit or "targettarget"
    if Korwen.db.totHealthText then
        setPercent(healthText, UnitHealthPercent, unit, true, percentCurve)
    end
    if Korwen.db.totPowerText then
        setPercent(powerText, UnitPowerPercent, unit, nil, false, percentCurve)
    end
end

local function startPercents()
    if not (healthText and (Korwen.db.totHealthText or Korwen.db.totPowerText) and tot:IsShown()) then return end
    updatePercents()
    percentTicker = percentTicker or C_Timer.NewTicker(PERCENT_INTERVAL, updatePercents)
end

local function stopPercents()
    if percentTicker then
        percentTicker:Cancel()
        percentTicker = nil
    end
end

-- Called when a percentage setting changes.
function Korwen:UpdateTargetOfTargetText()
    if not healthText then return end
    healthText:SetShown(self.db.totHealthText)
    powerText:SetShown(self.db.totPowerText)
    stopPercents()
    startPercents()
end

-- Blizzard's layout, measured once before we change anything (ToT frame units, relative to
-- its top left), so the layout can be rebuilt for any width without changes piling up.
local original
local function measure()
    local art, health, power, name = tot.FrameTexture, tot.HealthBar, tot.ManaBar, tot.Name
    local totLeft, totTop = tot:GetLeft(), tot:GetTop()
    local file, texLeft, texRight, texTop, texBottom = textureSource(art)
    if not (file and totLeft and art:GetLeft() and health:GetLeft() and power:GetTop() and name:GetBottom()) then
        return
    end
    return {
        file = file, texLeft = texLeft, texRight = texRight, texTop = texTop, texBottom = texBottom,
        artLeft = art:GetLeft() - totLeft, artRight = art:GetRight() - totLeft,
        healthLeft = health:GetLeft() - totLeft, healthRight = health:GetRight() - totLeft,
        healthTop = health:GetTop() - totTop, healthBottom = health:GetBottom() - totTop,
        powerTop = power:GetTop() - totTop, powerBottom = power:GetBottom() - totTop,
        nameBottom = name:GetBottom() - totTop,
    }
end

local function place(region, left, right, top, bottom)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", tot, "TOPLEFT", left, top)
    region:SetPoint("BOTTOMRIGHT", tot, "TOPLEFT", right, bottom)
end

-- The box is drawn as two mirrored halves of the art's right end. They also outline the
-- visible frame, used to size and place the drag handle.
local artLeftHalf, artRightHalf

-- Sizes the box and bars for the layout's width (health bar widened to the left): the box
-- keeps the same margin on both sides, both bars cover a shared span inside it with their
-- art's ends clipped off, and the name is centered above it.
local function applyWidth()
    if not artRightHalf then return end
    local o, layout = original, Korwen:LayoutSettings()
    local width = layout and layout.totWidth or Korwen.layoutDefaults.totWidth
    local barRight = o.healthRight
    local barLeft = barRight - (o.healthRight - o.healthLeft) * width

    local boxLeft = barLeft - (o.artRight - barRight)
    local half = (o.artRight - boxLeft) / 2
    local cut = o.texRight - (o.texRight - o.texLeft) * half / (o.artRight - o.artLeft)
    artRightHalf:SetTexCoord(cut, o.texRight, o.texTop, o.texBottom)
    artRightHalf:SetWidth(half)
    artLeftHalf:SetTexCoord(o.texRight, cut, o.texTop, o.texBottom)
    artLeftHalf:SetWidth(half)

    local left, right = barLeft + SPAN_GAP, barRight - SPAN_GAP
    place(tot.HealthBar, left - HEALTH_OVERHANG_LEFT, right + HEALTH_OVERHANG_RIGHT, o.healthTop, o.healthBottom)
    place(tot.ManaBar, left - POWER_OVERHANG, right + POWER_OVERHANG, o.powerTop, o.powerBottom)
    tot.Name:ClearAllPoints()
    tot.Name:SetPoint("BOTTOMLEFT", tot, "TOPLEFT", left, o.nameBottom)
    tot.Name:SetPoint("BOTTOMRIGHT", tot, "TOPLEFT", right, o.nameBottom)
end

-- Needs on-screen geometry, so it's retried each time the frame is shown until it succeeds.
local function rebuildFrame()
    if artRightHalf then return end
    original = original or measure()
    if not original then return end
    local art = tot.FrameTexture
    local layer, sublevel = art:GetDrawLayer()
    local parent = art:GetParent()

    artRightHalf = parent:CreateTexture(nil, layer, nil, sublevel)
    artRightHalf:SetTexture(original.file)
    artRightHalf:SetPoint("TOPRIGHT", art)
    artRightHalf:SetPoint("BOTTOMRIGHT", art)

    artLeftHalf = parent:CreateTexture(nil, layer, nil, sublevel)
    artLeftHalf:SetTexture(original.file)
    artLeftHalf:SetPoint("TOPRIGHT", artRightHalf, "TOPLEFT")
    artLeftHalf:SetPoint("BOTTOMRIGHT", artRightHalf, "BOTTOMLEFT")

    art:SetParent(hidden)
    clipFill(tot.HealthBar, HEALTH_OVERHANG_LEFT, HEALTH_OVERHANG_RIGHT)
    clipFill(tot.ManaBar, POWER_OVERHANG, POWER_OVERHANG)
    tot.Name:SetJustifyH("CENTER")
    shrinkName()
    healthText = createPercentText(tot.HealthBar, 9, HEALTH_OVERHANG_LEFT, HEALTH_OVERHANG_RIGHT)
    powerText = createPercentText(tot.ManaBar, 7, POWER_OVERHANG, POWER_OVERHANG)
    Korwen:UpdateTargetOfTargetText()
end
-- UIParent units per ToT frame unit.
local function ratio()
    return tot:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

-- Center and size of the visible frame, in ToT frame units.
local function visibleBox()
    local left = (artLeftHalf or tot):GetLeft()
    local right = (artRightHalf or tot):GetRight()
    local top, bottom = (artRightHalf or tot):GetTop(), (artRightHalf or tot):GetBottom()
    if not (left and right and top and bottom) then return end
    return (left + right) / 2, (top + bottom) / 2, right - left, top - bottom
end

-- Protected frame: can only be scaled and moved out of combat, so this is retried on PLAYER_REGEN_ENABLED.
-- Size and position come from the active Edit Mode layout. The saved position is the visible
-- frame's center, so the ToT frame is offset by the distance between its own center and the
-- visible frame's center. Layouts without a saved position get Blizzard's anchor back.
local blizzardPoints = {}
local function applyPosition()
    if not active or applying or InCombatLockdown() then return end
    applying = true
    local layout = Korwen:LayoutSettings()
    tot:SetScale(layout and layout.totScale or Korwen.layoutDefaults.totScale)
    local pos = layout and layout.totPosition
    if pos then
        local boxX, boxY = visibleBox()
        local totX, totY = tot:GetCenter()
        local offsetX, offsetY = 0, 0
        if boxX and totX then
            offsetX, offsetY = boxX - totX, boxY - totY
        end
        tot:ClearAllPoints()
        tot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x / ratio() - offsetX, pos.y / ratio() - offsetY)
    elseif layout then
        tot:ClearAllPoints()
        for _, point in ipairs(blizzardPoints) do
            tot:SetPoint(unpack(point))
        end
    end
    applying = false
end

-- Called when the size setting changes. Pins an unmoved frame's center first, so it grows in place.
function Korwen:UpdateTargetOfTargetScale()
    local layout = self:LayoutSettings()
    if not active or not layout then return end
    if not layout.totPosition and not InCombatLockdown() then
        local x, y = visibleBox()
        if x then
            layout.totPosition = { x = x * ratio(), y = y * ratio() }
        end
    end
    applyPosition()
end

local function createHandle()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    local fill = frame:CreateTexture(nil, "OVERLAY")
    fill:SetAllPoints()
    fill:SetColorTexture(0.2, 0.6, 1, 0.35)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    label:SetText("Target of Target")

    -- Ticks marking the middle of each edge, to help line the frame up with others.
    for _, point in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local tick = frame:CreateTexture(nil, "OVERLAY", nil, 1)
        tick:SetColorTexture(1, 1, 1, 0.9)
        tick:SetPoint(point)
        if point == "TOP" or point == "BOTTOM" then
            tick:SetSize(2, 6)
        else
            tick:SetSize(6, 2)
        end
    end

    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local layout = Korwen:LayoutSettings()
        if layout then
            layout.totPosition = { x = x, y = y }
        end
        applyPosition()
    end)
    return frame
end

local function showHandle()
    handle = handle or createHandle()
    handle:ClearAllPoints()
    local x, y, width, height = visibleBox()
    if x then
        local r = ratio()
        handle:SetSize(width * r, height * r)
        handle:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * r, y * r)
    else
        handle:SetSize(120, 40)
        handle:SetPoint("CENTER", UIParent, "CENTER")
    end
    handle:Show()
end

local function hideHandle()
    if handle then handle:Hide() end
end

-- On first show the frame is rebuilt; then the width and position are applied.
local function setUp()
    if artRightHalf then
        applyPosition()
        startPercents()
        return
    end
    rebuildFrame()
    applyWidth()
    applyPosition()
end

local function onLayoutChanged()
    applyWidth()
    applyPosition()
    if handle and handle:IsShown() then
        showHandle()
    end
end

-- Called when the width setting changes.
function Korwen:UpdateTargetOfTargetWidth()
    if active then
        onLayoutChanged()
    end
end

Korwen:On("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME or not Korwen.db.totEnabled then return end
    active = true

    local portrait = tot.Portrait or tot.portrait or _G.TargetFrameToTPortrait
    if portrait then
        portrait:SetParent(hidden)
    end
    tot:HookScript("OnShow", setUp)
    tot:HookScript("OnHide", stopPercents)
    for i = 1, tot:GetNumPoints() do
        blizzardPoints[i] = { tot:GetPoint(i) }
    end
    -- Blizzard may re-anchor the frame on layout changes; put it back where the user left it.
    hooksecurefunc(tot, "SetPoint", applyPosition)

    Korwen:On("PLAYER_ENTERING_WORLD", setUp)
    Korwen:On("PLAYER_REGEN_ENABLED", applyPosition)
    Korwen:On("EDIT_MODE_LAYOUTS_UPDATED", onLayoutChanged)
    if EditModeManagerFrame and EditModeManagerFrame.SelectLayout then
        hooksecurefunc(EditModeManagerFrame, "SelectLayout", onLayoutChanged)
    end
    EventRegistry:RegisterCallback("EditMode.Enter", showHandle)
    EventRegistry:RegisterCallback("EditMode.Exit", hideHandle)
end)
