local _, ns = ...
local L = ns.L
local Teams = ns.Teams

-- Window to put groups in order: drag them, use up/down per group, or A-Z. Changes apply right away.
local GroupSorter = {}
ns.GroupSorter = GroupSorter

local EXTRA_LEFT = ns.Dialogs.LEFT_BORDER_EXTRA
local WINDOW_WIDTH = 320 + EXTRA_LEFT
local WINDOW_HEIGHT = 420
-- Rows are cards like the group headers in the Lineup window, this far apart, with room around
-- the list like the Lineup window's (above the first, below the last and at the sides).
local ROW_HEIGHT = 28
local ROW_SPACING = 8
local LIST_PADDING = 8

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

local function CreateArrowButton(row, delta)
    return ns.Dialogs.CreateArrowButton(row, delta, function()
        Move(row.group, delta)
    end)
end

-- Group row (template: LineupPetBattlesGroupSortRowTemplate)
local GroupSortRowMixin = {}
_G.LineupPetBattlesGroupSortRowMixin = GroupSortRowMixin

-- A card like a group header in the Lineup window: a drag grip where the header has its chevron,
-- the group's icon, name and team count, and up / down arrows where it has its gear.
function GroupSortRowMixin:OnLoad()
    self.Background = ns.CreateCardFill(self)
    self.Outline = ns.CreateCardOutline(self)

    self.Grip = ns.CreateDragGrip(self)
    self.Grip:SetPoint("LEFT", 10, 0)

    self.DownButton = CreateArrowButton(self, 1)
    self.DownButton:SetPoint("RIGHT", -2, 0)
    self.UpButton = CreateArrowButton(self, -1)
    self.UpButton:SetPoint("RIGHT", self.DownButton, "LEFT", 0, 0)

    self.Icon = self:CreateTexture(nil, "ARTWORK")
    self.Icon:SetSize(20, 20)
    self.Icon:SetPoint("LEFT", self.Grip, "RIGHT", 10, 0)

    self.Name = self:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
    self.Name:SetJustifyH("LEFT")
    self.Name:SetWordWrap(false)

    self.Count = self:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    self.Count:SetTextColor(ns.MUTED_COLOR:GetRGB())
    self.Count:SetPoint("LEFT", self.Name, "RIGHT", 6, 0)

    -- The outline brightens while hovered, also over the arrows.
    local function UpdateOutline()
        ns.UpdateCardOutline(self.Outline, false, self:IsMouseOver())
    end
    self:SetScript("OnEnter", UpdateOutline)
    self:SetScript("OnLeave", UpdateOutline)
    for _, button in ipairs({ self.UpButton, self.DownButton }) do
        button:HookScript("OnEnter", UpdateOutline)
        button:HookScript("OnLeave", UpdateOutline)
    end
end

function GroupSortRowMixin:Init(data)
    local group = data.group
    self.group = group
    -- Like the header: the icon when the group has one, else the name right after the grip.
    ns.IconPicker.SetIconTexture(self.Icon, group.icon, 20)
    self.Icon:SetShown(group.icon ~= nil)
    local nameAnchor = group.icon and self.Icon or self.Grip
    self.Name:ClearAllPoints()
    self.Name:SetPoint("LEFT", nameAnchor, "RIGHT", group.icon and 6 or 10, 0)
    self.Name:SetText(group.name)
    self.Count:SetFormattedText("(%d)", #Teams:GetGroupTeams(group))
    -- The count follows the name; a long name is cut short to leave room for it and the arrows.
    local room = self.UpButton:GetLeft() and nameAnchor:GetRight()
        and self.UpButton:GetLeft() - nameAnchor:GetRight() - 6 - 6 - self.Count:GetUnboundedStringWidth() - 6
    local width = self.Name:GetUnboundedStringWidth()
    self.Name:SetWidth(room and min(width, max(room, 1)) or width)
    self.UpButton:SetEnabled(data.index > 1)
    self.DownButton:SetEnabled(data.index < data.count)
    ns.UpdateCardOutline(self.Outline, false, self:IsMouseOver())
end

local function CreateWindow()
    window = ns.Dialogs.CreateWindow("LineupPetBattlesGroupSorter", WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetTitle(L["Sort Groups"])

    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 16 + EXTRA_LEFT, -32)
    -- A set width (rather than a right anchor) so the hint's height covers every wrapped line; the
    -- list below is anchored to its bottom.
    hint:SetWidth(WINDOW_WIDTH - 32 - EXTRA_LEFT)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText(L["Drag a group or use its arrows to move it. \"Ungrouped\" always comes last."])

    local inset = window.Inset
    inset:ClearAllPoints()
    -- Below the hint (one or two lines, depending on the language), with some room under it.
    inset:SetPoint("TOP", hint, "BOTTOM", 0, -10)
    inset:SetPoint("LEFT", 6 + EXTRA_LEFT, 0)
    inset:SetPoint("BOTTOMRIGHT", -6, 34)

    emptyText = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetTextColor(ns.MUTED_COLOR:GetRGB())
    emptyText:SetPoint("TOPLEFT", 16, -16)
    emptyText:SetPoint("TOPRIGHT", -16, -16)
    emptyText:SetText(L["No groups yet"])

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("LineupPetBattlesGroupSortRowTemplate", function(row, data)
        row:Init(data)
    end)
    view:SetPadding(LIST_PADDING, LIST_PADDING, LIST_PADDING, LIST_PADDING, ROW_SPACING)
    scrollBox = ns.CreateScrollList(inset, view)
    ns.AddDragReorder(scrollBox, nil, function(entries)
        local groups = {}
        for index, data in ipairs(entries) do
            groups[index] = data.group
        end
        Teams:SetGroupOrder(groups)
        Refresh()
        ns.TeamsPanel:Refresh()
    end)

    local doneButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    doneButton:SetPoint("BOTTOMRIGHT", -8, 6)
    doneButton:SetSize(90, 22)
    doneButton:SetText(DONE)
    doneButton:SetScript("OnClick", function()
        window:Hide()
    end)

    local alphabeticalButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    alphabeticalButton:SetPoint("BOTTOMLEFT", 8 + EXTRA_LEFT, 6)
    alphabeticalButton:SetSize(110, 22)
    alphabeticalButton:SetText(L["Sort A-Z"])
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

    ns.Dialogs.PlaceWindow(window)
    window:Show()
    window:Raise()
end
