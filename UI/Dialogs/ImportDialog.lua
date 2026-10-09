local _, ns = ...
local L = ns.L

-- Window to paste Rematch team strings into. A single team opens in the team editor to review
-- before saving; several teams (one per line, as Xu-Fu exports them) are saved directly.
local ImportDialog = {}
ns.ImportDialog = ImportDialog

local EXTRA_LEFT = ns.Dialogs.LEFT_BORDER_EXTRA
local DIALOG_WIDTH = 460 + EXTRA_LEFT
local DIALOG_HEIGHT = 440
-- Lines in the preview below the text box (more are summed up).
local MAX_PREVIEW_LINES = 5

local NOTE_ICONS = {
    error = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t ",
    warning = ns.HURT_ICON .. " ",
    info = "|TInterface\\Common\\help-i:14:14:0:0:64:64:14:50:14:50|t ",
}
local NOTE_COLORS = {
    error = RED_FONT_COLOR,
    warning = ORANGE_FONT_COLOR,
    info = GRAY_FONT_COLOR,
}
local READY_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t "

local MAX_LISTED_NAMES = 3

local dialog, textBox, statusText, previewText, importButton, groupDropdown, replaceCheck
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

-- What importing a single team will give: its notes (see Import.BuildDraft) with icons, most
-- important first, or that it's ready.
local function DescribeTeamPreview(parsed)
    local _, notes = ns.Import.BuildDraft(parsed)
    local order = { error = 1, warning = 2, info = 3 }
    table.sort(notes, function(a, b)
        return order[a.severity] < order[b.severity]
    end)
    local lines, hasProblems = {}, false
    for index, note in ipairs(notes) do
        hasProblems = hasProblems or note.severity ~= ns.Import.INFO
        if index <= MAX_PREVIEW_LINES then
            lines[#lines + 1] = NOTE_ICONS[note.severity] .. NOTE_COLORS[note.severity]:WrapTextInColorCode(note.text)
        end
    end
    if #notes > MAX_PREVIEW_LINES then
        lines[#lines + 1] = GRAY_FONT_COLOR:WrapTextInColorCode(format(L["...and %d more"], #notes - MAX_PREVIEW_LINES))
    end
    if not hasProblems then
        tinsert(lines, 1, READY_ICON .. GREEN_FONT_COLOR:WrapTextInColorCode(L["Ready to import: you have all the pets"]))
    end
    return table.concat(lines, "\n")
end

local function UpdateStatus()
    result = nil
    previewText:SetText("")
    local text = textBox:GetText()
    if strtrim(text) == "" then
        statusText:SetText(L["Paste a team to import"])
        statusText:SetTextColor(GRAY_FONT_COLOR:GetRGB())
    else
        local all = ns.Import.ParseAll(text)
        if all.numTeams == 0 then
            statusText:SetText(all.errors[1] or L["Not a team string"])
            statusText:SetTextColor(RED_FONT_COLOR:GetRGB())
        else
            result = all
            local summary
            if all.numTeams == 1 then
                local parsed = all.entries[#all.entries].parsed
                summary = ns.Import.Describe(parsed)
                previewText:SetText(DescribeTeamPreview(parsed))
            else
                local names = GetTeamNames()
                local listed = table.concat(names, ", ", 1, math.min(#names, MAX_LISTED_NAMES))
                summary = format(L["%d teams: %s%s"], #names, listed, #names > MAX_LISTED_NAMES and ", ..." or "")
                previewText:SetText(GRAY_FONT_COLOR:WrapTextInColorCode(L["After importing, teams that need attention are listed in chat"]))
            end
            if #all.errors > 0 then
                summary = summary .. format(L["  |cffff2020(%d unreadable)|r"], #all.errors)
            end
            statusText:SetText(summary)
            statusText:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
        end
    end
    importButton:SetEnabled(result ~= nil)
    replaceCheck:SetShown(result ~= nil and result.numTeams > 1)
end

-- One team: open it in the editor (its notes were in the preview). Several: confirm, then save them
-- all and list the teams that need attention in chat.
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
        -- The notes were in the preview already; the editor shows the pets and the script's check.
        local draft = ns.Import.BuildDraft(result.entries[1].parsed)
        draft.groupID = importGroupID
        ns.TeamEditor:Open(nil, draft)
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
    dialog = ns.Dialogs.CreateWindow("LineupImportDialog", DIALOG_WIDTH, DIALOG_HEIGHT)
    dialog.Inset:Hide()
    dialog:SetTitle(L["Import Team"])

    -- Addons can't read the clipboard, so pasting is up to the player; the box is focused on open.
    local clearButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    clearButton:SetPoint("TOPRIGHT", -12, -30)
    clearButton:SetSize(80, 22)
    clearButton:SetText(L["Clear"])
    clearButton:SetScript("OnClick", function()
        textBox:SetText("")
        textBox:SetFocus()
    end)

    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", 16 + EXTRA_LEFT, -32)
    hint:SetPoint("RIGHT", clearButton, "LEFT", -10, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["Paste one or more Rematch team strings, e.g. from Xu-Fu's Pet Guides"])

    local textInset = CreateFrame("Frame", nil, dialog, "InsetFrameTemplate")
    textInset:SetPoint("TOPLEFT", 14 + EXTRA_LEFT, -66)
    textInset:SetPoint("BOTTOMRIGHT", -14, 82 + 18 + 14 * MAX_PREVIEW_LINES + 16)

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

    -- The preview: what importing will give (one line per note).
    previewText = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewText:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -6)
    previewText:SetPoint("RIGHT", -16, 0)
    previewText:SetJustifyH("LEFT")
    previewText:SetJustifyV("TOP")
    previewText:SetSpacing(3)
    -- A long note can take two lines.
    previewText:SetMaxLines(MAX_PREVIEW_LINES + 2)

    importButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    importButton:SetPoint("BOTTOMRIGHT", -8, 6)
    importButton:SetSize(100, 22)
    importButton:SetText(L["Import"])
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
    groupLabel:SetPoint("BOTTOMLEFT", 18 + EXTRA_LEFT, 42)
    groupLabel:SetText(L["Group"])

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
    replaceCheck.Label:SetText(L["Replace same names"])
    ns.SetTooltip(replaceCheck, L["Replace same names"],
        L["Teams with the same name as an existing team replace it instead of being added again."])
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

    ns.Dialogs.PlaceWindow(dialog)
    dialog:Show()
    dialog:Raise()
    textBox:SetFocus()
end
