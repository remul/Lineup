local _, ns = ...

-- A small pill-shaped label for short text, e.g. a pet's breed ("P/S"): a dark fill with a thin
-- bronze outline like the cards' (see ns.CreateCardOutline), as wide as its text.
--   local badge = ns.CreateBadge(parent)
--   badge:SetPoint(...)
--   badge:SetText("P/S")                      -- nil or "" hides it
--   badge:SetText("Script", GREEN_FONT_COLOR) -- coloured: fill, outline and text in that colour
-- ns.CreateBadge(parent, scale) makes a smaller (or bigger) one, e.g. 0.8; the whole badge scales,
-- so its ends stay round. badge:SetMaxWidth(width) cuts longer text off with "...".
local BADGE_HEIGHT = 14 -- the pill textures' height, so the ends stay half circles
-- Pill textures are 28 x 14 with round ends 7 wide; only the middle stretches.
local PILL_END = 7
local TEXT_PADDING = 5
local TEXT_SCALE = 0.9
local FILL = CreateColor(0, 0, 0, 0.55)
local OUTLINE = CreateColor(0.62, 0.56, 0.46, 0.6)
-- Coloured badges: the fill is the colour darkened this much, the outline the colour itself.
local TINT_FILL_SHADE, TINT_FILL_ALPHA = 0.25, 0.7
local TINT_OUTLINE_ALPHA = 0.55

local function CreatePillTexture(badge, layer, file)
    local texture = badge:CreateTexture(nil, layer)
    texture:SetTexture(ns.MEDIA .. file)
    texture:SetTextureSliceMargins(PILL_END, 0, PILL_END, 0)
    texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    texture:SetAllPoints()
    return texture
end

local BadgeMixin = {}

-- Shows text in the badge, plain (white on dark) or in color, or hides the badge without text.
function BadgeMixin:SetText(text, color)
    if not text or text == "" then
        self:Hide()
        return
    end
    if color then
        local r, g, b = color:GetRGB()
        self.Fill:SetVertexColor(r * TINT_FILL_SHADE, g * TINT_FILL_SHADE, b * TINT_FILL_SHADE, TINT_FILL_ALPHA)
        self.Outline:SetVertexColor(r, g, b, TINT_OUTLINE_ALPHA)
        self.Text:SetTextColor(r, g, b)
    else
        self.Fill:SetVertexColor(FILL:GetRGBA())
        self.Outline:SetVertexColor(OUTLINE:GetRGBA())
        self.Text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    end

    self.Text:SetText(text)
    -- The text's full width, cut off ("...") where the badge would get wider than maxWidth.
    local textWidth = ceil(self.Text:GetUnboundedStringWidth())
    local maxTextWidth = self.maxWidth and self.maxWidth - 2 * TEXT_PADDING
    if maxTextWidth and textWidth > maxTextWidth then
        textWidth = maxTextWidth
    end
    self.Text:SetWidth(textWidth)
    self:SetWidth(max(BADGE_HEIGHT, textWidth + 2 * TEXT_PADDING))
    self:Show()
end

-- The widest the badge gets (in its own units, before its scale); nil for no limit.
function BadgeMixin:SetMaxWidth(width)
    self.maxWidth = width
end

function ns.CreateBadge(parent, scale)
    local badge = Mixin(CreateFrame("Frame", nil, parent), BadgeMixin)
    badge:SetScale(scale or 1)
    badge:SetHeight(BADGE_HEIGHT)
    badge.Fill = CreatePillTexture(badge, "BACKGROUND", "PillFill")
    badge.Outline = CreatePillTexture(badge, "BORDER", "PillBorder")
    badge.Text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badge.Text:SetPoint("CENTER", 0, 0)
    -- As tall as the badge (text centered in it), so descenders (y, g) aren't cut off.
    badge.Text:SetHeight(BADGE_HEIGHT)
    badge.Text:SetJustifyV("MIDDLE")
    badge.Text:SetTextScale(TEXT_SCALE)
    badge.Text:SetWordWrap(false)
    badge:Hide()
    return badge
end
