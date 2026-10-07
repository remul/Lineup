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

    versionText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    versionText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    local about = CreateParagraph(content,
        L["Pet battle teams for Blizzard's Pet Journal: save and load teams, group them, import Rematch team strings (e.g. from Xu-Fu's Pet Guides) and keep an automatic leveling queue."],
        icon, -10)

    -- Settings
    local settings = CreateSection(content, L["Settings"], about)

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
        check:SetScript("OnEnter", function(button)
            GameTooltip:SetOwner(button, "ANCHOR_TOPLEFT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", GameTooltip_Hide)
        checkboxes[#checkboxes + 1] = { button = check, key = key }
        return check
    end

    local autoLoadCheck = CreateCheckbox("autoLoadTargetTeam", L["Load a target's team automatically"],
        L["When you target a tamer or wild pet that has exactly one team, that team is loaded right away."],
        settings, -4, -HEADER_GAP + 2)
    local debugCheck = CreateCheckbox("debug", L["Debug messages in chat"],
        L["Shows details about loading teams in chat, to help track down problems."], autoLoadCheck, 0, 0)

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
        and L["Copy all your Rematch teams and groups into Lineup, including pet battle scripts from tdBattlePetScript."]
        or L["Enable Rematch and reload to import its teams here. Or use Rematch's \"Export All Teams\" and paste the text into Import."])
end
