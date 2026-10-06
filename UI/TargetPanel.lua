local _, ns = ...
local Teams = ns.Teams

-- Small window above the Teams window: the current target with quick Load / Save for it.
local TargetPanel = {}
ns.TargetPanel = TargetPanel

-- Shared with the Teams window below, so both are the same width.
local PANEL_WIDTH = 340
local PANEL_HEIGHT = 110
local CONTENT_LEFT = 66 -- right of the template's portrait
-- The portrait sticks out past the frame's left edge; both docked windows leave this gap so it
-- clears the Collections window.
local OFFSET_X = 2 + 12

TargetPanel.HEIGHT = PANEL_HEIGHT
TargetPanel.WIDTH = PANEL_WIDTH
TargetPanel.OFFSET_X = OFFSET_X

local panel

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
        root:CreateTitle("Load team")
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
        ns:Print(format("Saved team \"%s\".", team.name))
        RefreshAll()
    end

    local teams = Teams:GetForTarget(npcID)
    if #teams == 0 then
        SaveNew()
        return
    end
    MenuUtil.CreateContextMenu(button, function(_, root)
        root:CreateTitle("Save current pets")
        for _, team in ipairs(teams) do
            root:CreateButton(format("Update \"%s\"", team.name), function()
                Teams:UpdateFromLoadout(team)
                ns:Print(format("Updated team \"%s\".", team.name))
                RefreshAll()
            end)
        end
        root:CreateDivider()
        root:CreateButton("Save as New Team", SaveNew)
    end)
end

local function SetButtonTooltip(button, title, text)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
end

function TargetPanel:Setup()
    panel = CreateFrame("Frame", "LineupTargetPanel", PetJournal, "ButtonFrameTemplate")
    panel:SetPoint("TOPLEFT", CollectionsJournal, "TOPRIGHT", OFFSET_X, 0)
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel.Inset:Hide()
    panel.CloseButton:Hide()
    panel:SetTitle("Target")

    panel.Name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.Name:SetPoint("TOPLEFT", CONTENT_LEFT, -32)
    panel.Name:SetPoint("RIGHT", -12, 0)
    panel.Name:SetJustifyH("LEFT")
    panel.Name:SetWordWrap(false)

    panel.Status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.Status:SetPoint("TOPLEFT", panel.Name, "BOTTOMLEFT", 0, -4)
    panel.Status:SetPoint("RIGHT", -12, 0)
    panel.Status:SetJustifyH("LEFT")
    panel.Status:SetWordWrap(false)

    panel.LoadButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.LoadButton:SetPoint("BOTTOMLEFT", CONTENT_LEFT, 10)
    panel.LoadButton:SetSize(100, 22)
    panel.LoadButton:SetText("Load")
    panel.LoadButton:SetScript("OnClick", LoadForTarget)
    SetButtonTooltip(panel.LoadButton, "Load for target", "Load this target's team into your journal.")

    panel.SaveButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.SaveButton:SetPoint("LEFT", panel.LoadButton, "RIGHT", 6, 0)
    panel.SaveButton:SetSize(100, 22)
    panel.SaveButton:SetText(SAVE)
    panel.SaveButton:SetScript("OnClick", SaveForTarget)
    SetButtonTooltip(panel.SaveButton, "Save for target", "Save the pets currently in your journal as a team for this target.")

    panel:SetScript("OnShow", function()
        TargetPanel:Refresh()
    end)
    self:Refresh()
end

function TargetPanel:GetFrame()
    return panel
end

function TargetPanel:Refresh()
    if not panel or not panel:IsVisible() then
        return
    end

    local npcID = ns.Target.npcID
    if not npcID or not UnitExists("target") then
        panel:SetPortraitToAsset("Interface\\CharacterFrame\\TempPortrait")
        panel.Name:SetText("No target")
        panel.Name:SetTextColor(GRAY_FONT_COLOR:GetRGB())
        panel.Status:SetText("Target a tamer or wild pet.")
        panel.LoadButton:Disable()
        panel.SaveButton:Disable()
        return
    end

    panel:SetPortraitToUnit("target")
    panel.Name:SetText(ns.Target.name or ("NPC " .. npcID))
    panel.Name:SetTextColor(NORMAL_FONT_COLOR:GetRGB())

    local numTeams = #Teams:GetForTarget(npcID)
    if numTeams == 0 then
        panel.Status:SetText("No teams for this target yet.")
    else
        panel.Status:SetText(GREEN_FONT_COLOR:WrapTextInColorCode(format(numTeams == 1 and "%d team" or "%d teams", numTeams)))
    end
    panel.LoadButton:SetEnabled(numTeams > 0)
    panel.SaveButton:Enable()
end
