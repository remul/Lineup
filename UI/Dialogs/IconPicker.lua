local _, ns = ...
local L = ns.L

-- An embeddable icon chooser. Without a search it lists pet family icons, expansion logos and then
-- every macro/item icon in the game. Icons have no names in the API, so search matches pet families,
-- expansions, pet species and pet abilities by name; an icon file ID or file name can be typed in
-- as well.
local IconPicker = {}
ns.IconPicker = IconPicker

local STRIDE = 8
local ICON_SPACING = 4
local MAX_SPECIES_ID = 6000
local MAX_ABILITY_ID = 4000

-- Elements are { icon = fileID or path, label = "Pet: ..." (optional) }.
local allIcons, namedIcons

local function GetFamilyIcons()
    local result = {}
    for petType = 1, ns.NUM_FAMILIES do
        local name = ns.GetFamilyName(petType)
        result[petType] = { icon = ns.GetFamilyIcon(petType), label = L["Family: "] .. name, search = name:lower() }
    end
    return result
end

-- Expansion logos, Classic to the current one: entries like the families', and [fileID] = true to
-- tell them apart from square icons (see SetIconTexture).
local expansionIcons, isLogo

local function GetExpansionIcons()
    if not expansionIcons then
        expansionIcons, isLogo = {}, {}
        for level = 0, GetServerExpansionLevel() do
            local info = GetExpansionDisplayInfo(level)
            local name = _G["EXPANSION_NAME" .. level]
            if info and info.logo and name then
                expansionIcons[#expansionIcons + 1] = { icon = info.logo, label = L["Expansion: "] .. name, search = name:lower() }
                isLogo[info.logo] = true
            end
        end
    end
    return expansionIcons
end

-- Logos are about twice as wide as tall, so they're shown at full width and half height.
function IconPicker.IsLogo(icon)
    GetExpansionIcons()
    return icon ~= nil and isLogo[icon] == true
end

-- Shows icon on texture (anchored by one point) within a size x size square, keeping a logo's shape.
function IconPicker.SetIconTexture(texture, icon, size)
    texture:SetTexture(icon)
    texture:SetSize(size, IconPicker.IsLogo(icon) and size / 2 or size)
end

-- The icon as inline text, e.g. for menus.
function IconPicker.FormatIcon(icon, size)
    return format("|T%s:%d:%d|t", icon, IconPicker.IsLogo(icon) and size / 2 or size, size)
end

local function GetAllIcons()
    if allIcons then
        return allIcons
    end
    allIcons = GetFamilyIcons()
    for _, entry in ipairs(GetExpansionIcons()) do
        allIcons[#allIcons + 1] = entry
    end
    local fileIDs = {}
    for _, fill in ipairs({ GetMacroIcons, GetMacroItemIcons }) do
        if fill then
            fill(fileIDs)
        end
    end
    for _, fileID in ipairs(fileIDs) do
        allIcons[#allIcons + 1] = { icon = fileID }
    end
    return allIcons
end

-- Built on the first search: every pet species and pet ability with its icon.
local function GetNamedIcons()
    if namedIcons then
        return namedIcons
    end
    -- Only cache the list once it's complete.
    local list = GetFamilyIcons()
    for _, entry in ipairs(GetExpansionIcons()) do
        list[#list + 1] = entry
    end
    for speciesID = 1, MAX_SPECIES_ID do
        local name, icon = ns.GetSpeciesInfo(speciesID)
        if name and icon then
            list[#list + 1] = { icon = icon, label = L["Pet: "] .. name, search = name:lower() }
        end
    end
    for abilityID = 1, MAX_ABILITY_ID do
        local name, icon = C_PetJournal.GetPetAbilityInfo(abilityID)
        if type(name) == "string" and icon then
            list[#list + 1] = { icon = icon, label = L["Ability: "] .. name, search = name:lower() }
        end
    end
    namedIcons = list
    return namedIcons
end

-- A typed file ID ("132599") or icon file name ("INV_Misc_Bag_08") or path, if the text looks like one.
local function ParseIconText(text)
    if tonumber(text) then
        return tonumber(text)
    end
    if text:find("\\") then
        return text
    end
    if text:find("_") and not text:find("%s") then
        return "Interface\\Icons\\" .. text
    end
end

local function Search(text)
    text = strtrim(text)
    if text == "" then
        return GetAllIcons()
    end

    local results, seen = {}, {}
    local typedIcon = ParseIconText(text)
    if typedIcon then
        results[1] = { icon = typedIcon, label = L["Icon: "] .. text }
        seen[typedIcon] = true
    end

    local query = text:lower()
    for _, entry in ipairs(GetNamedIcons()) do
        if not seen[entry.icon] and entry.search:find(query, 1, true) then
            seen[entry.icon] = true
            results[#results + 1] = entry
        end
    end
    return results
end

-- Icon button (template: LineupPetBattlesIconButtonTemplate)
local IconButtonMixin = {}
_G.LineupPetBattlesIconButtonMixin = IconButtonMixin

function IconButtonMixin:OnLoad()
    self.Icon = self:CreateTexture(nil, "ARTWORK")
    self.Icon:SetPoint("CENTER")

    self.Selected = self:CreateTexture(nil, "OVERLAY")
    self.Selected:SetPoint("TOPLEFT", -4, 4)
    self.Selected:SetPoint("BOTTOMRIGHT", 4, -4)
    self.Selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    self.Selected:SetBlendMode("ADD")

    self:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
end

function IconButtonMixin:Init(entry, picker)
    self.entry = entry
    self.picker = picker
    IconPicker.SetIconTexture(self.Icon, entry.icon, self:GetWidth())
    self.Selected:SetShown(entry.icon == picker.selected)
end

function IconButtonMixin:OnClick()
    self.picker:Select(self.entry.icon)
end

function IconButtonMixin:OnEnter()
    if self.entry.label then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.entry.label)
        GameTooltip:Show()
    end
end

function IconButtonMixin:OnLeave()
    GameTooltip:Hide()
end

-- Picker frame methods
local PickerMixin = {}

function PickerMixin:SetSelected(icon)
    self.selected = icon
    self.ScrollBox:ForEachFrame(function(button)
        button.Selected:SetShown(button.entry.icon == icon)
    end)
end

function PickerMixin:Select(icon)
    self:SetSelected(icon)
    self.onSelect(icon)
end

function PickerMixin:ClearSearch()
    self.SearchBox:SetText("")
end

function PickerMixin:Refresh()
    local results = Search(self.SearchBox:GetText())
    self.results = results
    self.ScrollBox:SetDataProvider(CreateDataProvider(results))
    self.NoResults:SetShown(#results == 0)
end

-- Creates the picker inside parent; onSelect(icon) receives a fileID, a path, or nil for no icon.
function IconPicker.Create(parent, onSelect)
    local picker = Mixin(CreateFrame("Frame", nil, parent), PickerMixin)
    picker.onSelect = onSelect

    local searchBox = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
    searchBox:SetPoint("TOPLEFT", 6, 0)
    searchBox:SetPoint("RIGHT", -92, 0)
    searchBox:SetHeight(24)
    searchBox:SetAutoFocus(false)
    searchBox.Instructions:SetText(L["Pet, ability, or icon ID"])
    searchBox:HookScript("OnTextChanged", function()
        picker:Refresh()
    end)
    -- Enter picks the first result (handy for a typed icon ID).
    searchBox:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
        local first = picker.results and picker.results[1]
        if first and strtrim(box:GetText()) ~= "" then
            picker:Select(first.icon)
        end
    end)
    picker.SearchBox = searchBox

    local noIconButton = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    noIconButton:SetPoint("TOPRIGHT", 0, 0)
    noIconButton:SetSize(80, 24)
    noIconButton:SetText(NONE)
    noIconButton:SetScript("OnClick", function()
        picker:Select(nil)
    end)

    local inset = CreateFrame("Frame", nil, picker, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 0, -30)
    inset:SetPoint("BOTTOMRIGHT")

    local view = CreateScrollBoxListGridView(STRIDE, 0, 0, 0, 0, ICON_SPACING, ICON_SPACING)
    view:SetElementInitializer("LineupPetBattlesIconButtonTemplate", function(button, entry)
        button:Init(entry, picker)
    end)
    picker.ScrollBox = ns.CreateScrollList(inset, view, 6)

    picker.NoResults = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    picker.NoResults:SetTextColor(ns.MUTED_COLOR:GetRGB())
    picker.NoResults:SetPoint("TOP", 0, -24)
    picker.NoResults:SetText(L["No icons found"])

    picker:Refresh()
    return picker
end

-- Width the picker needs to fit a full row of icons.
IconPicker.WIDTH = STRIDE * (36 + ICON_SPACING) + 34
