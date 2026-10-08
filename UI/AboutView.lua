local addonName, ns = ...
local L = ns.L

-- The Settings tab of the Lineup window: the settings and general info about the addon.
local AboutView = {}
ns.AboutView = AboutView

local view, versionText, statsText, rematchText, rematchButton
-- Checkboxes for settings: { button, key in ns.db }.
local checkboxes = {}

-- Imports every Rematch team and group (with tdBattlePetScript scripts), after confirming.
local function ImportFromRematch()
    local text, ungroupedName = ns.Import.ExportFromRematch()
    if not text then
        ns:Print(L["Couldn't read Rematch's teams: "] .. tostring(ungroupedName))
        return
    end
    local result = ns.Import.ParseAll(text)
    if result.numTeams == 0 then
        ns:Print(L["Rematch has no teams to import."])
        return
    end
    ns.Import.ConfirmImportAll(result, true, ungroupedName, L["From Rematch: "], function()
        ns.Import.Report(ns.Import.ImportAll(result, nil, true, ungroupedName))
        ns.TeamsPanel:Refresh()
    end)
end

-- Space between a section's header and its content, and between sections.
local HEADER_GAP = 6
local SECTION_GAP = 16
local SECTION_HEADER_HEIGHT = 18

local function CreateParagraph(parent, text, anchor, offsetY)
    local paragraph = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    paragraph:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
    paragraph:SetPoint("RIGHT")
    paragraph:SetJustifyH("LEFT")
    paragraph:SetSpacing(2)
    paragraph:SetText(text)
    return paragraph
end

-- A section's gold title with a divider line running to the right edge, below anchor (or at the
-- top of parent).
local function CreateSection(parent, text, anchor)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(SECTION_HEADER_HEIGHT)
    if anchor then
        header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SECTION_GAP)
    else
        header:SetPoint("TOPLEFT")
    end
    header:SetPoint("RIGHT", parent)

    header.Text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.Text:SetPoint("LEFT")
    header.Text:SetText(text)

    header.Line = header:CreateTexture(nil, "ARTWORK")
    header.Line:SetPoint("LEFT", header.Text, "RIGHT", 8, 0)
    header.Line:SetPoint("RIGHT")
    header.Line:SetHeight(ns.SetDividerTexture(header.Line))
    return header
end

-- Builds the view inside parent (the Lineup window) and returns it; it starts hidden. The addon's
-- name and description sit on the window, the sections below sunk into it like the Teams tab's.
function AboutView:Create(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local edge = ns.TeamsPanel.SECTION_INSET
    local header = CreateFrame("Frame", nil, view)
    header:SetPoint("TOPLEFT", edge, -32)
    header:SetPoint("BOTTOMRIGHT", -edge, 30)

    -- Header: icon, name, version and what Lineup does.
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT")
    icon:SetTexture(ns.MEDIA .. "Icon")

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetText(ns.TITLE)

    versionText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    versionText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    local about = CreateParagraph(header,
        L["Pet battle teams for the Pet Journal: save, load and group teams, import Rematch team strings and level pets from a queue."],
        icon, -10)

    -- Everything below the description sits in one inset.
    local inset = CreateFrame("Frame", nil, view, "InsetFrameTemplate")
    local insetLeft, insetRight = ns.TeamsPanel.INSET_LEFT, ns.TeamsPanel.INSET_RIGHT
    inset:SetPoint("TOPLEFT", about, "BOTTOMLEFT", insetLeft - edge, -12)
    inset:SetPoint("BOTTOMRIGHT", insetRight, 26)
    local content = CreateFrame("Frame", nil, inset)
    content:SetPoint("TOPLEFT", edge - insetLeft, -10)
    content:SetPoint("BOTTOMRIGHT", -(edge - insetLeft), 10)

    -- Settings
    local settings = CreateSection(content, L["Settings"])

    -- A checkbox for the setting ns.db[key], below anchor, explained by tooltip.
    local function CreateCheckbox(key, label, tooltip, anchor, offsetX, offsetY)
        local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", offsetX, offsetY)
        check.Label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        check.Label:SetPoint("LEFT", check, "RIGHT", 2, 0)
        check.Label:SetPoint("RIGHT", content, "RIGHT")
        check.Label:SetJustifyH("LEFT")
        check.Label:SetText(label)
        check:SetScript("OnClick", function(button)
            ns.db[key] = button:GetChecked()
        end)
        ns.SetTooltip(check, label, tooltip, "ANCHOR_TOPLEFT")
        checkboxes[#checkboxes + 1] = { button = check, key = key }
        return check
    end

    local autoLoadCheck = CreateCheckbox("autoLoadTargetTeam", L["Load a target's team automatically"],
        L["Targeting a tamer or wild pet with exactly one team loads that team."],
        settings, -4, -HEADER_GAP + 2)
    local debugCheck = CreateCheckbox("debug", L["Debug messages in chat"],
        L["Shows team loading details in chat, for troubleshooting."], autoLoadCheck, 0, 0)

    -- Import & Export: teams from Rematch, and all teams as text.
    local transfer = CreateSection(content, L["Import & Export"], debugCheck)
    transfer:SetPoint("TOPLEFT", debugCheck, "BOTTOMLEFT", 4, -SECTION_GAP + 2)
    rematchText = CreateParagraph(content, "", transfer, -HEADER_GAP)

    rematchButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    rematchButton:SetPoint("TOPLEFT", rematchText, "BOTTOMLEFT", 0, -8)
    rematchButton:SetPoint("RIGHT", content, "CENTER", -4, 0)
    rematchButton:SetHeight(22)
    rematchButton:SetText(L["Import Rematch Teams"])
    rematchButton:SetScript("OnClick", ImportFromRematch)

    local exportButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    exportButton:SetPoint("LEFT", content, "CENTER", 4, 0)
    exportButton:SetPoint("TOP", rematchButton)
    exportButton:SetPoint("RIGHT")
    exportButton:SetHeight(22)
    exportButton:SetText(L["Export All Teams"])
    exportButton:SetScript("OnClick", function()
        ns.ExportDialog:Open(L["Export All Teams"], ns.Export.All())
    end)
    ns.SetTooltip(exportButton, L["Export All Teams"],
        L["All teams and groups as team strings, with notes and scripts. For backups or moving to Rematch."])

    -- Overview
    local overview = CreateSection(content, L["Overview"], rematchButton)
    statsText = CreateParagraph(content, "", overview, -HEADER_GAP)

    -- Commands
    local commands = CreateSection(content, L["Commands"], statsText)
    CreateParagraph(content,
        L["|cffffd100/lineup|r  open the Pet Journal\n|cffffd100/lineup debug|r  toggle debug messages"],
        commands, -HEADER_GAP)

    return view
end

function AboutView:Refresh()
    if not view or not view:IsVisible() then
        return
    end

    local versionLabel = L["Version "] .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or "?")
    -- The author comes from the TOC (## Author), the same value addon managers show.
    local author = C_AddOns.GetAddOnMetadata(addonName, "Author")
    versionText:SetText(author and format(L["%s · by %s"], versionLabel, author) or versionLabel)

    statsText:SetText(format(L["%d teams in %d groups\n%d pets in the leveling queue"],
        #ns.Teams:GetAll(), #ns.Teams:GetGroups(), #ns.LevelingQueue:Get()))
    for _, checkbox in ipairs(checkboxes) do
        checkbox.button:SetChecked(ns.db[checkbox.key])
    end

    local rematchLoaded = ns.Import.IsRematchAvailable()
    rematchButton:SetEnabled(rematchLoaded)
    rematchText:SetText(rematchLoaded
        and L["Copies all Rematch teams and groups into Lineup, with their tdBattlePetScript scripts."]
        or L["Enable Rematch and reload to import its teams, or paste the text of Rematch's \"Export All Teams\" into Import."])
end
