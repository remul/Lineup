local _, ns = ...
local Teams = ns.Teams

-- Window for creating and editing a group, with a "Group" tab (name) and an "Icon" tab.
local GroupEditor = {}
ns.GroupEditor = GroupEditor

local EDITOR_HEIGHT = 460
local TAB_GROUP, TAB_ICON = 1, 2

local editor, nameBox, previewIcon, previewName, iconPicker, groupTab, iconTab, deleteButton
local editingGroup, draft, onSaved

local function UpdatePreview()
    previewIcon:SetTexture(draft.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    previewIcon:SetDesaturated(draft.icon == nil)
    local name = strtrim(nameBox:GetText())
    previewName:SetText(name ~= "" and name or "New Group")
end

local function SelectTab(tab)
    PanelTemplates_SetTab(editor, tab)
    groupTab:SetShown(tab == TAB_GROUP)
    iconTab:SetShown(tab == TAB_ICON)
end

local function Save()
    local name = strtrim(nameBox:GetText())
    if name == "" then
        ns:Print("A group needs a name.")
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

local function Delete()
    local group = editingGroup
    ns.Dialogs.Confirm(format("Delete group \"%s\"?\nIts teams become ungrouped.", group.name), function()
        Teams:DeleteGroup(group)
        editor:Hide()
        ns.TeamsPanel:Refresh()
    end)
end

local function CreateTab(index, text)
    local tab = CreateFrame("Button", "LineupGroupEditorTab" .. index, editor, "PanelTabButtonTemplate")
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
    editor = CreateFrame("Frame", "LineupGroupEditor", UIParent, "ButtonFrameTemplate")
    editor:SetSize(ns.IconPicker.WIDTH + 24, EDITOR_HEIGHT)
    editor:SetFrameStrata("DIALOG")
    editor:SetToplevel(true)
    editor:SetMovable(true)
    editor:SetClampedToScreen(true)
    editor:EnableMouse(true)
    editor:RegisterForDrag("LeftButton")
    editor:SetScript("OnDragStart", editor.StartMoving)
    editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
    ButtonFrameTemplate_HidePortrait(editor)
    editor.Inset:Hide()
    tinsert(UISpecialFrames, editor:GetName())

    -- Tabs along the bottom edge, like other Blizzard windows.
    editor.Tabs = { CreateTab(TAB_GROUP, "Group"), CreateTab(TAB_ICON, "Icon") }
    editor.Tabs[1]:SetPoint("TOPLEFT", editor, "BOTTOMLEFT", 11, 2)
    editor.Tabs[2]:SetPoint("LEFT", editor.Tabs[1], "RIGHT", 3, 0)
    PanelTemplates_SetNumTabs(editor, #editor.Tabs)

    -- Group tab: preview and name.
    groupTab = CreateFrame("Frame", nil, editor)
    groupTab:SetPoint("TOPLEFT", 12, -30)
    groupTab:SetPoint("BOTTOMRIGHT", -12, 34)

    local previewInset = CreateFrame("Frame", nil, groupTab, "InsetFrameTemplate")
    previewInset:SetPoint("TOPLEFT")
    previewInset:SetPoint("TOPRIGHT")
    previewInset:SetHeight(72)

    local previewButton = CreateFrame("Button", nil, previewInset)
    previewButton:SetSize(48, 48)
    previewButton:SetPoint("LEFT", 12, 0)
    previewButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    previewButton:SetScript("OnClick", function()
        SelectTab(TAB_ICON)
    end)
    previewButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Click to choose an icon")
        GameTooltip:Show()
    end)
    previewButton:SetScript("OnLeave", GameTooltip_Hide)
    previewIcon = previewButton:CreateTexture(nil, "ARTWORK")
    previewIcon:SetAllPoints()

    previewName = previewInset:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    previewName:SetPoint("LEFT", previewButton, "RIGHT", 12, 0)
    previewName:SetPoint("RIGHT", -12, 0)
    previewName:SetJustifyH("LEFT")
    previewName:SetWordWrap(false)

    local nameLabel = groupTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", previewInset, "BOTTOMLEFT", 4, -20)
    nameLabel:SetText("Name")

    nameBox = CreateFrame("EditBox", nil, groupTab, "InputBoxTemplate")
    nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 4, -4)
    nameBox:SetPoint("RIGHT", -4, 0)
    nameBox:SetHeight(24)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(40)
    nameBox:SetScript("OnTextChanged", UpdatePreview)
    nameBox:SetScript("OnEnterPressed", Save)

    local chooseIconButton = CreateFrame("Button", nil, groupTab, "UIPanelButtonTemplate")
    chooseIconButton:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -14)
    chooseIconButton:SetSize(140, 24)
    chooseIconButton:SetText("Choose Icon...")
    chooseIconButton:SetScript("OnClick", function()
        SelectTab(TAB_ICON)
    end)

    -- Icon tab.
    iconTab = CreateFrame("Frame", nil, editor)
    iconTab:SetPoint("TOPLEFT", 12, -30)
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
    deleteButton:SetPoint("BOTTOMLEFT", 8, 6)
    deleteButton:SetSize(90, 22)
    deleteButton:SetText(DELETE)
    deleteButton:SetScript("OnClick", Delete)
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
        root:CreateRadio("Ungrouped", IsSelected, SetSelected, UNGROUPED)
        for _, group in ipairs(Teams:GetGroups()) do
            local label = group.icon and format("|T%s:16:16|t %s", group.icon, group.name) or group.name
            root:CreateRadio(label, IsSelected, SetSelected, group.id)
        end
        root:CreateDivider()
        root:CreateButton("New Group...", function()
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

    editor:SetTitle(group and "Edit Group" or "New Group")
    nameBox:SetText(group and group.name or "")
    iconPicker:ClearSearch()
    iconPicker:SetSelected(draft.icon)
    deleteButton:SetShown(group ~= nil)
    UpdatePreview()
    SelectTab(TAB_GROUP)

    local teamsPanel = ns.TeamsPanel:GetFrame()
    editor:ClearAllPoints()
    if teamsPanel and teamsPanel:IsVisible() then
        editor:SetPoint("TOPLEFT", teamsPanel, "TOPRIGHT", 4, 0)
    else
        editor:SetPoint("CENTER")
    end
    editor:Show()
    editor:Raise()
    nameBox:SetFocus()
end
