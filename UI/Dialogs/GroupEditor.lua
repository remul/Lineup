local _, ns = ...
local L = ns.L
local Teams = ns.Teams

-- Window for creating and editing a group, with a "Group" tab (name) and an "Icon" tab.
local GroupEditor = {}
ns.GroupEditor = GroupEditor

local EXTRA_LEFT = ns.Dialogs.LEFT_BORDER_EXTRA
local EDITOR_HEIGHT = 460
local TAB_GROUP, TAB_ICON = 1, 2
local PREVIEW_ICON_SIZE = 48

local editor, nameBox, previewIcon, previewName, iconPicker, groupTab, iconTab, deleteButton
local editingGroup, draft, onSaved
-- Shows a message below the name box (see Dialogs.CreateInputError).
local ShowNameError

local function UpdatePreview()
    ns.IconPicker.SetIconTexture(previewIcon, draft.icon or "Interface\\Icons\\INV_Misc_QuestionMark", PREVIEW_ICON_SIZE)
    previewIcon:SetDesaturated(draft.icon == nil)
    local name = strtrim(nameBox:GetText())
    previewName:SetText(name ~= "" and name or L["New Group"])
end

local function SelectTab(tab)
    PanelTemplates_SetTab(editor, tab)
    groupTab:SetShown(tab == TAB_GROUP)
    iconTab:SetShown(tab == TAB_ICON)
end

local function Save()
    local name = strtrim(nameBox:GetText())
    if name == "" then
        ShowNameError(L["A group needs a name"])
        SelectTab(TAB_GROUP)
        nameBox:SetFocus()
        return
    end

    local group = editingGroup
    if group then
        Teams:RenameGroup(group, name)
    else
        group = Teams:CreateGroup(name)
    end
    Teams:SetGroupIcon(group, draft.icon)

    editor:Hide()
    ns.TeamsPanel:Refresh()
    if onSaved then
        onSaved(group)
    end
end

-- Asks, then deletes the group: its teams become ungrouped, or with deleteTeams are deleted too.
-- onDeleted() runs afterwards (optional).
function GroupEditor.ConfirmDelete(group, deleteTeams, onDeleted)
    local prompt
    if deleteTeams then
        local numTeams = #Teams:GetGroupTeams(group)
        prompt = format(numTeams == 1 and L["Delete group \"%s\" and its team?"]
            or L["Delete group \"%s\" and its %d teams?"], group.name, numTeams)
    else
        prompt = format(L["Delete group \"%s\"?\nIts teams become ungrouped."], group.name)
    end
    ns.Dialogs.Confirm(prompt, function()
        Teams:DeleteGroup(group, deleteTeams)
        if onDeleted then
            onDeleted()
        end
        ns.TeamsPanel:Refresh()
    end)
end

local function Delete()
    GroupEditor.ConfirmDelete(editingGroup, false, function()
        editor:Hide()
    end)
end

local function CreateTab(index, text)
    local tab = CreateFrame("Button", "LineupPetBattlesGroupEditorTab" .. index, editor, "PanelTabButtonTemplate")
    tab:SetID(index)
    tab:SetText(text)
    PanelTemplates_TabResize(tab, 0)
    tab:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        SelectTab(index)
    end)
    return tab
end

local function CreateEditor()
    editor = ns.Dialogs.CreateWindow("LineupPetBattlesGroupEditor", ns.IconPicker.WIDTH + 24 + EXTRA_LEFT, EDITOR_HEIGHT)
    editor.Inset:Hide()

    -- Tabs along the bottom edge, like other Blizzard windows.
    editor.Tabs = { CreateTab(TAB_GROUP, L["Group"]), CreateTab(TAB_ICON, L["Icon"]) }
    editor.Tabs[1]:SetPoint("TOPLEFT", editor, "BOTTOMLEFT", 11, 2)
    editor.Tabs[2]:SetPoint("LEFT", editor.Tabs[1], "RIGHT", 3, 0)
    PanelTemplates_SetNumTabs(editor, #editor.Tabs)

    -- Group tab: preview and name.
    groupTab = CreateFrame("Frame", nil, editor)
    groupTab:SetPoint("TOPLEFT", 12 + EXTRA_LEFT, -30)
    groupTab:SetPoint("BOTTOMRIGHT", -12, 34)

    local previewInset = CreateFrame("Frame", nil, groupTab, "InsetFrameTemplate")
    previewInset:SetPoint("TOPLEFT")
    previewInset:SetPoint("TOPRIGHT")
    previewInset:SetHeight(72)

    local previewButton = CreateFrame("Button", nil, previewInset)
    previewButton:SetSize(PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)
    previewButton:SetPoint("LEFT", 12, 0)
    previewButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    previewButton:SetScript("OnClick", function()
        SelectTab(TAB_ICON)
    end)
    previewButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Click to choose an icon"])
        GameTooltip:Show()
    end)
    previewButton:SetScript("OnLeave", GameTooltip_Hide)
    previewIcon = previewButton:CreateTexture(nil, "ARTWORK")
    previewIcon:SetPoint("CENTER")

    previewName = previewInset:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    previewName:SetPoint("LEFT", previewButton, "RIGHT", 12, 0)
    previewName:SetPoint("RIGHT", -12, 0)
    previewName:SetJustifyH("LEFT")
    previewName:SetWordWrap(false)

    local nameLabel = groupTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", previewInset, "BOTTOMLEFT", 4, -20)
    nameLabel:SetText(L["Name"])

    nameBox = CreateFrame("EditBox", nil, groupTab, "InputBoxTemplate")
    nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 4, -4)
    nameBox:SetPoint("RIGHT", -4, 0)
    nameBox:SetHeight(24)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(40)
    nameBox:SetScript("OnTextChanged", UpdatePreview)
    nameBox:SetScript("OnEnterPressed", Save)
    ShowNameError = ns.Dialogs.CreateInputError(nameBox)

    local chooseIconButton = CreateFrame("Button", nil, groupTab, "UIPanelButtonTemplate")
    chooseIconButton:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -14)
    chooseIconButton:SetSize(140, 24)
    chooseIconButton:SetText(L["Choose Icon..."])
    chooseIconButton:SetScript("OnClick", function()
        SelectTab(TAB_ICON)
    end)

    -- Icon tab.
    iconTab = CreateFrame("Frame", nil, editor)
    iconTab:SetPoint("TOPLEFT", 12 + EXTRA_LEFT, -30)
    iconTab:SetPoint("BOTTOMRIGHT", -12, 34)
    iconPicker = ns.IconPicker.Create(iconTab, function(icon)
        draft.icon = icon
        UpdatePreview()
        SelectTab(TAB_GROUP)
    end)
    iconPicker:SetAllPoints()

    -- Footer buttons, shared by both tabs.
    local saveButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    saveButton:SetPoint("BOTTOMRIGHT", -8, 6)
    saveButton:SetSize(90, 22)
    saveButton:SetText(SAVE)
    saveButton:SetScript("OnClick", Save)

    local cancelButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -4, 0)
    cancelButton:SetSize(90, 22)
    cancelButton:SetText(CANCEL)
    cancelButton:SetScript("OnClick", function()
        editor:Hide()
    end)

    deleteButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    deleteButton:SetPoint("BOTTOMLEFT", 8 + EXTRA_LEFT, 6)
    deleteButton:SetSize(90, 22)
    deleteButton:SetText(DELETE)
    deleteButton:SetScript("OnClick", Delete)
end

-- The group's name after its icon, for menus.
function GroupEditor.FormatGroupName(group)
    return group.icon and (ns.IconPicker.FormatIcon(group.icon, 16) .. " " .. group.name) or group.name
end

-- Sets up a WowStyle1DropdownTemplate dropdown to choose a group: "Ungrouped", every group, and
-- "New Group...". getGroupID() returns the current choice (nil = ungrouped); setGroupID(id) stores it.
function GroupEditor.SetupGroupDropdown(dropdown, getGroupID, setGroupID)
    local UNGROUPED = 0
    local function IsSelected(groupID)
        return (getGroupID() or UNGROUPED) == groupID
    end
    local function SetSelected(groupID)
        setGroupID(groupID ~= UNGROUPED and groupID or nil)
    end

    dropdown:SetupMenu(function(_, root)
        root:CreateRadio(L["Ungrouped"], IsSelected, SetSelected, UNGROUPED)
        for _, group in ipairs(Teams:GetGroups()) do
            root:CreateRadio(GroupEditor.FormatGroupName(group), IsSelected, SetSelected, group.id)
        end
        root:CreateDivider()
        root:CreateButton(L["New Group..."], function()
            GroupEditor:Open(nil, function(group)
                setGroupID(group.id)
                dropdown:GenerateMenu()
            end)
        end)
    end)
end

-- Opens the editor for a group, or for a new group when group is nil.
-- callback(group) runs after saving, e.g. to select a newly created group.
function GroupEditor:Open(group, callback)
    if not editor then
        CreateEditor()
    end

    editingGroup = group
    onSaved = callback
    draft = { icon = group and group.icon }

    editor:SetTitle(group and L["Edit Group"] or L["New Group"])
    nameBox:SetText(group and group.name or "")
    ShowNameError(nil)
    iconPicker:ClearSearch()
    iconPicker:SetSelected(draft.icon)
    deleteButton:SetShown(group ~= nil)
    UpdatePreview()
    SelectTab(TAB_GROUP)

    ns.Dialogs.PlaceWindow(editor)
    editor:Show()
    editor:Raise()
    nameBox:SetFocus()
end
