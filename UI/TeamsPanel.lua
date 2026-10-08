local _, ns = ...
local L = ns.L
local Teams = ns.Teams

-- The Lineup window, docked to the right of the Collections window and shown with the Pet Journal
-- tab. Its Teams tab is split into sections: Target (see TargetSection), Current (the loaded team
-- and loadout, see CurrentSection) and the team list, where teams are listed under collapsible
-- group headers. The Leveling Queue and Settings tabs use the whole window.
local TeamsPanel = {}
ns.TeamsPanel = TeamsPanel

local WINDOW_WIDTH = 400
-- Gap to the Collections window.
local WINDOW_OFFSET_X = 9
-- Sections are sunk into the window like the Pet Journal's insets, with their content padded
-- inside. The gaps between them hold the buttons. The window's left border sits further in than
-- its right one, so the left offset is larger to leave the same strip of frame on both sides.
local INSET_LEFT, INSET_RIGHT = 6 + ns.Dialogs.LEFT_BORDER_EXTRA, -6
local INSET_TOP = -26
local INSET_GAP = 4
TeamsPanel.INSET_LEFT, TeamsPanel.INSET_RIGHT, TeamsPanel.INSET_GAP = INSET_LEFT, INSET_RIGHT, INSET_GAP
local SECTION_PADDING = 8
-- Window edge to section content.
TeamsPanel.SECTION_INSET = INSET_LEFT + SECTION_PADDING
local HEADER_HEIGHT = 28
local ROW_HEIGHT = 64
-- Space between team cards.
local CARD_GAP = 4
local GROUP_SPACING = 8
-- Gap between a group header and its first team, and after its last team.
local GROUP_INNER_SPACING = 4
-- Width of the target text in the right column (clear of the pet icons on the left).
local RIGHT_COLUMN_WIDTH = 170
local EMPTY_GROUP_HEIGHT = 36
-- Team rows are indented under their group header.
local ROW_INDENT = 12
local PET_ICON_SIZE = 26
local PET_ICON_SPACING = 5
-- Pet icons sit indented under the team name so the two lines are easy to tell apart.
local PET_ICON_INDENT = 18
-- Downward chevron; rotated to point right for collapsed groups (plus/minus if the atlas is missing).
local CHEVRON_ATLAS = "uitools-icon-chevron-down"
local LOADED_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local HAS_CHEVRON = C_Texture.GetAtlasInfo(CHEVRON_ATLAS) ~= nil
local UNGROUPED = 0

local TAB_TEAMS, TAB_QUEUE, TAB_ABOUT = 1, 2, 3
local TAB_LABELS = { L["Teams"], L["Leveling Queue"], L["Settings"] }

local panel, teamsView, queueView, aboutView, scrollBox, countText, emptyText, searchBox, expandAllButton
local currentTab = TAB_TEAMS
local refreshPending = false

-- An inset across the window's width, below anchor (or at the top), holding the section created
-- by module (e.g. TargetSection: module.HEIGHT and module:Create(parent)) with padding around it.
local function CreateSectionInset(parent, module, anchor)
    local inset = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    if anchor then
        inset:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -INSET_GAP)
        inset:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -INSET_GAP)
    else
        inset:SetPoint("TOPLEFT", INSET_LEFT, INSET_TOP)
        inset:SetPoint("TOPRIGHT", INSET_RIGHT, INSET_TOP)
    end
    inset:SetHeight(module.HEIGHT + 2 * SECTION_PADDING)

    local section = module:Create(inset)
    section:SetPoint("TOPLEFT", SECTION_PADDING, -SECTION_PADDING)
    section:SetPoint("TOPRIGHT", -SECTION_PADDING, -SECTION_PADDING)
    return inset
end
TeamsPanel.CreateSectionInset = CreateSectionInset

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

-- Points the chevron down when open, right when collapsed (plus / minus without the atlas).
local function SetChevron(texture, collapsed)
    if HAS_CHEVRON then
        texture:SetAtlas(CHEVRON_ATLAS)
        texture:SetRotation(collapsed and math.pi / 2 or 0)
    else
        texture:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    end
end

-- The gear button on group headers and team rows, opening their menu. onHoverChanged runs when
-- the mouse enters or leaves it, so the row can keep its hover state.
local function CreateGearButton(parent, tooltip, onClick, onHoverChanged)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(16, 16)
    button:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function()
        onHoverChanged()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
        onHoverChanged()
    end)
    return button
end

-- The gear is dimmed to keep the list calm, and in full colour only while its row is hovered.
local function UpdateGearButton(button, hovered)
    local texture = button:GetNormalTexture()
    texture:SetDesaturated(not hovered)
    texture:SetAlpha(hovered and 1 or 0.35)
end

-- "vs. Zunta", or "vs. NPC 66126" without a name; nil without a target.
local function DescribeTarget(team)
    if team.targetNpcID then
        return L["vs. "] .. (team.targetName or (L["NPC "] .. team.targetNpcID))
    end
end

-- Group header (template: LineupGroupHeaderTemplate)
local GroupHeaderMixin = {}
_G.LineupGroupHeaderMixin = GroupHeaderMixin

function GroupHeaderMixin:OnLoad()
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- A card like the teams'; see UpdateState for the outline.
    self.Background = ns.CreateCardFill(self)
    self.Outline = ns.CreateCardOutline(self)

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

    self.EditButton = CreateGearButton(self, L["Group options"], function()
        self:ShowGroupMenu()
    end, function()
        self:UpdateState()
    end)
    self.EditButton:SetPoint("RIGHT", -6, 0)

    self:SetScript("OnEnter", self.UpdateState)
    self:SetScript("OnLeave", self.UpdateState)
end

-- The group holding the loaded team gets a gold outline (so you can find it even while the group
-- is collapsed). Hovering brightens the outline and puts the gear in full colour; it's done here
-- rather than with a highlight texture so it stays while the mouse is on the gear.
function GroupHeaderMixin:UpdateState()
    local data = self.data
    local hovered = self:IsMouseOver()
    ns.UpdateCardOutline(self.Outline, data and data.hasLoaded, hovered)
    UpdateGearButton(self.EditButton, hovered)
end

function GroupHeaderMixin:Init(data)
    self.data = data
    local icon = data.group and data.group.icon
    ns.IconPicker.SetIconTexture(self.Icon, icon, 20)
    self.Icon:SetShown(icon ~= nil)
    self.Name:ClearAllPoints()
    self.Name:SetPoint("LEFT", icon and self.Icon or self.ExpandIcon, "RIGHT", 6, 0)
    self.Name:SetText(data.name)
    self.Count:SetFormattedText("(%d)", data.count)
    SetChevron(self.ExpandIcon, data.collapsed)
    self:UpdateState()
end

-- Options for a group; the "Ungrouped" header (no group) only offers importing.
function GroupHeaderMixin:ShowGroupMenu()
    local group = self.data.group
    MenuUtil.CreateContextMenu(self.EditButton, function(_, root)
        root:CreateTitle(self.data.name)
        if group then
            root:CreateButton(L["Edit Group"], function()
                ns.GroupEditor:Open(group)
            end)
        end
        root:CreateButton(L["Import Team"], function()
            ns.ImportDialog:Open(group and group.id)
        end)
        if group then
            root:CreateButton(L["Export Group"], function()
                ns.ExportDialog:Open(format(L["Export \"%s\""], group.name), ns.Export.Group(group))
            end)
        end
        if group then
            local groups = Teams:GetGroups()
            local index = tIndexOf(groups, group)
            root:CreateDivider()
            root:CreateButton(L["Move Up"], function()
                Teams:MoveGroup(group, -1)
                TeamsPanel:Refresh()
            end):SetEnabled(index > 1)
            root:CreateButton(L["Move Down"], function()
                Teams:MoveGroup(group, 1)
                TeamsPanel:Refresh()
            end):SetEnabled(index < #groups)

            root:CreateDivider()
            root:CreateButton(L["Delete Group"], function()
                ns.GroupEditor.ConfirmDelete(group, false)
            end)
            root:CreateButton(L["Delete Group and Teams"], function()
                ns.GroupEditor.ConfirmDelete(group, true)
            end):SetEnabled(#Teams:GetGroupTeams(group) > 0)
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
TeamsPanel.SplitTeamName = SplitTeamName

function TeamRowMixin:OnLoad()
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Everything visible sits on Inner: a rounded card, indented under group headers, with a little
    -- space to the next card.
    self.Inner = CreateFrame("Frame", nil, self)
    self.Inner:SetPoint("BOTTOMRIGHT", 0, CARD_GAP / 2)
    local inner = self.Inner

    self.Background = ns.CreateCardFill(inner)
    -- Gold for the loaded team, brighter while hovered otherwise.
    self.Outline = ns.CreateCardOutline(inner)

    self.EditButton = CreateGearButton(self, L["Team options"], function()
        self:ShowTeamMenu()
    end, function()
        self:UpdateEditButton()
        if not self:IsMouseOver() then
            self:SetHovered(false)
        end
    end)
    self.EditButton:SetPoint("TOPRIGHT", -6, -8)

    -- Family tag from the team name, e.g. "Humanoid", lined up on the right.
    self.Tag = inner:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    self.Tag:SetPoint("RIGHT", self.EditButton, "LEFT", -6, 0)

    self.Name = inner:CreateFontString(nil, "ARTWORK", "GameFontHighlightMed2")
    -- Check mark in front of the loaded team's name.
    self.Check = inner:CreateTexture(nil, "ARTWORK")
    self.Check:SetSize(14, 14)
    self.Check:SetPoint("TOPLEFT", 10, -10)
    self.Check:SetTexture(LOADED_ICON)
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
end

-- "Script", with what's wrong when it won't run as written ("No script" in grey without one). Grey while tdBattlePetScript isn't
-- installed (nothing can run then), otherwise green, orange or red like the script's status.
local SCRIPT_LABELS = {
    ok = L["Script"],
    warning = L["Script · check abilities"],
    error = L["Script · error"],
}

function TeamRowMixin:UpdateScriptLabel(team)
    if not team.script then
        self.Script:SetText(L["No script"])
        self.Script:SetTextColor(GRAY_FONT_COLOR:GetRGB())
        return
    end
    local status = ns.Script.Check(team.script, team.pets)
    self.Script:SetText(SCRIPT_LABELS[status.level] or L["Script"])
    if status.level == "ok" and not ns.Script.CanRun() then
        self.Script:SetTextColor(GRAY_FONT_COLOR:GetRGB())
    else
        self.Script:SetTextColor(status.color:GetRGB())
    end
end

function TeamRowMixin:Init(data)
    local team = data.team
    self.team = team

    self.Inner:SetPoint("TOPLEFT", data.indented and ROW_INDENT or 0, -CARD_GAP / 2)
    -- (A texture's alpha is part of its vertex color, so the stripe is set there, not with SetAlpha.)
    ns.SetCardFillAlpha(self.Background, data.stripe and 0.24 or 0.18)
    local loaded = Teams:IsLoaded(team)
    self.loaded = loaded
    ns.UpdateCardOutline(self.Outline, loaded, false)
    self:UpdateEditButton()

    local displayName, tag = SplitTeamName(team.name)
    self.Name:SetText(displayName)
    -- The loaded team: gold name after a check mark; others white.
    self.Check:SetShown(loaded)
    self.Name:SetPoint("TOPLEFT", loaded and 28 or 10, -9)
    self.Name:SetTextColor((loaded and NORMAL_FONT_COLOR or HIGHLIGHT_FONT_COLOR):GetRGB())
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

    -- Target, green while you're targeting it; "No target" in grey.
    local target = DescribeTarget(team)
    if not target then
        target = GRAY_FONT_COLOR:WrapTextInColorCode(L["No target"])
    elseif ns.Target:IsCurrent(team.targetNpcID) then
        target = GREEN_FONT_COLOR:WrapTextInColorCode(target)
    end
    self.Target:SetText(target)
    self:UpdateScriptLabel(team)
end

function TeamRowMixin:UpdateEditButton()
    UpdateGearButton(self.EditButton, self:IsMouseOver())
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
        root:CreateButton(L["Load Team"], function()
            Teams:Load(team)
        end)
        root:CreateButton(L["Edit Team"], function()
            ns.TeamEditor:Open(team)
        end)
        root:CreateButton(L["Update with Current Pets"], function()
            ns.Dialogs.Confirm(format(L["Replace the pets of \"%s\" with the pets and abilities in your journal?"], team.name), function()
                Teams:UpdateFromLoadout(team)
                TeamsPanel:Refresh()
            end)
        end)
        root:CreateButton(L["Pop Out Notes"], function()
            ns.NotesWindow:Open(team)
        end):SetEnabled(ns.NotesWindow.HasContent(team))
        root:CreateButton(L["Export Team"], function()
            ns.ExportDialog:Open(format(L["Export \"%s\""], team.name), ns.Export.Team(team))
        end)

        local moveTo = root:CreateButton(L["Move to Group"])
        local function IsInGroup(groupID)
            return (team.groupID or 0) == groupID
        end
        local function MoveToGroup(groupID)
            team.groupID = groupID ~= 0 and groupID or nil
            TeamsPanel:Refresh()
        end
        moveTo:CreateRadio(L["Ungrouped"], IsInGroup, MoveToGroup, 0)
        for _, group in ipairs(Teams:GetGroups()) do
            moveTo:CreateRadio(ns.GroupEditor.FormatGroupName(group), IsInGroup, MoveToGroup, group.id)
        end

        root:CreateDivider()
        root:CreateButton(L["Delete Team"], function()
            ns.Dialogs.Confirm(format(L["Delete team \"%s\"?"], team.name), function()
                Teams:Delete(team)
                TeamsPanel:Refresh()
            end)
        end)
    end)
end

function TeamRowMixin:SetHovered(hovered)
    ns.UpdateCardOutline(self.Outline, self.loaded, hovered)
end

function TeamRowMixin:OnEnter()
    self:SetHovered(true)
    self:UpdateEditButton()
    local team = self.team
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(team.name)
    local target = DescribeTarget(team)
    if target then
        GameTooltip:AddLine(target, 1, 0.82, 0)
    end
    for slot = 1, 3 do
        local entry = team.pets[slot]
        local _, name, level, missing = Teams.GetSlotDisplay(entry)
        local breed = ns.Breeds.DescribeSlot(entry)
        if missing then
            GameTooltip:AddDoubleLine(name, breed or "", 1, 0.25, 0.25, 0.7, 0.7, 0.7)
        elseif name then
            local details = level and format(L["Level %d"], level) or ""
            if breed then
                details = details ~= "" and (breed .. " · " .. details) or breed
            end
            GameTooltip:AddDoubleLine(name, details, 1, 1, 1, 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine(L["Empty slot"], 0.5, 0.5, 0.5)
        end
    end
    if team.script then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Script"], NORMAL_FONT_COLOR:GetRGB())
        ns.Script.AddCheckToTooltip(GameTooltip, ns.Script.Check(team.script, team.pets))
    end
    if team.notes then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(team.notes, 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Click to load. Right-click for options."], 0, 1, 0)
    GameTooltip:Show()
end

function TeamRowMixin:OnLeave()
    GameTooltip:Hide()
    -- Moving onto the gear button counts as leaving the row; keep the hover then.
    if not self:IsMouseOver() then
        self:SetHovered(false)
    end
    self:UpdateEditButton()
end

-- Placeholder under an expanded group that has no teams. (Plain "Button" frames are only used
-- for these rows, so the scroll box pools them separately from spacers and templates.)
local function InitEmptyGroupRow(row)
    if not row.Text then
        row:EnableMouse(false)
        -- Just an outline, indented like a team card: an empty spot where teams would go.
        row.Outline = ns.CreateCardOutline(row)
        row.Outline:ClearAllPoints()
        row.Outline:SetPoint("TOPLEFT", ROW_INDENT, -CARD_GAP / 2)
        row.Outline:SetPoint("BOTTOMRIGHT", 0, CARD_GAP / 2)
        -- A fixed box (all four edges) so the text can wrap onto a second line.
        row.Text = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.Text:SetPoint("TOPLEFT", ROW_INDENT + 10, -2)
        row.Text:SetPoint("BOTTOMRIGHT", -8, 2)
        row.Text:SetJustifyH("LEFT")
        row.Text:SetJustifyV("MIDDLE")
        row.Text:SetWordWrap(true)
        row.Text:SetText(L["No teams. Import one from the gear menu, or choose this group in a team's editor."])
    end
end

local function Contains(text, query)
    return text ~= nil and text:lower():find(query, 1, true) ~= nil
end

-- True if the team's name, target or one of its pets (species or custom name) contains the
-- (lowercase) search text. Random and leveling slots have no pet to match.
local function TeamMatches(team, query)
    if Contains(team.name, query) or Contains(team.targetName, query) then
        return true
    end
    for slot = 1, 3 do
        local entry = team.pets[slot] or {}
        if entry.speciesID and Contains((ns.GetSpeciesInfo(entry.speciesID)), query) then
            return true
        end
        if entry.petID then
            local _, customName = C_PetJournal.GetPetInfoByPetID(entry.petID)
            if Contains(customName, query) then
                return true
            end
        end
    end
    return false
end

-- List building: headers followed by their (sorted) teams unless collapsed, with a little space
-- between groups. Team rows alternate stripes within each group and are indented under headers.
-- With a search (lowercase query), only matching teams (see TeamMatches) are listed (all teams of
-- a group whose name matches), groups without matches are left out, and the rest are shown open.
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
        if not query or Contains(groupName, query) then
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

    -- The loaded team's group header is highlighted.
    local loadedTeam = Teams:GetLoadedTeam()

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
        tinsert(elements, { isHeader = true, group = group, name = name, count = #teams, collapsed = collapsed,
                            hasLoaded = loadedTeam ~= nil and tIndexOf(teams, loadedTeam) ~= nil })
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
        AddGroup(nil, L["Ungrouped"], ungrouped)
    end
    return elements, numShown
end

-- Shows the state like the group headers: right while any group is collapsed, down when all are
-- open. A click toggles (the tooltip says which way); hidden without groups.
local function UpdateExpandAllButton()
    expandAllButton:SetShown(#Teams:GetGroups() > 0)
    SetChevron(expandAllButton.Icon, Teams:IsAnyCollapsed())
end

-- Puts a team in view: clears the search, opens its group and scrolls it to the middle.
function TeamsPanel:ShowTeam(team)
    searchBox:SetText("")
    if team.groupID and Teams:GetGroup(team.groupID) then
        Teams:SetCollapsed(team.groupID, false)
    elseif Teams:IsCollapsed(nil) then
        Teams:SetCollapsed(nil, false)
    end
    self:RefreshNow()
    scrollBox:ScrollToElementDataByPredicate(function(data)
        return data.team == team
    end, ScrollBoxConstants.AlignCenter)
end

-- Panel
function TeamsPanel:Setup()
    panel = CreateFrame("Frame", "LineupTeamsPanel", PetJournal, "ButtonFrameTemplate")
    panel:SetPoint("TOPLEFT", CollectionsJournal, "TOPRIGHT", WINDOW_OFFSET_X, 0)
    panel:SetPoint("BOTTOMLEFT", CollectionsJournal, "BOTTOMRIGHT", WINDOW_OFFSET_X, 0)
    panel:SetWidth(WINDOW_WIDTH)
    -- Catch clicks on the whole window, so they don't reach the world (e.g. an NPC) behind it.
    panel:EnableMouse(true)
    ButtonFrameTemplate_HidePortrait(panel)
    panel.CloseButton:Hide()
    panel.Inset:Hide()
    panel:SetTitle(ns.TITLE)

    -- Teams tab: Target, Current, then the team list, each sunk into the window.
    teamsView = CreateFrame("Frame", nil, panel)
    teamsView:SetAllPoints()

    local targetInset = CreateSectionInset(teamsView, ns.TargetSection)
    local currentInset = CreateSectionInset(teamsView, ns.CurrentSection, targetInset)

    -- Between Current and the list: expand / collapse all, search (teams, targets and groups) and
    -- the Sort button for groups.
    local searchY = -6
    local sortButton = CreateFrame("Button", nil, teamsView, "UIPanelButtonTemplate")
    sortButton:SetPoint("TOPRIGHT", currentInset, "BOTTOMRIGHT", -SECTION_PADDING + 2, searchY)
    sortButton:SetSize(70, 22)
    sortButton:SetText(L["Sort"])
    sortButton:SetScript("OnClick", function()
        ns.GroupSorter:Open()
    end)
    ns.SetTooltip(sortButton, L["Sort groups"], L["Change the order of your groups."])

    searchBox = CreateFrame("EditBox", nil, teamsView, "SearchBoxTemplate")
    -- Expand / collapse all groups; the chevron shows the state, like the group headers.
    expandAllButton = CreateFrame("Button", nil, teamsView)
    expandAllButton:SetSize(22, 22)
    expandAllButton:SetPoint("TOPLEFT", currentInset, "BOTTOMLEFT", SECTION_PADDING - 2, searchY)
    expandAllButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    expandAllButton.Icon = expandAllButton:CreateTexture(nil, "ARTWORK")
    expandAllButton.Icon:SetSize(14, 14)
    expandAllButton.Icon:SetPoint("CENTER")
    expandAllButton:SetScript("OnClick", function()
        Teams:SetAllCollapsed(not Teams:IsAnyCollapsed())
        TeamsPanel:RefreshNow()
    end)
    expandAllButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(Teams:IsAnyCollapsed() and L["Expand all groups"] or L["Collapse all groups"])
        GameTooltip:Show()
    end)
    expandAllButton:SetScript("OnLeave", GameTooltip_Hide)

    searchBox:SetPoint("TOPLEFT", expandAllButton, "TOPRIGHT", 8, 0)
    searchBox:SetPoint("RIGHT", sortButton, "LEFT", -8, 0)
    searchBox:SetHeight(22)
    searchBox:SetAutoFocus(false)
    searchBox.Instructions:SetText(L["Search teams, groups and pets"])
    searchBox:HookScript("OnTextChanged", function()
        TeamsPanel:RefreshNow()
    end)

    local inset = CreateFrame("Frame", nil, teamsView, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", currentInset, "BOTTOMLEFT", 0, 2 * searchY - 22)
    inset:SetPoint("BOTTOMRIGHT", INSET_RIGHT, 26)

    emptyText = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", 16, -16)
    emptyText:SetPoint("TOPRIGHT", -16, -16)

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
    -- Room above the first group and below the last like between groups, and a little on both sides.
    view:SetPadding(GROUP_SPACING, GROUP_SPACING, 4, 4, 2)
    scrollBox = ns.CreateScrollList(inset, view)

    countText = teamsView:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("BOTTOMLEFT", 14, 8)

    -- New Team / New Group / Import along the bottom edge, like the Pet Journal's own buttons.
    local previous
    local function CreateBottomButton(text, onClick)
        local button = CreateFrame("Button", nil, teamsView, "UIPanelButtonTemplate")
        button:SetHeight(22)
        button:SetText(text)
        button:SetWidth(button:GetFontString():GetStringWidth() + 24)
        button:SetScript("OnClick", onClick)
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -2, 0)
        else
            button:SetPoint("BOTTOMRIGHT", INSET_RIGHT, 4)
        end
        previous = button
    end
    CreateBottomButton(L["New Team"], function()
        ns.TeamEditor:Open(nil)
    end)
    CreateBottomButton(L["New Group"], function()
        ns.GroupEditor:Open(nil)
    end)
    CreateBottomButton(L["Import"], function()
        ns.ImportDialog:Open()
    end)

    -- Leveling Queue tab
    queueView = ns.QueueView:Create(panel)

    -- Settings tab (settings and info about the addon)
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
    teamsView:SetShown(tab == TAB_TEAMS)
    queueView:SetShown(tab == TAB_QUEUE)
    aboutView:SetShown(tab == TAB_ABOUT)
    self:RefreshNow()
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

    -- Build the leveling queue up front (it scans the journal) rather than inside row setup.
    ns.LevelingQueue:Get()
    -- Also on the other tabs: the loadout's health drives the glow on Blizzard's heal button.
    ns.CurrentSection:Refresh()

    if currentTab == TAB_QUEUE then
        ns.QueueView:Refresh()
        return
    elseif currentTab == TAB_ABOUT then
        ns.AboutView:Refresh()
        return
    end

    ns.TargetSection:Refresh()
    UpdateExpandAllButton()

    local numTeams = #Teams:GetAll()
    local query = strtrim(searchBox:GetText()):lower()
    query = query ~= "" and query or nil
    local elements, numShown = BuildElements(query)
    scrollBox:SetDataProvider(CreateDataProvider(elements), ScrollBoxConstants.RetainScrollPosition)

    if query and #elements == 0 then
        emptyText:SetText(format(L["Nothing matches \"%s\"."], strtrim(searchBox:GetText())))
        emptyText:Show()
    elseif not query and numTeams == 0 and #Teams:GetGroups() == 0 then
        emptyText:SetText(L["No teams yet.\n\nPick three pets in the journal, then click \"New Team\"."])
        emptyText:Show()
    else
        emptyText:Hide()
    end

    if query then
        countText:SetFormattedText(L["%d of %d teams"], numShown, numTeams)
    else
        countText:SetFormattedText(numTeams == 1 and L["%d team"] or L["%d teams"], numTeams)
    end
end
