local _, ns = ...
local L = ns.L
local Teams = ns.Teams

-- Window for creating and editing a team: name, group, target NPC, pets and script.
local TeamEditor = {}
ns.TeamEditor = TeamEditor

local EXTRA_LEFT = ns.Dialogs.LEFT_BORDER_EXTRA
local EDITOR_WIDTH = 420 + EXTRA_LEFT
local EDITOR_HEIGHT = 560
local LABEL_WIDTH = 70
-- Window edge to the labels on the left.
local CONTENT_LEFT = 16 + EXTRA_LEFT
local PET_ICON_SIZE = 32
local PET_ICON_SPACING = 14

local editor, nameBox, groupDropdown, npcIDBox, targetNameText, petIcons, scriptBox, scriptStatus, saveButton, deleteButton
-- Show a message below the name and target boxes (see Dialogs.CreateInputError).
local ShowNameError, ShowTargetError
local fixAbilitiesButton
local editingTeam, draft, scriptCheck

local function CreateLabel(text, anchor, offsetY)
    local label = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", anchor, "TOPLEFT", CONTENT_LEFT, offsetY)
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
        targetNameText:SetTextColor(ns.MUTED_COLOR:GetRGB())
    end
end

-- Shown before the script status: a check mark, a warning sign or a red cross.
local SCRIPT_STATUS_ICONS = {
    ok = "|TInterface\\RaidFrame\\ReadyCheck-Ready:16:16|t ",
    warning = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:16:16|t ",
    error = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:16:16|t ",
}
local SAVE_BUTTON_MIN_WIDTH = 100

-- Translated where they're shown (L[text]).
local SAVE_TEXTS = {
    error = "Save with Errors",
    warning = "Save with Warnings",
}

-- Sizes a button to its text, at least minWidth wide.
local function FitButton(button, minWidth)
    button:SetWidth(max(minWidth, button:GetFontString():GetStringWidth() + 24))
end

-- The script is checked against the team's pets too, so it's updated with them. A script with
-- problems can still be saved (to fix later), but the button says so. Abilities the script needs
-- that a pet can learn get a button to select them.
local function UpdateScriptStatus()
    scriptCheck = ns.Script.Check(draft.script, draft.pets)
    scriptStatus:SetText((SCRIPT_STATUS_ICONS[scriptCheck.level] or "") .. scriptCheck.summary)
    scriptStatus:SetTextColor(scriptCheck.color:GetRGB())

    local canFix = scriptCheck.fixes ~= nil and #scriptCheck.fixes > 0
    fixAbilitiesButton:SetShown(canFix)
    scriptStatus:SetPoint("RIGHT", canFix and fixAbilitiesButton or editor, canFix and "LEFT" or "RIGHT", canFix and -6 or -16, 0)

    saveButton:SetText(SAVE_TEXTS[scriptCheck.level] and L[SAVE_TEXTS[scriptCheck.level]] or SAVE)
    FitButton(saveButton, SAVE_BUTTON_MIN_WIDTH)
end

-- "1/1/2": which ability each slot picks ("-" when left open); empty without a fixed pet.
local function DescribeAbilityChoices(entry)
    local choices = Teams.GetAbilityChoices(entry)
    if not choices then
        return ""
    end
    return format("%s/%s/%s", choices[1] or "-", choices[2] or "-", choices[3] or "-")
end

-- Both abilities of each slot, the picked one bright and the other dimmed.
local function AddAbilitiesToTooltip(entry)
    local choices, list = Teams.GetAbilityChoices(entry)
    if not choices then
        return
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Abilities"], NORMAL_FONT_COLOR:GetRGB())
    for index = 1, 3 do
        local _, first = C_PetBattles.GetAbilityInfoByID(list[index])
        local _, second = C_PetBattles.GetAbilityInfoByID(list[index + 3])
        local choice = choices[index]
        local firstShade = (choice == 1 or not choice) and 1 or 0.45
        local secondShade = (choice == 2 or not choice) and 1 or 0.45
        GameTooltip:AddDoubleLine(format("%d. %s", index, first), second,
            firstShade, firstShade, firstShade, secondShade, secondShade, secondShade)
    end
    if not (choices[1] and choices[2] and choices[3]) then
        GameTooltip:AddLine(L["\"-\" keeps whatever is selected in the journal."], 0.6, 0.6, 0.6, true)
    end
end

local function UpdatePets()
    for slot, icon in ipairs(petIcons) do
        local texture, _, _, missing = Teams.GetSlotDisplay(draft.pets[slot])
        icon.Texture:SetTexture(texture)
        icon.Texture:SetDesaturated(missing)
        icon.Abilities.Text:SetText(DescribeAbilityChoices(draft.pets[slot]))
        -- Random, leveling and empty slots have no abilities to pick, so nothing to hover or click.
        icon.Abilities:SetShown(Teams.GetAbilityChoices(draft.pets[slot]) ~= nil)
    end
    UpdateScriptStatus()
end

-- Menu to pick each ability slot's ability (or leave it open) for a fixed pet in the draft. It
-- stays open, so all three can be set in one go.
local function ShowAbilityMenu(owner, slot)
    local entry = draft.pets[slot]
    local choices, list = Teams.GetAbilityChoices(entry)
    if not choices then
        return
    end
    local function IsSelected(data)
        local selected = entry.abilities and entry.abilities[data.index]
        return selected == data.abilityID
    end
    local function Select(data)
        entry.abilities = entry.abilities or {}
        entry.abilities[data.index] = data.abilityID
        UpdatePets()
        return MenuResponse.Refresh
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        local _, name = Teams.GetSlotDisplay(entry)
        root:CreateTitle(name)
        for index = 1, 3 do
            root:CreateDivider()
            root:CreateTitle(format(L["Ability slot %d"], index))
            for _, abilityID in ipairs({ list[index], list[index + 3] }) do
                local _, abilityName, abilityIcon = C_PetBattles.GetAbilityInfoByID(abilityID)
                root:CreateRadio(format("|T%s:16:16|t %s", abilityIcon, abilityName), IsSelected, Select,
                    { index = index, abilityID = abilityID })
            end
            root:CreateRadio(ns.MUTED_COLOR:WrapTextInColorCode(L["Keep current"]), IsSelected, Select, { index = index })
        end
    end)
end

-- Puts the pet picker's choice into a slot. A pet of the same species keeps the slot's ability
-- picks (and the breed the team asks for); another one starts with its first three abilities
-- (usable at any level). A leveling slot
-- keeps its leveling preferences when it already was one.
local function SetSlotPet(slot, pet)
    local entry = draft.pets[slot]
    if not pet.petID then
        if pet.leveling and entry.leveling then
            pet.preferences = entry.preferences
        end
        draft.pets[slot] = pet
        UpdatePets()
        return
    end
    local abilities
    if entry.speciesID == pet.speciesID and entry.abilities then
        abilities = CopyTable(entry.abilities)
    else
        local list = ns.GetSpeciesAbilities(pet.speciesID).ids
        abilities = { list[1], list[2], list[3] }
    end
    local breed = entry.speciesID == pet.speciesID and entry.breed or nil
    draft.pets[slot] = { petID = pet.petID, speciesID = pet.speciesID, abilities = abilities, breed = breed }
    UpdatePets()
end

local function Save()
    local name = strtrim(nameBox:GetText())
    if name == "" then
        ShowNameError(L["A team needs a name"])
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
    editor = ns.Dialogs.CreateWindow("LineupTeamEditor", EDITOR_WIDTH, EDITOR_HEIGHT)
    editor.Inset:Hide()

    -- Name
    CreateLabel(L["Name"], editor, -40)
    nameBox = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    nameBox:SetPoint("TOPLEFT", CONTENT_LEFT + LABEL_WIDTH + 6, -34)
    nameBox:SetPoint("RIGHT", -20, 0)
    nameBox:SetHeight(24)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(40)
    nameBox:SetScript("OnEnterPressed", EditBox_ClearFocus)
    ShowNameError = ns.Dialogs.CreateInputError(nameBox)

    -- Group
    CreateLabel(L["Group"], editor, -76)
    groupDropdown = CreateFrame("DropdownButton", nil, editor, "WowStyle1DropdownTemplate")
    groupDropdown:SetPoint("TOPLEFT", CONTENT_LEFT + LABEL_WIDTH, -70)
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
    npcIDBox:SetPoint("TOPLEFT", CONTENT_LEFT + LABEL_WIDTH + 6, -106)
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
    ns.SetTooltip(npcIDBox, L["NPC ID"], L["Target the NPC and click \"Use Target\", or type its ID."])
    -- After the box's own OnTextChanged, which the error hooks.
    ShowTargetError = ns.Dialogs.CreateInputError(npcIDBox)

    local useTargetButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    useTargetButton:SetPoint("TOPRIGHT", -16, -106)
    useTargetButton:SetSize(90, 24)
    useTargetButton:SetText(L["Use Target"])
    useTargetButton:SetScript("OnClick", function()
        local npcID, name = ns.Target.GetNpc("target")
        if not npcID then
            ShowTargetError(L["Target an NPC first"])
            return
        end
        ShowTargetError(nil)
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
        -- Clicking the icon opens the pet picker for this slot.
        local icon = CreateFrame("Button", nil, editor)
        icon:SetSize(PET_ICON_SIZE, PET_ICON_SIZE)
        icon:SetPoint("TOPLEFT", CONTENT_LEFT + LABEL_WIDTH + 6 + (slot - 1) * (PET_ICON_SIZE + PET_ICON_SPACING), -146)
        icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        icon.Background = icon:CreateTexture(nil, "BACKGROUND")
        icon.Background:SetAllPoints()
        icon.Background:SetColorTexture(0, 0, 0, 0.5)
        icon.Texture = icon:CreateTexture(nil, "ARTWORK")
        icon.Texture:SetAllPoints()
        -- The slot's pet and abilities, and what a click does (hint).
        local function ShowTooltip(owner, hint)
            local entry = draft.pets[slot]
            local _, name, level, missing = Teams.GetSlotDisplay(entry)
            GameTooltip:SetOwner(owner, "ANCHOR_TOP")
            if name then
                GameTooltip:SetText(name, missing and 1 or nil, missing and 0.25 or nil, missing and 0.25 or nil)
                if level then
                    GameTooltip:AddLine(format(L["Level %d"], level), 1, 1, 1)
                end
                local breed = ns.Breeds.DescribeSlot(entry)
                if breed then
                    GameTooltip:AddLine(L["Breed: "] .. breed, 1, 1, 1)
                end
                AddAbilitiesToTooltip(entry)
            else
                GameTooltip:SetText(L["Empty slot"], GRAY_FONT_COLOR:GetRGB())
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(hint, 0, 1, 0)
            GameTooltip:Show()
        end
        icon:SetScript("OnEnter", function(button)
            ShowTooltip(button, L["Click to choose a pet."])
        end)
        icon:SetScript("OnLeave", GameTooltip_Hide)
        icon:SetScript("OnClick", function()
            GameTooltip:Hide()
            local taken = {}
            for otherSlot, entry in ipairs(draft.pets) do
                if otherSlot ~= slot and entry.petID then
                    taken[entry.petID] = true
                end
            end
            ns.PetPicker:Open(editor, slot, taken, function(pet)
                SetSlotPet(slot, pet)
            end)
        end)

        -- The picked abilities under the icon, e.g. "1/1/2"; hovering shows their names, clicking
        -- changes them.
        icon.Abilities = CreateFrame("Button", nil, editor)
        icon.Abilities:SetPoint("TOP", icon, "BOTTOM", 0, -2)
        icon.Abilities:SetSize(PET_ICON_SIZE + 6, 12)
        icon.Abilities:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        icon.Abilities.Text = icon.Abilities:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        icon.Abilities.Text:SetAllPoints()
        icon.Abilities:SetScript("OnEnter", function(button)
            ShowTooltip(button, L["Click to change the abilities."])
        end)
        icon.Abilities:SetScript("OnLeave", GameTooltip_Hide)
        icon.Abilities:SetScript("OnClick", function(button)
            GameTooltip:Hide()
            ShowAbilityMenu(button, slot)
        end)
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
    ns.SetTooltip(usePetsButton, L["Use Current Pets"],
        L["Replace this team's pets and abilities with the pets in your journal."])

    -- Script
    local scriptLabel = CreateLabel(L["Script"], editor, -198)
    local scriptHint = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scriptHint:SetPoint("LEFT", scriptLabel, "RIGHT", 0, 0)
    scriptHint:SetTextColor(ns.MUTED_COLOR:GetRGB())
    scriptHint:SetText(L["Paste a tdBattlePetScript script, e.g. from Xu-Fu's Pet Guides"])

    local scriptInset = CreateFrame("Frame", nil, editor, "InsetFrameTemplate")
    scriptInset:SetPoint("TOPLEFT", 14 + EXTRA_LEFT, -216)
    scriptInset:SetPoint("BOTTOMRIGHT", -14, 56)

    scriptBox = ns.Dialogs.CreateMultiLineEditBox(scriptInset, EDITOR_WIDTH - 80, function(box, userInput)
        if userInput then
            draft.script = box:GetText()
            UpdateScriptStatus()
        end
    end)

    -- Selects the abilities the script needs on pets that can learn them (see Script.Check).
    fixAbilitiesButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    fixAbilitiesButton:SetPoint("TOPRIGHT", scriptInset, "BOTTOMRIGHT", 0, -3)
    fixAbilitiesButton:SetHeight(20)
    fixAbilitiesButton:SetText(L["Select Script Abilities"])
    FitButton(fixAbilitiesButton, 0)
    fixAbilitiesButton:Hide()
    fixAbilitiesButton:SetScript("OnClick", function()
        ns.Script.ApplyFixes(draft.pets, scriptCheck.fixes)
        UpdatePets()
    end)
    fixAbilitiesButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(L["Select Script Abilities"])
        for _, fix in ipairs(scriptCheck.fixes) do
            local _, petName = Teams.GetSlotDisplay(draft.pets[fix.slot])
            local _, abilityName = C_PetBattles.GetAbilityInfoByID(fix.abilityID)
            GameTooltip:AddDoubleLine(format(L["Slot %d: %s"], fix.slot, petName), abilityName, 1, 1, 1, 0, 1, 0)
        end
        GameTooltip:Show()
    end)
    fixAbilitiesButton:SetScript("OnLeave", GameTooltip_Hide)

    scriptStatus = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scriptStatus:SetPoint("TOPLEFT", scriptInset, "BOTTOMLEFT", 4, -5)
    scriptStatus:SetPoint("RIGHT", -16, 0)
    scriptStatus:SetJustifyH("LEFT")
    scriptStatus:SetWordWrap(false)

    -- The status line shows the first problem; hovering it lists them all.
    local scriptStatusHover = CreateFrame("Frame", nil, editor)
    scriptStatusHover:SetAllPoints(scriptStatus)
    scriptStatusHover:SetScript("OnEnter", function(frame)
        if scriptCheck.level == "none" then
            return
        end
        GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Script"])
        ns.Script.AddCheckToTooltip(GameTooltip, scriptCheck)
        GameTooltip:Show()
    end)
    scriptStatusHover:SetScript("OnLeave", GameTooltip_Hide)

    -- Buttons
    saveButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    saveButton:SetPoint("BOTTOMRIGHT", -8, 6)
    saveButton:SetSize(SAVE_BUTTON_MIN_WIDTH, 22)
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
    deleteButton:SetPoint("BOTTOMLEFT", 8 + EXTRA_LEFT, 6)
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
    ns.PetPicker:Hide()

    editor:SetTitle(team and L["Edit Team"] or (initialDraft and L["Import Team"]) or L["New Team"])
    nameBox:SetText(draft.name)
    ShowNameError(nil)
    ShowTargetError(nil)
    npcIDBox:SetText(draft.targetNpcID and tostring(draft.targetNpcID) or "")
    scriptBox:SetText(draft.script)
    deleteButton:SetShown(team ~= nil)
    groupDropdown:GenerateMenu()
    UpdateTarget()
    UpdatePets()

    ns.Dialogs.PlaceWindow(editor)
    editor:Show()
    editor:Raise()

    if not team then
        nameBox:SetFocus()
        nameBox:HighlightText()
    end
end
