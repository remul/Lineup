local addonName, ns = ...
local L = ns.L

-- The Settings tab of the Lineup window: the settings and general info about the addon.
local AboutView = {}
ns.AboutView = AboutView

local view, versionText, statsText, debugCheck, rematchText, rematchButton

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

local function CreateParagraph(parent, text, anchor, offsetY)
    local paragraph = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    paragraph:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
    paragraph:SetPoint("RIGHT")
    paragraph:SetJustifyH("LEFT")
    paragraph:SetSpacing(2)
    paragraph:SetText(text)
    return paragraph
end

-- A section header like the Teams tab's, below anchor.
local function CreateSection(parent, text, anchor)
    local header = ns.TeamsPanel.CreateSectionHeader(parent, text)
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SECTION_GAP)
    header:SetPoint("RIGHT")
    return header
end

-- Builds the view inside parent (the Lineup window) and returns it; it starts hidden. Laid out
-- like the Teams tab: sections with a header line, without a box around them.
function AboutView:Create(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local inset = ns.TeamsPanel.SECTION_INSET
    local content = CreateFrame("Frame", nil, view)
    content:SetPoint("TOPLEFT", inset, -32)
    content:SetPoint("BOTTOMRIGHT", -inset, 30)

    -- Header: icon, name, version and what Lineup does.
    local icon = content:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT")
    icon:SetTexture(ns.MEDIA .. "Icon")

    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetText(ns.TITLE)

    versionText = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    versionText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    local about = CreateParagraph(content,
        L["Pet battle teams for Blizzard's Pet Journal: save and load teams, group them, import Rematch team strings (e.g. from Xu-Fu's Pet Guides) and keep an automatic leveling queue."],
        icon, -10)

    -- Settings
    local settings = CreateSection(content, L["Settings"], about)

    debugCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    debugCheck:SetSize(24, 24)
    debugCheck:SetPoint("TOPLEFT", settings, "BOTTOMLEFT", -4, -HEADER_GAP + 2)
    debugCheck.Label = debugCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    debugCheck.Label:SetPoint("LEFT", debugCheck, "RIGHT", 2, 0)
    debugCheck.Label:SetText(L["Debug messages in chat"])
    debugCheck:SetScript("OnClick", function(button)
        ns.db.debug = button:GetChecked()
    end)

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
    exportButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(L["Export All Teams"])
        GameTooltip:AddLine(L["All teams and groups as team strings (with notes and scripts), to back them up or move them to Rematch."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    exportButton:SetScript("OnLeave", GameTooltip_Hide)

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

    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or ""
    -- The packager replaces @project-version@ on release; until then this is a development copy.
    local versionLabel = version:find("^@") and L["Development version"] or (L["Version "] .. version)
    -- The author comes from the TOC (## Author), the same value addon managers show.
    local author = C_AddOns.GetAddOnMetadata(addonName, "Author")
    versionText:SetText(author and format(L["%s · by %s"], versionLabel, author) or versionLabel)

    statsText:SetText(format(L["%d teams in %d groups\n%d pets in the leveling queue"],
        #ns.Teams:GetAll(), #ns.Teams:GetGroups(), #ns.LevelingQueue:Get()))
    debugCheck:SetChecked(ns.db.debug)

    local rematchLoaded = ns.Import.IsRematchAvailable()
    rematchButton:SetEnabled(rematchLoaded)
    rematchText:SetText(rematchLoaded
        and L["Copy all your Rematch teams and groups into Lineup, including pet battle scripts from tdBattlePetScript."]
        or L["Enable Rematch and reload to import its teams here. Or use Rematch's \"Export All Teams\" and paste the text into Import."])
end
