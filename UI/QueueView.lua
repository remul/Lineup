local _, ns = ...
local L = ns.L

-- The "Leveling Queue" tab of the Lineup window: the automatic leveling queue with XP bars. With the
-- custom sort, rows can be dragged, or moved with their up / down arrows, into your own order.
local QueueView = {}
ns.QueueView = QueueView

local ROW_HEIGHT = 46

local view, scrollBox, countText, emptyText

local GetRarityColor = ns.GetRarityColor

-- Queue row (template: LineupQueueRowTemplate)
local QueueRowMixin = {}
_G.LineupQueueRowMixin = QueueRowMixin

function QueueRowMixin:OnLoad()
    self.Background = self:CreateTexture(nil, "BACKGROUND")
    self.Background:SetAllPoints()
    self.Background:SetAtlas("PetList-ButtonBackground")
    self:SetHighlightAtlas("PetList-ButtonHighlight")

    -- Custom sort: a drag grip before the icon (which moves over for it).
    self.Grip = ns.CreateDragGrip(self)
    self.Grip:SetPoint("LEFT", 8, 0)

    self.Icon = self:CreateTexture(nil, "ARTWORK")
    self.Icon:SetSize(34, 34)

    self.IconBorder = self:CreateTexture(nil, "OVERLAY")
    self.IconBorder:SetAllPoints(self.Icon)
    self.IconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")

    self.Position = self:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    self.Position:SetPoint("TOPLEFT", self.Icon, "TOPLEFT", 1, -1)

    self.Family = self:CreateTexture(nil, "ARTWORK")
    self.Family:SetSize(18, 18)
    self.Family:SetPoint("RIGHT", -8, 0)

    -- Custom sort: arrows left of the family icon.
    local function Move(delta)
        ns.LevelingQueue:Move(self.pet.petID, delta)
    end
    self.DownButton = ns.Dialogs.CreateArrowButton(self, 1, function()
        Move(1)
    end)
    self.DownButton:SetPoint("RIGHT", self.Family, "LEFT", -6, 0)
    self.UpButton = ns.Dialogs.CreateArrowButton(self, -1, function()
        Move(-1)
    end)
    self.UpButton:SetPoint("RIGHT", self.DownButton, "LEFT", 0, 0)

    self.Name = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.Name:SetPoint("TOPLEFT", self.Icon, "TOPRIGHT", 8, -2)
    self.Name:SetJustifyH("LEFT")
    self.Name:SetWordWrap(false)

    self.Level = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    self.Level:SetPoint("BOTTOMLEFT", self.Icon, "BOTTOMRIGHT", 8, 3)
    self.Level:SetWidth(52)
    self.Level:SetJustifyH("LEFT")

    self.XPBar = CreateFrame("StatusBar", nil, self)
    self.XPBar:SetPoint("LEFT", self.Level, "RIGHT", 2, 0)
    self.XPBar:SetHeight(8)
    self.XPBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    self.XPBar:SetStatusBarColor(0.58, 0.0, 0.55)
    self.XPBar.Background = self.XPBar:CreateTexture(nil, "BACKGROUND")
    self.XPBar.Background:SetAllPoints()
    self.XPBar.Background:SetColorTexture(0, 0, 0, 0.5)
end

function QueueRowMixin:Init(data)
    local pet = data.pet
    self.pet = pet
    local _, _, level, xp, maxXp, _, _, _, icon = C_PetJournal.GetPetInfoByPetID(pet.petID)
    self.xp, self.maxXp = xp or 0, maxXp or 1

    local r, g, b = GetRarityColor(pet.rarity)
    self.Icon:SetTexture(icon)
    self.IconBorder:SetVertexColor(r, g, b)
    self.Position:SetText(data.position)
    self.Name:SetText(pet.name)
    self.Name:SetTextColor(r, g, b)
    self.Level:SetFormattedText(L["Level %d"], level or pet.level)
    self.XPBar:SetMinMaxValues(0, self.maxXp)
    self.XPBar:SetValue(self.xp)
    self.Family:SetTexture(ns.GetFamilyIcon(pet.petType))

    -- The name and XP bar run up to the arrows (custom sort) or the family icon.
    local custom = data.custom
    self.Grip:SetShown(custom)
    self.Icon:SetPoint("LEFT", custom and 22 or 6, 0)
    self.UpButton:SetShown(custom)
    self.DownButton:SetShown(custom)
    self.UpButton:SetEnabled(data.position > 1)
    self.DownButton:SetEnabled(data.position < data.count)
    local rightEdge = custom and self.UpButton or self.Family
    self.Name:SetPoint("RIGHT", rightEdge, "LEFT", -6, 0)
    self.XPBar:SetPoint("RIGHT", rightEdge, "LEFT", -8, 0)
end

function QueueRowMixin:OnClick()
    ns:SelectPetInJournal(self.pet.petID)
end

function QueueRowMixin:OnEnter()
    local pet = self.pet
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(pet.name, GetRarityColor(pet.rarity))
    GameTooltip:AddLine(format(L["Level %d %s"], pet.level, ns.GetFamilyName(pet.petType)), 1, 1, 1)
    GameTooltip:AddLine(format(L["%d / %d XP"], self.xp, self.maxXp), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Your battle pets below level 25. Options sets whether duplicates and species you have at 25 are included."], 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(L["Leveling slots in your teams use the first pet that fits, in this order."], 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Click to show it in the Pet Journal."], 0, 1, 0)
    GameTooltip:Show()
end

function QueueRowMixin:OnLeave()
    GameTooltip:Hide()
end

-- Settings at the top of the tab, sunk in like the Teams tab's sections: the sort order on the
-- left (one radio button per order), which pets are included on the right.
local SETTING_ROW_HEIGHT = 18
local Settings = {}
Settings.HEIGHT = 16 + #ns.LevelingQueue.SORTS * SETTING_ROW_HEIGHT
-- [key] = radio button / checkbox, updated in QueueView:Refresh.
local sortRadios, optionChecks = {}, {}

local function CreateColumnTitle(parent, text)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetText(text)
    return title
end

-- A radio button with the Blizzard radio art, label on the right.
local function CreateRadio(parent, label)
    local radio = CreateFrame("CheckButton", nil, parent)
    radio:SetSize(16, 16)
    radio:SetNormalTexture("Interface\\Buttons\\UI-RadioButton")
    radio:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
    radio:SetCheckedTexture("Interface\\Buttons\\UI-RadioButton")
    radio:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
    radio:SetHighlightTexture("Interface\\Buttons\\UI-RadioButton", "ADD")
    radio:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
    radio.Label = radio:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    radio.Label:SetPoint("LEFT", radio, "RIGHT", 4, 0)
    radio.Label:SetText(label)
    -- The label is clickable too.
    radio:SetHitRectInsets(0, -(radio.Label:GetStringWidth() + 4), 0, 0)
    return radio
end

function Settings:Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(self.HEIGHT)

    local sortTitle = CreateColumnTitle(frame, L["Sort by"])
    sortTitle:SetPoint("TOPLEFT")
    local previous
    for _, sort in ipairs(ns.LevelingQueue.SORTS) do
        local radio = CreateRadio(frame, L[sort.label])
        if previous then
            radio:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, 16 - SETTING_ROW_HEIGHT)
        else
            radio:SetPoint("TOPLEFT", sortTitle, "BOTTOMLEFT", 0, -4)
        end
        radio:SetScript("OnClick", function()
            ns.LevelingQueue:SetSort(sort.key)
            QueueView:Refresh()
        end)
        sortRadios[sort.key] = radio
        previous = radio
    end

    local optionsTitle = CreateColumnTitle(frame, L["Options"])
    optionsTitle:SetPoint("TOPLEFT", frame, "TOP", 10, 0)
    previous = nil
    for _, option in ipairs({
        { key = "queueIncludeDuplicates", label = L["Include duplicates"] },
        { key = "queueIncludeMaxedSpecies", label = L["Include pets you have at 25"] },
    }) do
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check:SetSize(22, 22)
        if previous then
            check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
        else
            check:SetPoint("TOPLEFT", optionsTitle, "BOTTOMLEFT", -4, -1)
        end
        check.Label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        check.Label:SetPoint("LEFT", check, "RIGHT", 1, 0)
        check.Label:SetPoint("RIGHT", frame, "RIGHT")
        check.Label:SetJustifyH("LEFT")
        check.Label:SetText(option.label)
        check:SetScript("OnClick", function(button)
            ns.LevelingQueue:SetOption(option.key, button:GetChecked())
        end)
        optionChecks[option.key] = check
        previous = check
    end
    return frame
end

-- Builds the view inside parent (the Lineup window) and returns it; it starts hidden.
function QueueView:Create(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local settingsInset = ns.TeamsPanel.CreateSectionInset(view, Settings)

    local inset = CreateFrame("Frame", nil, view, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", settingsInset, "BOTTOMLEFT", 0, -ns.TeamsPanel.INSET_GAP)
    inset:SetPoint("BOTTOMRIGHT", ns.TeamsPanel.INSET_RIGHT, 26)

    emptyText = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", 16, -16)
    emptyText:SetPoint("TOPRIGHT", -16, -16)
    emptyText:SetText(L["Nothing to level.\n\nNo battle pets below level 25 match your queue options."])

    local listView = CreateScrollBoxListLinearView()
    listView:SetElementExtent(ROW_HEIGHT)
    listView:SetElementInitializer("LineupQueueRowTemplate", function(row, data)
        row:Init(data)
    end)
    listView:SetPadding(0, 0, 0, 0, 2)
    scrollBox = ns.CreateScrollList(inset, listView)
    -- Dragging rows sets the custom order (and only works with that sort).
    ns.AddDragReorder(scrollBox, function()
        return ns.LevelingQueue:IsCustomSort()
    end, function(entries)
        local petIDs = {}
        for index, data in ipairs(entries) do
            petIDs[index] = data.pet.petID
        end
        ns.LevelingQueue:SetCustomOrder(petIDs)
    end)

    countText = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("BOTTOMLEFT", 14, 8)

    return view
end

function QueueView:Refresh()
    if not view or not view:IsVisible() then
        return
    end
    local sortKey = ns.LevelingQueue:GetSort()
    for key, radio in pairs(sortRadios) do
        radio:SetChecked(key == sortKey)
    end
    for key, check in pairs(optionChecks) do
        check:SetChecked(ns.LevelingQueue:GetOption(key) and true or false)
    end

    local pets = ns.LevelingQueue:Get()
    local custom = ns.LevelingQueue:IsCustomSort()
    local elements = {}
    for position, pet in ipairs(pets) do
        elements[position] = { pet = pet, position = position, count = #pets, custom = custom }
    end
    scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)
    emptyText:SetShown(#elements == 0)
    countText:SetFormattedText(#elements == 1 and L["%d pet to level"] or L["%d pets to level"], #elements)
end
