local _, ns = ...

-- Window to paste Rematch team strings into. A single team opens in the team editor to review
-- before saving; several teams (one per line, as Xu-Fu exports them) are saved directly.
local ImportDialog = {}
ns.ImportDialog = ImportDialog

local DIALOG_WIDTH = 460
local DIALOG_HEIGHT = 360

local MAX_LISTED_NAMES = 3

local dialog, textBox, statusText, importButton, groupDropdown, replaceCheck
local result, importGroupID

local function GetTeamNames()
    local names = {}
    for _, entry in ipairs(result.entries) do
        if entry.kind == "team" then
            names[#names + 1] = entry.parsed.name
        end
    end
    return names
end

local function UpdateStatus()
    result = nil
    local text = textBox:GetText()
    if strtrim(text) == "" then
        statusText:SetText("Paste a team to import.")
        statusText:SetTextColor(GRAY_FONT_COLOR:GetRGB())
    else
        local all = ns.Import.ParseAll(text)
        if all.numTeams == 0 then
            statusText:SetText(all.errors[1] or "Not a team string.")
            statusText:SetTextColor(RED_FONT_COLOR:GetRGB())
        else
            result = all
            local summary
            if all.numTeams == 1 then
                summary = ns.Import.Describe(all.entries[#all.entries].parsed)
            else
                local names = GetTeamNames()
                local listed = table.concat(names, ", ", 1, math.min(#names, MAX_LISTED_NAMES))
                summary = format("%d teams: %s%s", #names, listed, #names > MAX_LISTED_NAMES and ", ..." or "")
            end
            if #all.errors > 0 then
                summary = summary .. format("  |cffff2020(%d unreadable)|r", #all.errors)
            end
            statusText:SetText(summary)
            statusText:SetTextColor(GREEN_FONT_COLOR:GetRGB())
        end
    end
    importButton:SetEnabled(result ~= nil)
    replaceCheck:SetShown(result ~= nil and result.numTeams > 1)
end

-- One team: open it in the editor. Several: confirm, then save them all and report problems in chat.
-- (A single team under a group header is saved directly, without asking.)
local function DoImport()
    if not result then
        return
    end
    dialog:Hide()

    local hasGroups = false
    for _, entry in ipairs(result.entries) do
        hasGroups = hasGroups or entry.kind == "group"
    end

    if result.numTeams == 1 and not hasGroups then
        local draft, warnings = ns.Import.BuildDraft(result.entries[1].parsed)
        draft.groupID = importGroupID
        ns.TeamEditor:Open(nil, draft)
        for _, warning in ipairs(warnings) do
            ns:Print(warning)
        end
        return
    end

    local replace = replaceCheck:GetChecked()
    local toImport, groupID = result, importGroupID
    ns.Import.ConfirmImportAll(toImport, replace, nil, nil, function()
        ns.Import.Report(ns.Import.ImportAll(toImport, groupID, replace))
        ns.TeamsPanel:Refresh()
    end)
end

local function CreateDialog()
    dialog = CreateFrame("Frame", "LineupImportDialog", UIParent, "ButtonFrameTemplate")
    dialog:SetSize(DIALOG_WIDTH, DIALOG_HEIGHT)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetToplevel(true)
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    ButtonFrameTemplate_HidePortrait(dialog)
    dialog.Inset:Hide()
    dialog:SetTitle("Import Team")
    tinsert(UISpecialFrames, dialog:GetName())

    -- Addons can't read the clipboard, so pasting is up to the player; the box is focused on open.
    local clearButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    clearButton:SetPoint("TOPRIGHT", -12, -30)
    clearButton:SetSize(80, 22)
    clearButton:SetText("Clear")
    clearButton:SetScript("OnClick", function()
        textBox:SetText("")
        textBox:SetFocus()
    end)

    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", 16, -32)
    hint:SetPoint("RIGHT", clearButton, "LEFT", -10, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Paste one or more Rematch team strings, e.g. from Xu-Fu's Pet Guides.")

    local textInset = CreateFrame("Frame", nil, dialog, "InsetFrameTemplate")
    textInset:SetPoint("TOPLEFT", 14, -66)
    textInset:SetPoint("BOTTOMRIGHT", -14, 82)

    local lastLength = 0
    textBox = ns.Dialogs.CreateMultiLineEditBox(textInset, DIALOG_WIDTH - 80, function(box, userInput)
        -- After a paste the cursor (and view) is at the end; jump back so the team name is visible.
        local length = #box:GetText()
        if userInput and length - lastLength > 1 then
            C_Timer.After(0, function()
                box:SetCursorPosition(0)
            end)
        end
        lastLength = length
        UpdateStatus()
    end)

    statusText = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", textInset, "BOTTOMLEFT", 4, -6)
    statusText:SetPoint("RIGHT", -16, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetWordWrap(false)

    importButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    importButton:SetPoint("BOTTOMRIGHT", -8, 6)
    importButton:SetSize(100, 22)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", DoImport)

    local cancelButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelButton:SetPoint("RIGHT", importButton, "LEFT", -4, 0)
    cancelButton:SetSize(100, 22)
    cancelButton:SetText(CANCEL)
    cancelButton:SetScript("OnClick", function()
        dialog:Hide()
    end)

    -- Group the imported team goes into.
    local groupLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    groupLabel:SetPoint("BOTTOMLEFT", 18, 42)
    groupLabel:SetText("Group")

    groupDropdown = CreateFrame("DropdownButton", nil, dialog, "WowStyle1DropdownTemplate")
    groupDropdown:SetPoint("LEFT", groupLabel, "RIGHT", 8, 0)
    groupDropdown:SetWidth(180)
    ns.GroupEditor.SetupGroupDropdown(groupDropdown, function()
        return importGroupID
    end, function(groupID)
        importGroupID = groupID
    end)

    -- Only shown when importing several teams.
    replaceCheck = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
    replaceCheck:SetSize(24, 24)
    replaceCheck:SetPoint("LEFT", groupDropdown, "RIGHT", 12, 0)
    replaceCheck:SetChecked(true)
    replaceCheck.Label = replaceCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    replaceCheck.Label:SetPoint("LEFT", replaceCheck, "RIGHT", 2, 0)
    replaceCheck.Label:SetText("Replace same names")
    replaceCheck:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText("Replace same names")
        GameTooltip:AddLine("Teams with the same name as one you already have replace it, instead of being added again. Handy for re-importing an updated list.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    replaceCheck:SetScript("OnLeave", GameTooltip_Hide)
end

-- Opens the import window; groupID preselects the group for the imported team (nil = ungrouped).
function ImportDialog:Open(groupID)
    if not dialog then
        CreateDialog()
    end
    importGroupID = groupID
    groupDropdown:GenerateMenu()
    textBox:SetText("")
    UpdateStatus()

    local teamsPanel = ns.TeamsPanel:GetFrame()
    dialog:ClearAllPoints()
    if teamsPanel and teamsPanel:IsVisible() then
        dialog:SetPoint("TOPLEFT", teamsPanel, "TOPRIGHT", 4, 0)
    else
        dialog:SetPoint("CENTER")
    end
    dialog:Show()
    dialog:Raise()
    textBox:SetFocus()
end
