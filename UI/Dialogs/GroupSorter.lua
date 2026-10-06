local _, ns = ...
local Teams = ns.Teams

-- Window to put groups in order: up/down per group, or A-Z. Changes apply right away.
local GroupSorter = {}
ns.GroupSorter = GroupSorter

local WINDOW_WIDTH = 320
local WINDOW_HEIGHT = 420
local ROW_HEIGHT = 30

local window, scrollBox, emptyText

local function Refresh()
    local groups = Teams:GetGroups()
    local elements = {}
    for index, group in ipairs(groups) do
        elements[index] = { group = group, index = index, count = #groups }
    end
    scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)
    emptyText:SetShown(#groups == 0)
end

local function Move(group, delta)
    Teams:MoveGroup(group, delta)
    Refresh()
    ns.TeamsPanel:Refresh()
end

local function CreateArrowButton(row, texturePrefix, delta)
    local button = CreateFrame("Button", nil, row)
    button:SetSize(24, 24)
    button:SetNormalTexture(texturePrefix .. "-Up")
    button:SetPushedTexture(texturePrefix .. "-Down")
    button:SetDisabledTexture(texturePrefix .. "-Disabled")
    button:SetHighlightTexture(texturePrefix .. "-Highlight", "ADD")
    button:SetScript("OnClick", function()
        Move(row.group, delta)
    end)
    return button
end

-- Group row (template: LineupGroupSortRowTemplate)
local GroupSortRowMixin = {}
_G.LineupGroupSortRowMixin = GroupSortRowMixin

function GroupSortRowMixin:OnLoad()
    self.Background = self:CreateTexture(nil, "BACKGROUND")
    self.Background:SetAllPoints()

    self.DownButton = CreateArrowButton(self, "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton", 1)
    self.DownButton:SetPoint("RIGHT", -4, 0)
    self.UpButton = CreateArrowButton(self, "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton", -1)
    self.UpButton:SetPoint("RIGHT", self.DownButton, "LEFT", 0, 0)

    self.Position = self:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    self.Position:SetPoint("LEFT", 8, 0)
    self.Position:SetWidth(18)
    self.Position:SetJustifyH("RIGHT")

    self.Icon = self:CreateTexture(nil, "ARTWORK")
    self.Icon:SetSize(20, 20)
    self.Icon:SetPoint("LEFT", self.Position, "RIGHT", 8, 0)

    self.Name = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.Name:SetPoint("LEFT", self.Icon, "RIGHT", 8, 0)
    self.Name:SetPoint("RIGHT", self.UpButton, "LEFT", -6, 0)
    self.Name:SetJustifyH("LEFT")
    self.Name:SetWordWrap(false)
end

function GroupSortRowMixin:Init(data)
    self.group = data.group
    self.Background:SetColorTexture(1, 1, 1, data.index % 2 == 1 and 0.05 or 0.02)
    self.Position:SetText(data.index)
    self.Icon:SetTexture(data.group.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    self.Icon:SetDesaturated(data.group.icon == nil)
    self.Name:SetText(data.group.name)
    self.UpButton:SetEnabled(data.index > 1)
    self.DownButton:SetEnabled(data.index < data.count)
end

local function CreateWindow()
    window = CreateFrame("Frame", "LineupGroupSorter", UIParent, "ButtonFrameTemplate")
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    ButtonFrameTemplate_HidePortrait(window)
    window:SetTitle("Sort Groups")
    tinsert(UISpecialFrames, window:GetName())

    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 16, -32)
    hint:SetPoint("RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Use the arrows to move a group. \"Ungrouped\" always comes last.")

    local inset = window.Inset
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", 4, -52)
    inset:SetPoint("BOTTOMRIGHT", -6, 34)

    emptyText = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", 16, -16)
    emptyText:SetPoint("TOPRIGHT", -16, -16)
    emptyText:SetText("No groups yet.")

    scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", -20, 4)

    local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("LineupGroupSortRowTemplate", function(row, data)
        row:Init(data)
    end)
    view:SetPadding(0, 0, 0, 0, 2)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    local doneButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    doneButton:SetPoint("BOTTOMRIGHT", -8, 6)
    doneButton:SetSize(90, 22)
    doneButton:SetText(DONE)
    doneButton:SetScript("OnClick", function()
        window:Hide()
    end)

    local alphabeticalButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    alphabeticalButton:SetPoint("BOTTOMLEFT", 8, 6)
    alphabeticalButton:SetSize(110, 22)
    alphabeticalButton:SetText("Sort A-Z")
    alphabeticalButton:SetScript("OnClick", function()
        Teams:SortGroupsByName()
        Refresh()
        ns.TeamsPanel:Refresh()
    end)
end

function GroupSorter:Open()
    if not window then
        CreateWindow()
    end
    Refresh()

    local teamsPanel = ns.TeamsPanel:GetFrame()
    window:ClearAllPoints()
    if teamsPanel and teamsPanel:IsVisible() then
        window:SetPoint("TOPLEFT", teamsPanel, "TOPRIGHT", 4, 0)
    else
        window:SetPoint("CENTER")
    end
    window:Show()
    window:Raise()
end
