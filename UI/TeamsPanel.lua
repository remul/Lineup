local _, ns = ...
local Teams = ns.Teams

-- A panel docked to the right of the Collections window, shown with the Pet Journal tab.
-- Teams are listed under collapsible group headers.
local TeamsPanel = {}
ns.TeamsPanel = TeamsPanel

-- Same width as the Target window above it.
local PANEL_WIDTH = ns.TargetPanel.WIDTH
-- Blizzard draws a portrait window's left border 5px further out (NineSlice corner x -13) than a
-- window without portrait (-8). Widen this window to the left so its border lines up with Target.
local BORDER_ALIGN = 5
local HEADER_HEIGHT = 28
local ROW_HEIGHT = 64
local GROUP_SPACING = 8
-- Gap between a group header and its first team, and after its last team.
local GROUP_INNER_SPACING = 4
-- Width of the target text in the right column (clear of the pet icons on the left).
local RIGHT_COLUMN_WIDTH = 170
local EMPTY_GROUP_HEIGHT = 30
-- Team rows are indented under their group header.
local ROW_INDENT = 12
local PET_ICON_SIZE = 26
local PET_ICON_SPACING = 5
-- Pet icons sit indented under the team name so the two lines are easy to tell apart.
local PET_ICON_INDENT = 18
-- Downward chevron; rotated to point right for collapsed groups (plus/minus if the atlas is missing).
local CHEVRON_ATLAS = "uitools-icon-chevron-down"
local HAS_CHEVRON = C_Texture.GetAtlasInfo(CHEVRON_ATLAS) ~= nil
local UNGROUPED = 0

local TAB_TEAMS, TAB_QUEUE, TAB_ABOUT = 1, 2, 3
local TAB_TITLES = { "Teams", "Leveling Queue", "Lineup" }
-- Tab labels; the Lineup tab (info and settings) gets a gear icon.
local TAB_LABELS = { "Teams", "Leveling Queue", "|TInterface\\Buttons\\UI-OptionsButton:14:14|t Lineup" }

local panel, teamsView, queueView, aboutView, scrollBox, countText, emptyText, searchBox
local currentTab = TAB_TEAMS
local refreshPending = false

-- Sorts teams by name, lowercasing each name once instead of on every comparison.
local function SortTeamsByName(teams)
    local keys = {}
    for _, team in ipairs(teams) do
        keys[team] = team.name:lower()
    end
    table.sort(teams, function(a, b)
        return keys[a] < keys[b]
    end)
end

-- Group header (template: LineupGroupHeaderTemplate)
local GroupHeaderMixin = {}
_G.LineupGroupHeaderMixin = GroupHeaderMixin

function GroupHeaderMixin:OnLoad()
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- A warm band so headers stand apart from the team rows.
    self.Background = self:CreateTexture(nil, "BACKGROUND")
    self.Background:SetAllPoints()
    self.Background:SetColorTexture(1, 1, 1)
    self.Background:SetGradient("HORIZONTAL", CreateColor(0.32, 0.25, 0.10, 0.85), CreateColor(0.14, 0.11, 0.05, 0.45))
    self:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    -- Chevron pointing down when open, right when collapsed.
    self.ExpandIcon = self:CreateTexture(nil, "ARTWORK")
    self.ExpandIcon:SetSize(14, 14)
    self.ExpandIcon:SetPoint("LEFT", 6, 0)

    self.Icon = self:CreateTexture(nil, "ARTWORK")
    self.Icon:SetSize(20, 20)
    self.Icon:SetPoint("LEFT", self.ExpandIcon, "RIGHT", 6, 0)

    self.Name = self:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")

    self.Count = self:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    self.Count:SetPoint("LEFT", self.Name, "RIGHT", 6, 0)

    self.EditButton = CreateFrame("Button", nil, self)
    self.EditButton:SetSize(16, 16)
    self.EditButton:SetPoint("RIGHT", -6, 0)
    self.EditButton:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    self.EditButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    self.EditButton:SetScript("OnClick", function()
        self:ShowGroupMenu()
    end)
    self.EditButton:SetScript("OnEnter", function(button)
        self:UpdateEditButton()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Group options")
        GameTooltip:Show()
    end)
    self.EditButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
        self:UpdateEditButton()
    end)

    self:SetScript("OnEnter", self.UpdateEditButton)
    self:SetScript("OnLeave", self.UpdateEditButton)
end

-- Like on team rows, the gear is dimmed to keep the list calm, and in full colour while the group
-- is open or hovered.
function GroupHeaderMixin:UpdateEditButton()
    local active = (self.data and not self.data.collapsed) or self:IsMouseOver()
    local texture = self.EditButton:GetNormalTexture()
    texture:SetDesaturated(not active)
    texture:SetAlpha(active and 1 or 0.35)
end

function GroupHeaderMixin:Init(data)
    self.data = data
    local icon = data.group and data.group.icon
    self.Icon:SetTexture(icon)
    self.Icon:SetShown(icon ~= nil)
    self.Name:ClearAllPoints()
    self.Name:SetPoint("LEFT", icon and self.Icon or self.ExpandIcon, "RIGHT", 6, 0)
    self.Name:SetText(data.name)
    self.Count:SetFormattedText("(%d)", data.count)
    if HAS_CHEVRON then
        self.ExpandIcon:SetAtlas(CHEVRON_ATLAS)
        self.ExpandIcon:SetRotation(data.collapsed and math.pi / 2 or 0)
    else
        self.ExpandIcon:SetTexture(data.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    end
    self:UpdateEditButton()
end

-- Options for a group; the "Ungrouped" header (no group) only offers importing.
function GroupHeaderMixin:ShowGroupMenu()
    local group = self.data.group
    MenuUtil.CreateContextMenu(self.EditButton, function(_, root)
        root:CreateTitle(self.data.name)
        if group then
            root:CreateButton("Edit Group", function()
                ns.GroupEditor:Open(group)
            end)
        end
        root:CreateButton("Import Team", function()
            ns.ImportDialog:Open(group and group.id)
        end)
        if group then
            local groups = Teams:GetGroups()
            local index = tIndexOf(groups, group)
            root:CreateDivider()
            root:CreateButton("Move Up", function()
                Teams:MoveGroup(group, -1)
                TeamsPanel:Refresh()
            end):SetEnabled(index > 1)
            root:CreateButton("Move Down", function()
                Teams:MoveGroup(group, 1)
                TeamsPanel:Refresh()
            end):SetEnabled(index < #groups)
        end
    end)
end

function GroupHeaderMixin:OnClick(mouseButton)
    if mouseButton == "RightButton" then
        self:ShowGroupMenu()
        return
    end
    local groupID = self.data.group and self.data.group.id
    Teams:SetCollapsed(groupID, not self.data.collapsed)
    TeamsPanel:Refresh()
end

-- Team row (template: LineupTeamRowTemplate)
local TeamRowMixin = {}
_G.LineupTeamRowMixin = TeamRowMixin

-- "Zunta (Humanoid)" -> "Zunta", "Humanoid"; names without a trailing bracket are returned as is.
local function SplitTeamName(name)
    local base, tag = name:match("^(.-)%s*%((.-)%)%s*$")
    if base and base ~= "" then
        return base, tag
    end
    return name, nil
end

function TeamRowMixin:OnLoad()
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Everything visible sits on Inner, which is indented under group headers.
    self.Inner = CreateFrame("Frame", nil, self)
    self.Inner:SetPoint("BOTTOMRIGHT")
    local inner = self.Inner

    self.Background = inner:CreateTexture(nil, "BACKGROUND")
    self.Background:SetAllPoints()

    self.Hover = inner:CreateTexture(nil, "BACKGROUND", nil, 1)
    self.Hover:SetAllPoints()
    self.Hover:SetColorTexture(1, 1, 1, 0.08)
    self.Hover:Hide()

    -- Loaded team: a gold tint and a gold bar on the left.
    self.Selected = inner:CreateTexture(nil, "BORDER")
    self.Selected:SetAllPoints()
    self.Selected:SetColorTexture(1, 0.82, 0, 0.12)
    self.SelectedBar = inner:CreateTexture(nil, "BORDER", nil, 1)
    self.SelectedBar:SetPoint("TOPLEFT")
    self.SelectedBar:SetPoint("BOTTOMLEFT")
    self.SelectedBar:SetWidth(3)
    self.SelectedBar:SetColorTexture(1, 0.82, 0, 0.9)

    self.EditButton = CreateFrame("Button", nil, self)
    self.EditButton:SetSize(16, 16)
    self.EditButton:SetPoint("TOPRIGHT", -6, -8)
    self.EditButton:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    self.EditButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    self.EditButton:SetScript("OnClick", function()
        self:ShowTeamMenu()
    end)
    self.EditButton:SetScript("OnEnter", function(button)
        self:UpdateEditButton()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Team options")
        GameTooltip:Show()
    end)
    self.EditButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
        self:UpdateEditButton()
        if not self:IsMouseOver() then
            self.Hover:Hide()
        end
    end)

    -- Family tag from the team name, e.g. "Humanoid", lined up on the right.
    self.Tag = inner:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    self.Tag:SetPoint("RIGHT", self.EditButton, "LEFT", -6, 0)

    self.Name = inner:CreateFontString(nil, "ARTWORK", "GameFontHighlightMed2")
    self.Name:SetPoint("TOPLEFT", 10, -9)
    self.Name:SetPoint("RIGHT", self.Tag, "LEFT", -8, 0)
    self.Name:SetJustifyH("LEFT")
    self.Name:SetWordWrap(false)

    self.PetSlots = {}
    for slot = 1, 3 do
        local icon = inner:CreateTexture(nil, "ARTWORK")
        icon:SetSize(PET_ICON_SIZE, PET_ICON_SIZE)
        icon:SetPoint("BOTTOMLEFT", PET_ICON_INDENT + (slot - 1) * (PET_ICON_SIZE + PET_ICON_SPACING), 6)

        local border = inner:CreateTexture(nil, "OVERLAY")
        border:SetAllPoints(icon)
        border:SetTexture("Interface\\Common\\WhiteIconFrame")

        local level = inner:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        level:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)

        self.PetSlots[slot] = { Icon = icon, Border = border, Level = level }
    end

    -- Right column under the family tag: the target, and "Script" below it (both a bit smaller).
    self.Target = inner:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    self.Target:SetPoint("TOPRIGHT", self.Tag, "BOTTOMRIGHT", 0, -6)
    self.Target:SetWidth(RIGHT_COLUMN_WIDTH)
    self.Target:SetJustifyH("RIGHT")
    self.Target:SetWordWrap(false)
    self.Target:SetTextScale(0.9)

    self.Script = inner:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    self.Script:SetPoint("TOPRIGHT", self.Target, "BOTTOMRIGHT", 0, -2)
    self.Script:SetJustifyH("RIGHT")
    self.Script:SetTextScale(0.9)
    self.Script:SetText("Script")
end

function TeamRowMixin:Init(data)
    local team = data.team
    self.team = team

    self.Inner:SetPoint("TOPLEFT", data.indented and ROW_INDENT or 0, 0)
    self.Background:SetColorTexture(1, 1, 1, data.stripe and 0.05 or 0.02)
    local loaded = Teams:IsLoaded(team)
    self.loaded = loaded
    self.Selected:SetShown(loaded)
    self.SelectedBar:SetShown(loaded)
    self:UpdateEditButton()

    local displayName, tag = SplitTeamName(team.name)
    self.Name:SetText(displayName)
    local petType = tag and ns.FindFamilyByName(tag)
    if petType then
        self.Tag:SetText(format("|T%s:12:12|t %s", ns.GetFamilyIcon(petType), ns.GetFamilyColor(petType):WrapTextInColorCode(tag)))
    else
        self.Tag:SetText(tag and GRAY_FONT_COLOR:WrapTextInColorCode(tag) or "")
    end

    for slot, ui in ipairs(self.PetSlots) do
        local texture, _, level, missing, rarity = Teams.GetSlotDisplay(team.pets[slot])
        ui.Icon:SetTexture(texture)
        ui.Icon:SetDesaturated(missing)
        if rarity then
            ui.Border:SetVertexColor(ns.GetRarityColor(rarity))
        else
            ui.Border:SetVertexColor(0.5, 0.5, 0.5)
        end
        ui.Level:SetText(level and level < 25 and level or "")
        ui.Icon:SetShown(texture ~= nil)
        ui.Border:SetShown(texture ~= nil)
    end

    -- Target, green while you're targeting it.
    local target = ""
    if team.targetNpcID then
        target = "vs. " .. (team.targetName or ("NPC " .. team.targetNpcID))
        if ns.Target:IsCurrent(team.targetNpcID) then
            target = GREEN_FONT_COLOR:WrapTextInColorCode(target)
        end
    end
    self.Target:SetText(target)
    self.Script:SetShown(team.script ~= nil)
end

-- The gear is dimmed to keep the list calm, and in full colour while the row is hovered or loaded.
function TeamRowMixin:UpdateEditButton()
    local active = self.loaded or self:IsMouseOver()
    local texture = self.EditButton:GetNormalTexture()
    texture:SetDesaturated(not active)
    texture:SetAlpha(active and 1 or 0.35)
end

function TeamRowMixin:OnClick(mouseButton)
    if mouseButton == "RightButton" then
        self:ShowTeamMenu()
        return
    end
    Teams:Load(self.team)
end

function TeamRowMixin:ShowTeamMenu()
    local team = self.team
    MenuUtil.CreateContextMenu(self.EditButton, function(_, root)
        root:CreateTitle(team.name)
        root:CreateButton("Load Team", function()
            Teams:Load(team)
        end)
        root:CreateButton("Edit Team", function()
            ns.TeamEditor:Open(team)
        end)
        root:CreateButton("Pop Out Notes", function()
            ns.NotesWindow:Open(team)
        end):SetEnabled(ns.NotesWindow.HasContent(team))

        local moveTo = root:CreateButton("Move to Group")
        local function IsInGroup(groupID)
            return (team.groupID or 0) == groupID
        end
        local function MoveToGroup(groupID)
            team.groupID = groupID ~= 0 and groupID or nil
            TeamsPanel:Refresh()
        end
        moveTo:CreateRadio("Ungrouped", IsInGroup, MoveToGroup, 0)
        for _, group in ipairs(Teams:GetGroups()) do
            local label = group.icon and format("|T%s:16:16|t %s", group.icon, group.name) or group.name
            moveTo:CreateRadio(label, IsInGroup, MoveToGroup, group.id)
        end

        root:CreateDivider()
        root:CreateButton("Delete Team", function()
            ns.Dialogs.Confirm(format("Delete team \"%s\"?", team.name), function()
                Teams:Delete(team)
                TeamsPanel:Refresh()
            end)
        end)
    end)
end

function TeamRowMixin:OnEnter()
    self.Hover:Show()
    self:UpdateEditButton()
    local team = self.team
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(team.name)
    if team.targetNpcID then
        GameTooltip:AddLine("vs. " .. (team.targetName or ("NPC " .. team.targetNpcID)), 1, 0.82, 0)
    end
    for slot = 1, 3 do
        local _, name, level, missing = Teams.GetSlotDisplay(team.pets[slot])
        if missing then
            GameTooltip:AddLine(name, 1, 0.25, 0.25)
        elseif name then
            GameTooltip:AddDoubleLine(name, level and format("Level %d", level) or "", 1, 1, 1, 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Empty slot", 0.5, 0.5, 0.5)
        end
    end
    if team.script then
        local summary, color = ns.Script.Describe(team.script)
        GameTooltip:AddLine("Script: " .. summary, color:GetRGB())
    end
    if team.notes then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(team.notes, 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to load. Right-click for options.", 0, 1, 0)
    GameTooltip:Show()
end

function TeamRowMixin:OnLeave()
    GameTooltip:Hide()
    -- Moving onto the gear button counts as leaving the row; keep the hover then.
    if not self:IsMouseOver() then
        self.Hover:Hide()
    end
    self:UpdateEditButton()
end

-- Placeholder under an expanded group that has no teams. (Plain "Button" frames are only used
-- for these rows, so the scroll box pools them separately from spacers and templates.)
local function InitEmptyGroupRow(row)
    if not row.Text then
        row:EnableMouse(false)
        -- A fixed box (all four edges) so the text can wrap onto a second line.
        row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.Text:SetPoint("TOPLEFT", ROW_INDENT + 10, -2)
        row.Text:SetPoint("BOTTOMRIGHT", -8, 2)
        row.Text:SetJustifyH("LEFT")
        row.Text:SetJustifyV("MIDDLE")
        row.Text:SetWordWrap(true)
        row.Text:SetText("No teams in this group yet. Import one from the gear menu, or pick this group in a team's editor.")
    end
end

-- True if the team's name or target contains the (lowercase) search text.
local function TeamMatches(team, query)
    return team.name:lower():find(query, 1, true) ~= nil
        or (team.targetName and team.targetName:lower():find(query, 1, true) ~= nil)
end

-- List building: headers followed by their (sorted) teams unless collapsed, with a little space
-- between groups. Team rows alternate stripes within each group and are indented under headers.
-- With a search (lowercase query), only matching teams are listed (all teams of a group whose name
-- matches), groups without matches are left out, and the rest are shown open.
-- Returns the elements and the number of teams listed.
local function BuildElements(query)
    local groups = Teams:GetGroups()
    local groupExists = {}
    for _, group in ipairs(groups) do
        groupExists[group.id] = true
    end

    local teamsByGroup = {}
    for _, team in ipairs(Teams:GetAll()) do
        local key = groupExists[team.groupID] and team.groupID or UNGROUPED
        teamsByGroup[key] = teamsByGroup[key] or {}
        tinsert(teamsByGroup[key], team)
    end

    local function Filter(teams, groupName)
        if not query or (groupName and groupName:lower():find(query, 1, true)) then
            return teams
        end
        local matches = {}
        for _, team in ipairs(teams) do
            if TeamMatches(team, query) then
                matches[#matches + 1] = team
            end
        end
        return matches
    end

    local elements, numShown = {}, 0
    local function AddTeams(teams, indented)
        SortTeamsByName(teams)
        for index, team in ipairs(teams) do
            tinsert(elements, { team = team, indented = indented, stripe = index % 2 == 1 })
        end
        numShown = numShown + #teams
    end
    local function AddGroup(group, name, teams)
        if query and #teams == 0 then
            return
        end
        if #elements > 0 then
            tinsert(elements, { isSpacer = true, height = GROUP_SPACING })
        end
        local groupID = group and group.id
        -- While searching, groups with matches are shown open (without changing the saved state).
        local collapsed = not query and Teams:IsCollapsed(groupID)
        tinsert(elements, { isHeader = true, group = group, name = name, count = #teams, collapsed = collapsed })
        if not collapsed then
            tinsert(elements, { isSpacer = true, height = GROUP_INNER_SPACING })
            if #teams == 0 then
                tinsert(elements, { isEmpty = true })
            else
                AddTeams(teams, true)
            end
            tinsert(elements, { isSpacer = true, height = GROUP_INNER_SPACING })
        end
    end

    for _, group in ipairs(groups) do
        AddGroup(group, group.name, Filter(teamsByGroup[group.id] or {}, group.name))
    end

    local ungrouped = Filter(teamsByGroup[UNGROUPED] or {}, nil)
    if #groups == 0 then
        -- No groups yet: a plain list without headers.
        AddTeams(ungrouped, false)
    elseif #ungrouped > 0 then
        AddGroup(nil, "Ungrouped", ungrouped)
    end
    return elements, numShown
end

-- Panel
function TeamsPanel:Setup()
    panel = CreateFrame("Frame", "LineupTeamsPanel", PetJournal, "ButtonFrameTemplate")
    panel:SetPoint("TOPLEFT", CollectionsJournal, "TOPRIGHT", ns.TargetPanel.OFFSET_X - BORDER_ALIGN, -ns.TargetPanel.HEIGHT - 2)
    panel:SetPoint("BOTTOMLEFT", CollectionsJournal, "BOTTOMRIGHT", ns.TargetPanel.OFFSET_X - BORDER_ALIGN, 0)
    panel:SetWidth(PANEL_WIDTH + BORDER_ALIGN)
    ButtonFrameTemplate_HidePortrait(panel)
    panel.CloseButton:Hide()
    panel.Inset:Hide()

    -- Teams tab
    teamsView = CreateFrame("Frame", nil, panel)
    teamsView:SetAllPoints()

    local buttonsY = -30

    -- Three equal buttons across the top: New Team, New Group, Import.
    local buttonWidth = (PANEL_WIDTH + BORDER_ALIGN - 20 - 8) / 3
    local function CreateTopButton(index, text, onClick)
        local button = CreateFrame("Button", nil, teamsView, "UIPanelButtonTemplate")
        button:SetPoint("TOPLEFT", 10 + (index - 1) * (buttonWidth + 4), buttonsY)
        button:SetSize(buttonWidth, 24)
        button:SetText(text)
        button:SetScript("OnClick", onClick)
    end
    CreateTopButton(1, "New Team", function()
        ns.TeamEditor:Open(nil)
    end)
    CreateTopButton(2, "New Group", function()
        ns.GroupEditor:Open(nil)
    end)
    CreateTopButton(3, "Import", function()
        ns.ImportDialog:Open()
    end)

    -- Search (teams, targets and groups) and the Sort button for groups.
    local sortButton = CreateFrame("Button", nil, teamsView, "UIPanelButtonTemplate")
    sortButton:SetPoint("TOPRIGHT", -10, buttonsY - 30)
    sortButton:SetSize(70, 22)
    sortButton:SetText("Sort")
    sortButton:SetScript("OnClick", function()
        ns.GroupSorter:Open()
    end)
    sortButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText("Sort groups")
        GameTooltip:AddLine("Change the order of your groups.", 1, 1, 1)
        GameTooltip:Show()
    end)
    sortButton:SetScript("OnLeave", GameTooltip_Hide)

    searchBox = CreateFrame("EditBox", nil, teamsView, "SearchBoxTemplate")
    searchBox:SetPoint("TOPLEFT", 16, buttonsY - 30)
    searchBox:SetPoint("RIGHT", sortButton, "LEFT", -8, 0)
    searchBox:SetHeight(22)
    searchBox:SetAutoFocus(false)
    searchBox.Instructions:SetText("Search teams and groups")
    searchBox:HookScript("OnTextChanged", function()
        TeamsPanel:RefreshNow()
    end)

    local inset = CreateFrame("Frame", nil, teamsView, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 4, buttonsY - 58)
    inset:SetPoint("BOTTOMRIGHT", -6, 26)

    emptyText = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", 16, -16)
    emptyText:SetPoint("TOPRIGHT", -16, -16)

    scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", -20, 4)

    local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementFactory(function(factory, data)
        if data.isSpacer then
            factory("Frame", nop)
        elseif data.isEmpty then
            factory("Button", InitEmptyGroupRow)
        elseif data.isHeader then
            factory("LineupGroupHeaderTemplate", function(header, headerData)
                header:Init(headerData)
            end)
        else
            factory("LineupTeamRowTemplate", function(row, rowData)
                row:Init(rowData)
            end)
        end
    end)
    view:SetElementExtentCalculator(function(_, data)
        if data.isSpacer then
            return data.height
        elseif data.isEmpty then
            return EMPTY_GROUP_HEIGHT
        end
        return data.isHeader and HEADER_HEIGHT or ROW_HEIGHT
    end)
    view:SetPadding(0, 0, 0, 0, 2)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    countText = teamsView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("BOTTOMLEFT", 14, 8)

    -- Leveling Queue tab
    queueView = ns.QueueView:Create(panel)

    -- Lineup tab (about and settings)
    aboutView = ns.AboutView:Create(panel)

    -- Tabs along the bottom edge.
    panel.Tabs = {}
    for index, label in ipairs(TAB_LABELS) do
        local tab = CreateFrame("Button", "LineupTeamsPanelTab" .. index, panel, "PanelTabButtonTemplate")
        tab:SetID(index)
        tab:SetText(label)
        PanelTemplates_TabResize(tab, 0)
        tab:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            TeamsPanel:SelectTab(index)
        end)
        if index == 1 then
            tab:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 11, 2)
        else
            tab:SetPoint("LEFT", panel.Tabs[index - 1], "RIGHT", 3, 0)
        end
        panel.Tabs[index] = tab
    end
    PanelTemplates_SetNumTabs(panel, #panel.Tabs)

    panel:SetScript("OnShow", function()
        TeamsPanel:RefreshNow()
    end)
    self:SelectTab(TAB_TEAMS)
end

function TeamsPanel:SelectTab(tab)
    currentTab = tab
    PanelTemplates_SetTab(panel, tab)
    panel:SetTitle(TAB_TITLES[tab])
    teamsView:SetShown(tab == TAB_TEAMS)
    queueView:SetShown(tab == TAB_QUEUE)
    aboutView:SetShown(tab == TAB_ABOUT)
    self:RefreshNow()
end

function TeamsPanel:GetFrame()
    return panel
end

-- Asks for a redraw. Many things trigger one (journal updates, target changes, loads...), often
-- several in the same frame, so they're merged into a single redraw on the next frame.
function TeamsPanel:Refresh()
    if refreshPending then
        return
    end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        TeamsPanel:RefreshNow()
    end)
end

function TeamsPanel:RefreshNow()
    if not panel or not panel:IsVisible() then
        return
    end

    ns.TargetPanel:Refresh()
    -- Build the leveling queue up front (it scans the journal) rather than inside row setup.
    ns.LevelingQueue:Get()

    if currentTab == TAB_QUEUE then
        ns.QueueView:Refresh()
        return
    elseif currentTab == TAB_ABOUT then
        ns.AboutView:Refresh()
        return
    end

    local numTeams = #Teams:GetAll()
    local query = strtrim(searchBox:GetText()):lower()
    query = query ~= "" and query or nil
    local elements, numShown = BuildElements(query)
    scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)

    if query and #elements == 0 then
        emptyText:SetText(format("Nothing matches \"%s\".", strtrim(searchBox:GetText())))
        emptyText:Show()
    elseif not query and numTeams == 0 and #Teams:GetGroups() == 0 then
        emptyText:SetText("No teams yet.\n\nPick three pets in the journal, then click \"New Team\".")
        emptyText:Show()
    else
        emptyText:Hide()
    end

    if query then
        countText:SetFormattedText("%d of %d teams", numShown, numTeams)
    else
        countText:SetFormattedText(numTeams == 1 and "%d team" or "%d teams", numTeams)
    end
end
