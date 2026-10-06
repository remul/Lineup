local _, ns = ...
local L = ns.L
local Teams = ns.Teams

-- Window for creating and editing a team: name, group, target NPC, pets and script.
local TeamEditor = {}
ns.TeamEditor = TeamEditor

local EDITOR_WIDTH = 420
local EDITOR_HEIGHT = 560
local LABEL_WIDTH = 70
local PET_ICON_SIZE = 32

local editor, nameBox, groupDropdown, npcIDBox, targetNameText, petIcons, scriptBox, scriptStatus, deleteButton
local editingTeam, draft

local function CreateLabel(text, anchor, offsetY)
    local label = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchor, "TOPLEFT", 16, offsetY)
    label:SetWidth(LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function UpdateTarget()
    if draft.targetNpcID then
        targetNameText:SetText(draft.targetName or L["Unknown name"])
        targetNameText:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    else
        targetNameText:SetText(L["No target"])
        targetNameText:SetTextColor(GRAY_FONT_COLOR:GetRGB())
    end
end

local function UpdatePets()
    for slot, icon in ipairs(petIcons) do
        local texture, _, _, missing = Teams.GetSlotDisplay(draft.pets[slot])
        icon.Texture:SetTexture(texture)
        icon.Texture:SetDesaturated(missing)
    end
end

local function UpdateScriptStatus()
    local summary, color = ns.Script.Describe(draft.script)
    scriptStatus:SetText(summary)
    scriptStatus:SetTextColor(color:GetRGB())
end

local function Save()
    local name = strtrim(nameBox:GetText())
    if name == "" then
        ns:Print(L["A team needs a name."])
        nameBox:SetFocus()
        return
    end
    draft.name = name
    Teams:Save(editingTeam, draft)
    editor:Hide()
    ns.TeamsPanel:Refresh()
end

local function Delete()
    local team = editingTeam
    ns.Dialogs.Confirm(format(L["Delete team \"%s\"?"], team.name), function()
        Teams:Delete(team)
        editor:Hide()
        ns.TeamsPanel:Refresh()
    end)
end

local function CreateEditor()
    editor = CreateFrame("Frame", "LineupTeamEditor", UIParent, "ButtonFrameTemplate")
    editor:SetSize(EDITOR_WIDTH, EDITOR_HEIGHT)
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

    -- Name
    CreateLabel(L["Name"], editor, -40)
    nameBox = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    nameBox:SetPoint("TOPLEFT", 16 + LABEL_WIDTH + 6, -34)
    nameBox:SetPoint("RIGHT", -20, 0)
    nameBox:SetHeight(24)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(40)
    nameBox:SetScript("OnEnterPressed", EditBox_ClearFocus)

    -- Group
    CreateLabel(L["Group"], editor, -76)
    groupDropdown = CreateFrame("DropdownButton", nil, editor, "WowStyle1DropdownTemplate")
    groupDropdown:SetPoint("TOPLEFT", 16 + LABEL_WIDTH, -70)
    groupDropdown:SetWidth(220)
    -- The dropdown reads the selection while it's set up, before Open() has created a draft.
    ns.GroupEditor.SetupGroupDropdown(groupDropdown, function()
        return draft and draft.groupID
    end, function(groupID)
        draft.groupID = groupID
    end)

    -- Target
    CreateLabel(L["Target"], editor, -112)
    npcIDBox = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    npcIDBox:SetPoint("TOPLEFT", 16 + LABEL_WIDTH + 6, -106)
    npcIDBox:SetSize(70, 24)
    npcIDBox:SetAutoFocus(false)
    npcIDBox:SetNumeric(true)
    npcIDBox:SetMaxLetters(8)
    npcIDBox:SetScript("OnEnterPressed", EditBox_ClearFocus)
    npcIDBox:SetScript("OnTextChanged", function(box, userInput)
        if userInput then
            draft.targetNpcID = tonumber(box:GetText())
            draft.targetName = nil
            UpdateTarget()
        end
    end)
    npcIDBox:SetScript("OnEnter", function(box)
        GameTooltip:SetOwner(box, "ANCHOR_TOP")
        GameTooltip:SetText(L["NPC ID"])
        GameTooltip:AddLine(L["Target the NPC and click \"Use Target\", or type its ID."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    npcIDBox:SetScript("OnLeave", GameTooltip_Hide)

    local useTargetButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    useTargetButton:SetPoint("TOPRIGHT", -16, -106)
    useTargetButton:SetSize(90, 24)
    useTargetButton:SetText(L["Use Target"])
    useTargetButton:SetScript("OnClick", function()
        local npcID, name = ns.Target.GetNpc("target")
        if not npcID then
            ns:Print(L["Target an NPC first."])
            return
        end
        draft.targetNpcID, draft.targetName = npcID, name
        npcIDBox:SetText(tostring(npcID))
        UpdateTarget()
    end)

    targetNameText = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    targetNameText:SetPoint("LEFT", npcIDBox, "RIGHT", 10, 0)
    targetNameText:SetPoint("RIGHT", useTargetButton, "LEFT", -6, 0)
    targetNameText:SetJustifyH("LEFT")
    targetNameText:SetWordWrap(false)

    -- Pets
    CreateLabel(L["Pets"], editor, -156)
    petIcons = {}
    for slot = 1, 3 do
        local icon = CreateFrame("Frame", nil, editor)
        icon:SetSize(PET_ICON_SIZE, PET_ICON_SIZE)
        icon:SetPoint("TOPLEFT", 16 + LABEL_WIDTH + 6 + (slot - 1) * (PET_ICON_SIZE + 6), -146)
        icon.Background = icon:CreateTexture(nil, "BACKGROUND")
        icon.Background:SetAllPoints()
        icon.Background:SetColorTexture(0, 0, 0, 0.5)
        icon.Texture = icon:CreateTexture(nil, "ARTWORK")
        icon.Texture:SetAllPoints()
        icon:SetScript("OnEnter", function(self)
            local _, name, level, missing = Teams.GetSlotDisplay(draft.pets[slot])
            if name then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(name, missing and 1 or nil, missing and 0.25 or nil, missing and 0.25 or nil)
                if level then
                    GameTooltip:AddLine(format(L["Level %d"], level), 1, 1, 1)
                end
                GameTooltip:Show()
            end
        end)
        icon:SetScript("OnLeave", GameTooltip_Hide)
        petIcons[slot] = icon
    end

    local usePetsButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    usePetsButton:SetPoint("TOPRIGHT", -16, -150)
    usePetsButton:SetSize(150, 24)
    usePetsButton:SetText(L["Use Current Pets"])
    usePetsButton:SetScript("OnClick", function()
        draft.pets = Teams:CaptureLoadout()
        UpdatePets()
    end)
    usePetsButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(L["Use Current Pets"])
        GameTooltip:AddLine(L["Replace this team's pets and abilities with the three pets currently in your Pet Journal."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    usePetsButton:SetScript("OnLeave", GameTooltip_Hide)

    -- Script
    local scriptLabel = CreateLabel(L["Script"], editor, -198)
    local scriptHint = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scriptHint:SetPoint("LEFT", scriptLabel, "RIGHT", 0, 0)
    scriptHint:SetText(L["Paste a tdBattlePetScript script, e.g. from Xu-Fu's Pet Guides"])

    local scriptInset = CreateFrame("Frame", nil, editor, "InsetFrameTemplate")
    scriptInset:SetPoint("TOPLEFT", 14, -216)
    scriptInset:SetPoint("BOTTOMRIGHT", -14, 48)

    scriptBox = ns.Dialogs.CreateMultiLineEditBox(scriptInset, EDITOR_WIDTH - 80, function(box, userInput)
        if userInput then
            draft.script = box:GetText()
            UpdateScriptStatus()
        end
    end)

    scriptStatus = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scriptStatus:SetPoint("TOPLEFT", scriptInset, "BOTTOMLEFT", 4, -6)
    scriptStatus:SetPoint("RIGHT", -16, 0)
    scriptStatus:SetJustifyH("LEFT")
    scriptStatus:SetWordWrap(false)

    -- Buttons
    local saveButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    saveButton:SetPoint("BOTTOMRIGHT", -8, 6)
    saveButton:SetSize(100, 22)
    saveButton:SetText(SAVE)
    saveButton:SetScript("OnClick", Save)

    local cancelButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -4, 0)
    cancelButton:SetSize(100, 22)
    cancelButton:SetText(CANCEL)
    cancelButton:SetScript("OnClick", function()
        editor:Hide()
    end)

    deleteButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    deleteButton:SetPoint("BOTTOMLEFT", 8, 6)
    deleteButton:SetSize(100, 22)
    deleteButton:SetText(DELETE)
    deleteButton:SetScript("OnClick", Delete)
end

-- Opens the editor for a team, or for a new team when team is nil. A new team starts from the
-- current loadout, or from initialDraft when given (used by imports).
function TeamEditor:Open(team, initialDraft)
    if not editor then
        CreateEditor()
    end

    editingTeam = team
    draft = initialDraft or Teams:CreateDraft(team)

    editor:SetTitle(team and L["Edit Team"] or (initialDraft and L["Import Team"]) or L["New Team"])
    nameBox:SetText(draft.name)
    npcIDBox:SetText(draft.targetNpcID and tostring(draft.targetNpcID) or "")
    scriptBox:SetText(draft.script)
    deleteButton:SetShown(team ~= nil)
    groupDropdown:GenerateMenu()
    UpdateTarget()
    UpdatePets()
    UpdateScriptStatus()

    local teamsPanel = ns.TeamsPanel:GetFrame()
    editor:ClearAllPoints()
    if teamsPanel and teamsPanel:IsVisible() then
        editor:SetPoint("TOPLEFT", teamsPanel, "TOPRIGHT", 4, 0)
    else
        editor:SetPoint("CENTER")
    end
    editor:Show()
    editor:Raise()

    if not team then
        nameBox:SetFocus()
        nameBox:HighlightText()
    end
end
