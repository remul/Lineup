local _, ns = ...
local L = ns.L

-- The "Leveling Queue" tab of the Teams window: the automatic leveling queue with XP bars.
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

    self.Icon = self:CreateTexture(nil, "ARTWORK")
    self.Icon:SetSize(34, 34)
    self.Icon:SetPoint("LEFT", 6, 0)

    self.IconBorder = self:CreateTexture(nil, "OVERLAY")
    self.IconBorder:SetAllPoints(self.Icon)
    self.IconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")

    self.Position = self:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    self.Position:SetPoint("TOPLEFT", self.Icon, "TOPLEFT", 1, -1)

    self.Family = self:CreateTexture(nil, "ARTWORK")
    self.Family:SetSize(18, 18)
    self.Family:SetPoint("RIGHT", -8, 0)

    self.Name = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.Name:SetPoint("TOPLEFT", self.Icon, "TOPRIGHT", 8, -2)
    self.Name:SetPoint("RIGHT", self.Family, "LEFT", -6, 0)
    self.Name:SetJustifyH("LEFT")
    self.Name:SetWordWrap(false)

    self.Level = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    self.Level:SetPoint("BOTTOMLEFT", self.Icon, "BOTTOMRIGHT", 8, 3)
    self.Level:SetWidth(52)
    self.Level:SetJustifyH("LEFT")

    self.XPBar = CreateFrame("StatusBar", nil, self)
    self.XPBar:SetPoint("LEFT", self.Level, "RIGHT", 2, 0)
    self.XPBar:SetPoint("RIGHT", self.Family, "LEFT", -8, 0)
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
    GameTooltip:AddLine(L["The queue lists your battle pets below level 25 automatically; Options decides whether duplicates and pets you already have at 25 are included."], 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(L["Leveling slots in your teams use the first pet that fits, in this order."], 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Click to show it in the Pet Journal."], 0, 1, 0)
    GameTooltip:Show()
end

function QueueRowMixin:OnLeave()
    GameTooltip:Hide()
end

-- Builds the view inside parent (the Teams window) and returns it; it starts hidden.
function QueueView:Create(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local sortLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sortLabel:SetPoint("TOPLEFT", 14, -38)
    sortLabel:SetText(L["Sort by"])

    -- Options: which pets the queue includes.
    local optionsDropdown = CreateFrame("DropdownButton", nil, view, "WowStyle1DropdownTemplate")
    optionsDropdown:SetPoint("TOPRIGHT", -12, -30)
    optionsDropdown:SetWidth(100)
    optionsDropdown:SetDefaultText(L["Options"])
    -- Keep the label "Options" instead of listing the ticked entries.
    if optionsDropdown.SetSelectionText then
        optionsDropdown:SetSelectionText(function()
            return L["Options"]
        end)
    end
    optionsDropdown:SetupMenu(function(_, root)
        local function IsChecked(key)
            return ns.LevelingQueue:GetOption(key)
        end
        local function Toggle(key)
            ns.LevelingQueue:SetOption(key, not ns.LevelingQueue:GetOption(key))
        end
        root:CreateCheckbox(L["Include duplicates"], IsChecked, Toggle, "queueIncludeDuplicates")
        root:CreateCheckbox(L["Include pets you have at 25"], IsChecked, Toggle, "queueIncludeMaxedSpecies")
    end)

    local sortDropdown = CreateFrame("DropdownButton", nil, view, "WowStyle1DropdownTemplate")
    sortDropdown:SetPoint("LEFT", sortLabel, "RIGHT", 8, 0)
    sortDropdown:SetPoint("RIGHT", optionsDropdown, "LEFT", -6, 0)
    sortDropdown:SetupMenu(function(_, root)
        local function IsSelected(key)
            return ns.LevelingQueue:GetSort() == key
        end
        local function SetSelected(key)
            ns.LevelingQueue:SetSort(key)
        end
        for _, sort in ipairs(ns.LevelingQueue.SORTS) do
            root:CreateRadio(sort.label, IsSelected, SetSelected, sort.key)
        end
    end)

    local inset = CreateFrame("Frame", nil, view, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 4, -60)
    inset:SetPoint("BOTTOMRIGHT", -6, 26)

    emptyText = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", 16, -16)
    emptyText:SetPoint("TOPRIGHT", -16, -16)
    emptyText:SetText(L["Nothing to level.\n\nNo battle pets below level 25 match your queue options."])

    scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", -20, 4)

    local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    local listView = CreateScrollBoxListLinearView()
    listView:SetElementExtent(ROW_HEIGHT)
    listView:SetElementInitializer("LineupQueueRowTemplate", function(row, data)
        row:Init(data)
    end)
    listView:SetPadding(0, 0, 0, 0, 2)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, listView)

    countText = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("BOTTOMLEFT", 14, 8)

    return view
end

function QueueView:Refresh()
    if not view or not view:IsVisible() then
        return
    end
    local elements = {}
    for position, pet in ipairs(ns.LevelingQueue:Get()) do
        elements[position] = { pet = pet, position = position }
    end
    scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)
    emptyText:SetShown(#elements == 0)
    countText:SetFormattedText(#elements == 1 and L["%d pet to level"] or L["%d pets to level"], #elements)
end
