local addonName, ns = ...
local L = ns.L

-- The "Lineup" tab of the Teams window: general info about the addon and its settings.
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

local function CreateHeading(parent, text, anchor, offsetY)
    local heading = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
    heading:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
    heading:SetText(text)
    return heading
end

local function CreateParagraph(parent, text, anchor, offsetY)
    local paragraph = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    paragraph:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
    paragraph:SetPoint("RIGHT", -12, 0)
    paragraph:SetJustifyH("LEFT")
    paragraph:SetSpacing(2)
    paragraph:SetText(text)
    return paragraph
end

-- Builds the view inside parent (the Teams window) and returns it; it starts hidden.
function AboutView:Create(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    local inset = CreateFrame("Frame", nil, view, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 4, -26)
    inset:SetPoint("BOTTOMRIGHT", -6, 26)

    local content = CreateFrame("Frame", nil, inset)
    content:SetPoint("TOPLEFT", 12, -12)
    content:SetPoint("BOTTOMRIGHT", -12, 12)

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
        icon, -12)

    local overview = CreateHeading(content, L["Overview"], about, -16)
    statsText = CreateParagraph(content, "", overview, -6)

    local commands = CreateHeading(content, L["Commands"], statsText, -16)
    local commandList = CreateParagraph(content,
        L["|cffffd100/lineup|r  open the Pet Journal\n|cffffd100/lineup debug|r  toggle debug messages"],
        commands, -6)

    local rematch = CreateHeading(content, L["Rematch"], commandList, -16)
    rematchText = CreateParagraph(content, "", rematch, -6)

    rematchButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    rematchButton:SetPoint("TOPLEFT", rematchText, "BOTTOMLEFT", 0, -8)
    rematchButton:SetSize(180, 22)
    rematchButton:SetText(L["Import Rematch Teams"])
    rematchButton:SetScript("OnClick", ImportFromRematch)

    local settings = CreateHeading(content, L["Settings"], rematchButton, -16)

    debugCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    debugCheck:SetSize(24, 24)
    debugCheck:SetPoint("TOPLEFT", settings, "BOTTOMLEFT", -4, -4)
    debugCheck.Label = debugCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    debugCheck.Label:SetPoint("LEFT", debugCheck, "RIGHT", 2, 0)
    debugCheck.Label:SetText(L["Debug messages in chat"])
    debugCheck:SetScript("OnClick", function(button)
        ns.db.debug = button:GetChecked()
    end)

    return view
end

function AboutView:Refresh()
    if not view or not view:IsVisible() then
        return
    end

    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or ""
    -- The packager replaces @project-version@ on release; until then this is a development copy.
    versionText:SetText(version:find("^@") and L["Development version"] or (L["Version "] .. version))

    statsText:SetText(format(L["%d teams in %d groups\n%d pets in the leveling queue"],
        #ns.Teams:GetAll(), #ns.Teams:GetGroups(), #ns.LevelingQueue:Get()))
    debugCheck:SetChecked(ns.db.debug)

    local rematchLoaded = ns.Import.IsRematchAvailable()
    rematchButton:SetEnabled(rematchLoaded)
    rematchText:SetText(rematchLoaded
        and L["Copy all your Rematch teams and groups into Lineup, including pet battle scripts from tdBattlePetScript."]
        or L["Enable Rematch and reload to import its teams here. Or use Rematch's \"Export All Teams\" and paste the text into Import."])
end
