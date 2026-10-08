local _, ns = ...
local L = ns.L
local Teams = ns.Teams

-- Top section of the Lineup window: the current target, with quick Load / Save for it.
local TargetSection = {}
ns.TargetSection = TargetSection

TargetSection.HEIGHT = 46
local PORTRAIT_SIZE = 44
local BUTTON_WIDTH = 76

local section

local function RefreshAll()
    ns.TeamsPanel:Refresh()
end

local function LoadForTarget(button)
    local teams = Teams:GetForTarget(ns.Target.npcID)
    if #teams == 1 then
        Teams:Load(teams[1])
        RefreshAll()
        return
    end
    MenuUtil.CreateContextMenu(button, function(_, root)
        root:CreateTitle(L["Load team"])
        for _, team in ipairs(teams) do
            root:CreateButton(team.name, function()
                Teams:Load(team)
                RefreshAll()
            end)
        end
    end)
end

-- Saves the current pets for the target: a new team if it has none, otherwise pick one to update.
local function SaveForTarget(button)
    local npcID, name = ns.Target.npcID, ns.Target.name
    local function SaveNew()
        local team = Teams:CreateForTarget(npcID, name)
        ns:Print(format(L["Saved team \"%s\"."], team.name))
        RefreshAll()
    end

    local teams = Teams:GetForTarget(npcID)
    if #teams == 0 then
        SaveNew()
        return
    end
    MenuUtil.CreateContextMenu(button, function(_, root)
        root:CreateTitle(L["Save current pets"])
        for _, team in ipairs(teams) do
            root:CreateButton(format(L["Update \"%s\""], team.name), function()
                Teams:UpdateFromLoadout(team)
                ns:Print(format(L["Updated team \"%s\"."], team.name))
                RefreshAll()
            end)
        end
        root:CreateDivider()
        root:CreateButton(L["Save as New Team"], SaveNew)
    end)
end

-- The tooltip shows while the button is disabled too.
local function SetButtonTooltip(button, title, text)
    button:SetMotionScriptsWhileDisabled(true)
    ns.SetTooltip(button, title, text)
end

-- Builds the section inside parent and returns it (TargetSection.HEIGHT tall; set its width).
function TargetSection:Create(parent)
    section = CreateFrame("Frame", nil, parent)
    section:SetHeight(self.HEIGHT)

    -- Round portrait of the target.
    section.Portrait = section:CreateTexture(nil, "ARTWORK")
    section.Portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    section.Portrait:SetPoint("LEFT", 4, 0)
    local mask = section:CreateMaskTexture()
    mask:SetAllPoints(section.Portrait)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    section.Portrait:AddMaskTexture(mask)

    section.LoadButton = CreateFrame("Button", nil, section, "UIPanelButtonTemplate")
    section.LoadButton:SetPoint("TOPRIGHT")
    section.LoadButton:SetSize(BUTTON_WIDTH, 22)
    section.LoadButton:SetText(L["Load"])
    section.LoadButton:SetScript("OnClick", LoadForTarget)
    SetButtonTooltip(section.LoadButton, L["Load for target"], L["Load this target's team into your journal."])

    section.SaveButton = CreateFrame("Button", nil, section, "UIPanelButtonTemplate")
    section.SaveButton:SetPoint("TOP", section.LoadButton, "BOTTOM", 0, -2)
    section.SaveButton:SetSize(BUTTON_WIDTH, 22)
    section.SaveButton:SetText(SAVE)
    section.SaveButton:SetScript("OnClick", SaveForTarget)
    SetButtonTooltip(section.SaveButton, L["Save for target"], L["Save your journal's pets as a team for this target."])

    section.Name = section:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    section.Name:SetPoint("TOPLEFT", section.Portrait, "TOPRIGHT", 10, -6)
    section.Name:SetPoint("RIGHT", section.LoadButton, "LEFT", -8, 0)
    section.Name:SetJustifyH("LEFT")
    section.Name:SetWordWrap(false)

    section.Status = section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    section.Status:SetPoint("TOPLEFT", section.Name, "BOTTOMLEFT", 0, -5)
    section.Status:SetPoint("RIGHT", section.LoadButton, "LEFT", -8, 0)
    section.Status:SetJustifyH("LEFT")
    section.Status:SetWordWrap(false)

    return section
end

function TargetSection:Refresh()
    if not section or not section:IsVisible() then
        return
    end

    local npcID = ns.Target.npcID
    if not npcID or not UnitExists("target") then
        section.Portrait:SetTexture("Interface\\CharacterFrame\\TempPortrait")
        section.Name:SetText(L["No target"])
        section.Name:SetTextColor(GRAY_FONT_COLOR:GetRGB())
        section.Status:SetText(L["Target a tamer or wild pet."])
        section.LoadButton:Disable()
        section.SaveButton:Disable()
        return
    end

    SetPortraitTexture(section.Portrait, "target")
    section.Name:SetText(ns.Target.name or (L["NPC "] .. npcID))
    section.Name:SetTextColor(NORMAL_FONT_COLOR:GetRGB())

    local numTeams = #Teams:GetForTarget(npcID)
    if numTeams == 0 then
        section.Status:SetText(L["No teams for this target yet."])
    else
        section.Status:SetText(GREEN_FONT_COLOR:WrapTextInColorCode(format(numTeams == 1 and L["%d team"] or L["%d teams"], numTeams)))
    end
    section.LoadButton:SetEnabled(numTeams > 0)
    section.SaveButton:Enable()
end
