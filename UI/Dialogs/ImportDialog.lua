local _, ns = ...
local L = ns.L

-- Window to paste Rematch team strings into. A single team opens in the team editor to review
-- before saving (or is saved right away with the "Import single teams without the editor" option);
-- several teams (one per line, as Xu-Fu exports them) are saved directly. A team whose name you
-- already have can replace that team or be kept as well, with a number.
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
    info = ns.MUTED_COLOR,
}
local READY_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t "

local MAX_LISTED_NAMES = 3

-- The text box holds this many bytes at most: the game lays out all of an edit box's text, which
-- freezes it for seconds with a big paste (hundreds of teams). A longer paste is caught character
-- by character instead (see OnChar), and the box only shows its start.
local MAX_BOX_BYTES = 500

local dialog, textBox, statusText, previewText, importButton, groupDropdown, replaceCheck
local result, importGroupID
-- The whole text of a paste too long for the box, or nil while the box holds all of it.
local pastedText
-- The characters of the paste coming in this frame (nil between pastes), and how many.
local pasteBuffer, pasteLength = nil, 0
-- When the paste's first character came (debugprofilestop), for the debug message.
local pasteStart

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
        lines[#lines + 1] = ns.MUTED_COLOR:WrapTextInColorCode(format(L["...and %d more"], #notes - MAX_PREVIEW_LINES))
    end
    if not hasProblems then
        tinsert(lines, 1, READY_ICON .. GREEN_FONT_COLOR:WrapTextInColorCode(L["Ready to import: you have all the pets"]))
    end
    return table.concat(lines, "\n")
end

local function UpdateStatus()
    result = nil
    previewText:SetText("")
    local text = pastedText or textBox:GetText()
    if strtrim(text) == "" then
        statusText:SetText(L["Paste a team to import"])
        statusText:SetTextColor(ns.MUTED_COLOR:GetRGB())
    else
        local start = debugprofilestop()
        local all = ns.Import.ParseAll(text)
        ns:Debug(format("Import: read %d teams (%d characters) in %.1f ms", all.numTeams, #text,
            debugprofilestop() - start))
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
                previewText:SetText(ns.MUTED_COLOR:WrapTextInColorCode(L["After importing, teams that need attention are listed in chat"]))
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

-- A single team: into the editor to review (its notes were in the preview), or saved right away.
-- replacing is the team it replaces, if any.
local function ImportSingle(parsed, groupID, replacing)
    local draft, notes = ns.Import.BuildDraft(parsed)
    draft.groupID = groupID
    if not replacing then
        draft.name = ns.Teams:GetUniqueName(draft.name)
    end
    if not ns.db.importWithoutEditor then
        ns.TeamEditor:Open(replacing, draft)
        return
    end
    local team = ns.Teams:Save(replacing, draft)
    local problems = ns.Import.GetProblems(notes)
    ns.Import.Report(1, replacing and 1 or 0, #problems > 0 and { { teamName = team.name, problems = problems } } or {})
    ns.TeamsPanel:ShowTeam(team)
end

-- One team: imported as above, asking first if you already have a team of that name. Several:
-- confirm, then save them all and list the teams that need attention in chat.
-- (A single team under a group header is saved like several, without asking.)
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
        local parsed, groupID = result.entries[1].parsed, importGroupID
        local existing = ns.Teams:FindByName(parsed.name)
        if not existing then
            ImportSingle(parsed, groupID)
            return
        end
        ns.Dialogs.Choose(format(L["You already have a team named \"%s\". Replace it, or keep both?"], parsed.name),
            L["Replace"], function()
                ImportSingle(parsed, groupID or existing.groupID, existing)
            end, L["Keep Both"], function()
                ImportSingle(parsed, groupID)
            end)
        return
    end

    local replace = replaceCheck:GetChecked()
    local toImport, groupID = result, importGroupID
    ns.Import.ConfirmImportAll(toImport, replace, nil, nil, function()
        local start = debugprofilestop()
        local numImported, numReplaced, problems = ns.Import.ImportAll(toImport, groupID, replace)
        ns:Debug(format("Import: saved %d teams in %.1f ms", numImported, debugprofilestop() - start))
        ns.Import.Report(numImported, numReplaced, problems)
        ns.TeamsPanel:Refresh()
    end)
end

-- Empties the box (after a long paste, see ShowPasteNote, ready to paste again).
local function ClearText()
    pastedText = nil
    textBox:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    textBox:SetText("")
end

-- After a paste too long for the box: instead of its cut-off start, the box says what was pasted.
-- Clicking it (or Clear) empties it, so the text can't be half changed.
local function ShowPasteNote()
    local note
    if result and result.numTeams == 1 then
        note = L["1 team pasted. It's too long to show here, but it will be imported."]
    elseif result then
        note = format(L["%d teams pasted. They're too long to show here, but all of them will be imported."],
            result.numTeams)
    else
        note = L["The pasted text is too long to show here."]
    end
    textBox:SetText(note .. "\n\n" .. L["Click here to paste something else."])
    textBox:SetTextColor(ns.MUTED_COLOR:GetRGB())
    textBox:SetCursorPosition(0)
    textBox:ClearFocus()
end

-- A paste comes in as one OnChar per character, all in one frame; the next frame puts them
-- together. If the box couldn't hold it all, the whole paste is kept in pastedText (replacing what
-- was in the box), and the box says so (see ShowPasteNote).
local function FinishPaste()
    if not pasteBuffer then
        return
    end
    local text = table.concat(pasteBuffer, "", 1, pasteLength)
    pasteBuffer, pasteLength = nil, 0
    if #text <= 1 or #textBox:GetText() < MAX_BOX_BYTES - 4 then
        -- Typing, or a paste the box holds whole.
        return
    end
    local _, bufferLines = text:gsub("\n", "")
    local _, boxLines = textBox:GetText():gsub("\n", "")
    ns:Debug(format("Import: caught a paste of %d characters (%d line breaks; %d in the box) in %.1f ms",
        #text, bufferLines, boxLines, debugprofilestop() - pasteStart))
    pastedText = text
    UpdateStatus()
    ShowPasteNote()
end

-- Runs for every character of a paste (156,000 for 200 teams), so it does as little as it can.
local function OnChar(_, char)
    if not pasteBuffer then
        pasteBuffer, pasteStart = {}, debugprofilestop()
        C_Timer.After(0, FinishPaste)
    end
    pasteLength = pasteLength + 1
    pasteBuffer[pasteLength] = char
end

local function CreateDialog()
    dialog = ns.Dialogs.CreateWindow("LineupPetBattlesImportDialog", DIALOG_WIDTH, DIALOG_HEIGHT)
    dialog.Inset:Hide()
    dialog:SetTitle(L["Import Team"])

    -- Addons can't read the clipboard, so pasting is up to the player; the box is focused on open.
    local clearButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    clearButton:SetPoint("TOPRIGHT", -12, -30)
    clearButton:SetSize(80, 22)
    clearButton:SetText(L["Clear"])
    clearButton:SetScript("OnClick", function()
        ClearText()
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
        -- The note after a long paste (see ShowPasteNote): the status is already the paste's.
        if pastedText and not userInput then
            return
        end
        -- The box changed by hand: a long paste caught before is replaced by what's in the box (a
        -- new long paste is caught again by FinishPaste).
        pastedText = nil
        UpdateStatus()
    end)
    textBox:SetMaxBytes(MAX_BOX_BYTES)
    textBox:SetScript("OnChar", OnChar)
    -- Clicking the note after a long paste empties the box for the next paste.
    textBox:HookScript("OnEditFocusGained", function()
        if pastedText then
            ClearText()
        end
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
    ClearText()
    UpdateStatus()

    ns.Dialogs.PlaceWindow(dialog)
    dialog:Show()
    dialog:Raise()
    textBox:SetFocus()
end
