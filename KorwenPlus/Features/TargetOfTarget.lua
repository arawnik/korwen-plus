-- Features/TargetOfTarget.lua
-- "Improved Target of Target" (Korwen.db.totEnabled, applied at login): removes the portrait,
-- replaces the portrait's ring art with the art's right end mirrored onto the left around the
-- bars, and lets the frame be moved while Edit Mode is open. Blizzard's ToT frame belongs to the
-- target frame, so Edit Mode can't move it by itself: we show a drag handle over the visible
-- frame and save its center in Korwen.db.totPosition (UIParent coordinates, so scale changes
-- don't move it). Until moved, the frame stays where Blizzard puts it.
-- Size is Korwen.db.totScale (live); width is Korwen.db.totWidth (applied at login).

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

-- Replaces Blizzard's fill masks (shaped for the portrait layout) with a rectangle.
local function clipFill(bar, left, right)
    local fill = bar:GetStatusBarTexture()
    if not (fill and fill.GetNumMaskTextures) then return end
    for i = fill:GetNumMaskTextures(), 1, -1 do
        fill:RemoveMaskTexture(fill:GetMaskTexture(i))
    end
    local mask = bar:CreateMaskTexture()
    mask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("TOPLEFT", bar, "TOPLEFT", left, 0)
    mask:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -right, 0)
    fill:AddMaskTexture(mask)
end

-- Places a bar so its art covers the span [left, right] (screen coordinates of the ToT frame)
-- with the given overhangs, keeping its current top and bottom, and clips it to the span.
local function fitBar(bar, left, right, overhangLeft, overhangRight)
    local top, bottom, totLeft, totTop = bar:GetTop(), bar:GetBottom(), tot:GetLeft(), tot:GetTop()
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", tot, "TOPLEFT", left - overhangLeft - totLeft, top - totTop)
    bar:SetPoint("BOTTOMRIGHT", tot, "TOPLEFT", right + overhangRight - totLeft, bottom - totTop)
    clipFill(bar, overhangLeft, overhangRight)
end

-- Lines both bars up on the span and centers the name above it.
local function fitBarsAndName(left, right)
    local health, power, name = tot.HealthBar, tot.ManaBar, tot.Name
    local nameBottom, totLeft, totTop = name:GetBottom(), tot:GetLeft(), tot:GetTop()
    fitBar(health, left, right, HEALTH_OVERHANG_LEFT, HEALTH_OVERHANG_RIGHT)
    if power then
        fitBar(power, left, right, POWER_OVERHANG, POWER_OVERHANG)
    end
    name:ClearAllPoints()
    name:SetPoint("BOTTOMLEFT", tot, "TOPLEFT", left - totLeft, nameBottom - totTop)
    name:SetPoint("BOTTOMRIGHT", tot, "TOPLEFT", right - totLeft, nameBottom - totTop)
    name:SetJustifyH("CENTER")
end

-- Widens the health bar to the left by Korwen.db.totWidth.
local function widenBars(health)
    local width, height = health:GetSize()
    local right, top, totLeft, totTop = health:GetRight(), health:GetTop(), tot:GetLeft(), tot:GetTop()
    local extra = width * (Korwen.db.totWidth - 1)
    if extra < 0.5 or not (right and top and totLeft and totTop) then return end

    health:ClearAllPoints()
    health:SetPoint("TOPRIGHT", tot, "TOPLEFT", right - totLeft, top - totTop)
    health:SetSize(width + extra, height)
end

-- Needs on-screen geometry, so it's retried each time the frame is shown until it succeeds.
-- The two halves also outline the visible frame, used to size and place the drag handle.
local artLeftHalf, artRightHalf
local function mirrorFrameArt()
    local art, bar = tot.FrameTexture, tot.HealthBar
    if artRightHalf or not art or not bar then return end
    local artLeft, artRight = art:GetLeft(), art:GetRight()
    local file, left, right, top, bottom = textureSource(art)
    if not (artLeft and artRight and bar:GetLeft() and file) then return end
    widenBars(bar)

    -- Box around the bars with the same margin on both sides, drawn as two mirrored halves
    -- of the art's right end.
    local barLeft, barRight = bar:GetLeft(), bar:GetRight()
    local boxLeft = barLeft - (artRight - barRight)
    local half = (artRight - boxLeft) / 2
    local cut = right - (right - left) * half / (artRight - artLeft)
    local layer, sublevel = art:GetDrawLayer()
    local parent = art:GetParent()

    artRightHalf = parent:CreateTexture(nil, layer, nil, sublevel)
    artRightHalf:SetTexture(file)
    artRightHalf:SetTexCoord(cut, right, top, bottom)
    artRightHalf:SetWidth(half)
    artRightHalf:SetPoint("TOPRIGHT", art)
    artRightHalf:SetPoint("BOTTOMRIGHT", art)

    artLeftHalf = parent:CreateTexture(nil, layer, nil, sublevel)
    artLeftHalf:SetTexture(file)
    artLeftHalf:SetTexCoord(right, cut, top, bottom)
    artLeftHalf:SetWidth(half)
    artLeftHalf:SetPoint("TOPRIGHT", artRightHalf, "TOPLEFT")
    artLeftHalf:SetPoint("BOTTOMRIGHT", artRightHalf, "BOTTOMLEFT")

    art:SetParent(hidden)

    fitBarsAndName(barLeft + SPAN_GAP, barRight - SPAN_GAP)
    shrinkName()
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
-- The saved position is the visible frame's center, so the ToT frame is offset by the
-- distance between its own center and the visible frame's center.
local function applyPosition()
    if not active or applying or InCombatLockdown() then return end
    applying = true
    tot:SetScale(Korwen.db.totScale)
    local pos = Korwen.db.totPosition
    if pos then
        local boxX, boxY = visibleBox()
        local totX, totY = tot:GetCenter()
        local offsetX, offsetY = 0, 0
        if boxX and totX then
            offsetX, offsetY = boxX - totX, boxY - totY
        end
        tot:ClearAllPoints()
        tot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x / ratio() - offsetX, pos.y / ratio() - offsetY)
    end
    applying = false
end

-- Called when the size setting changes. Pins an unmoved frame's center first, so it grows in place.
function Korwen:UpdateTargetOfTargetScale()
    if not active then return end
    if not self.db.totPosition and not InCombatLockdown() then
        local x, y = visibleBox()
        if x then
            self.db.totPosition = { x = x * ratio(), y = y * ratio() }
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
        Korwen.db.totPosition = { x = x, y = y }
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

-- Once the art is mirrored the visible frame's center is known, so the position is re-applied.
local function setUp()
    mirrorFrameArt()
    applyPosition()
end

Korwen:On("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon ~= ADDON_NAME or not Korwen.db.totEnabled then return end
    active = true

    local portrait = tot.Portrait or tot.portrait or _G.TargetFrameToTPortrait
    if portrait then
        portrait:SetParent(hidden)
    end
    tot:HookScript("OnShow", setUp)
    -- Blizzard may re-anchor the frame on layout changes; put it back where the user left it.
    hooksecurefunc(tot, "SetPoint", applyPosition)

    Korwen:On("PLAYER_ENTERING_WORLD", setUp)
    Korwen:On("PLAYER_REGEN_ENABLED", applyPosition)
    EventRegistry:RegisterCallback("EditMode.Enter", showHandle)
    EventRegistry:RegisterCallback("EditMode.Exit", hideHandle)
end)
