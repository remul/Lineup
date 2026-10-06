local _, ns = ...
local L = ns.L
local Teams = ns.Teams

-- Middle section of the Lineup window: the loaded team, and the pets in the journal's loadout
-- (what actually goes into battle, random and leveling picks included) with their health. Also
-- whether the team's script will run, and Save / Revert while the journal differs from the team.
local CurrentSection = {}
ns.CurrentSection = CurrentSection

CurrentSection.HEIGHT = 110
local NUM_SLOTS = 3
local PET_ICON_SIZE = 30
local HEALTH_BAR_HEIGHT = 6
local CARD_SPACING = 6
-- Pets below this much health get an orange warning (dead pets always get a red one).
local LOW_HEALTH_PERCENT = 50

-- Healing hurt pets is left to Blizzard's own "Revive Battle Pets" button at the top of the
-- journal (casting needs a secure button, and one inside Lineup's window would lock it during
-- combat). Lineup points at it with a glow while a pet is hurt and the spell is ready.
local REVIVE_SPELL_ID = 125439
local BANDAGE_ITEM_ID = 86143

local SCRIPT_ICONS = {
    ok = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t ",
    warning = ns.HURT_ICON .. " ",
    error = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t ",
}
local SCRIPT_LABELS = {
    ok = L["Script ready"],
    warning = L["Script · check abilities"],
    error = L["Script · error"],
}

local section, healGlow
local currentTeam -- the loaded team, as last drawn
local cardPetIDs = {} -- [slot] = petID in the loadout, as last drawn
local injured = {}

-- Seconds until Revive Battle Pets is ready, 0 when it is (the global cooldown doesn't count).
local function GetReviveCooldown()
    local info = C_Spell.GetSpellCooldown(REVIVE_SPELL_ID)
    -- Cooldowns can be secret values (in combat), which addon code can't compare or add.
    if not info or not canaccessvalue(info.startTime) or not canaccessvalue(info.duration)
        or info.duration <= 1.5 then
        return 0
    end
    return max(0, info.startTime + info.duration - GetTime())
end

local function UpdateHealGlow()
    if healGlow then
        healGlow:SetShown(#injured > 0 and GetReviveCooldown() == 0)
    end
end

-- Hurt pets and how to heal them, for the health warning's tooltip.
local function AddHealthToTooltip()
    for _, pet in ipairs(injured) do
        local color = pet.dead and RED_FONT_COLOR or (pet.percent < LOW_HEALTH_PERCENT and ORANGE_FONT_COLOR) or HIGHLIGHT_FONT_COLOR
        local health = pet.dead and L["dead"] or format("%d%%", pet.percent)
        GameTooltip:AddDoubleLine(format(L["Slot %d: %s"], pet.slot, pet.name), health, color.r, color.g, color.b, color.r, color.g, color.b)
    end
    GameTooltip:AddLine(" ")
    local cooldown = GetReviveCooldown()
    if cooldown == 0 then
        GameTooltip:AddLine(L["Use \"Revive Battle Pets\" at the top of the journal to heal them."], 1, 1, 1, true)
    else
        GameTooltip:AddLine(format(L["Revive Battle Pets is ready in %s."], SecondsToTime(cooldown)), 1, 1, 1, true)
        local bandages = C_Item.GetItemCount(BANDAGE_ITEM_ID)
        if bandages > 0 then
            GameTooltip:AddLine(format(L["You have %d Battle Pet Bandages."], bandages), 1, 1, 1, true)
        end
    end
end

-- "☠ 1 pet dead" (red) or "⚠ 2 pets under half health" (orange), or "" when the loadout is fit
-- to fight. A dead pet can't battle at all, so that's the one shown when both apply.
local function DescribeHealth()
    local dead, low = 0, 0
    for _, pet in ipairs(injured) do
        if pet.dead then
            dead = dead + 1
        elseif pet.percent < LOW_HEALTH_PERCENT then
            low = low + 1
        end
    end
    if dead > 0 then
        return ns.DEAD_ICON .. " " .. RED_FONT_COLOR:WrapTextInColorCode(format(dead == 1 and L["%d pet dead"] or L["%d pets dead"], dead))
    elseif low > 0 then
        return ns.HURT_ICON .. " " .. ORANGE_FONT_COLOR:WrapTextInColorCode(format(low == 1 and L["%d pet under half health"] or L["%d pets under half health"], low))
    end
    return ""
end

-- Pet card: icon, name and a health bar for one loadout slot.
local function CreatePetCard(parent, slot)
    local card = CreateFrame("Button", nil, parent)
    card:SetHeight(PET_ICON_SIZE + 4)
    card:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    card.Icon = card:CreateTexture(nil, "ARTWORK")
    card.Icon:SetSize(PET_ICON_SIZE, PET_ICON_SIZE)
    card.Icon:SetPoint("LEFT", 2, 0)
    card.Border = card:CreateTexture(nil, "OVERLAY")
    card.Border:SetAllPoints(card.Icon)
    card.Border:SetTexture("Interface\\Common\\WhiteIconFrame")
    card.Level = card:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    card.Level:SetPoint("BOTTOMRIGHT", card.Icon, "BOTTOMRIGHT", 1, -1)

    card.Name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.Name:SetPoint("TOPLEFT", card.Icon, "TOPRIGHT", 5, -3)
    card.Name:SetPoint("RIGHT", -2, 0)
    card.Name:SetJustifyH("LEFT")
    card.Name:SetWordWrap(false)

    card.Health = CreateFrame("StatusBar", nil, card)
    card.Health:SetPoint("BOTTOMLEFT", card.Icon, "BOTTOMRIGHT", 5, 3)
    card.Health:SetPoint("RIGHT", -4, 0)
    card.Health:SetHeight(HEALTH_BAR_HEIGHT)
    card.Health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    card.Health:SetMinMaxValues(0, 1)
    local healthBackground = card.Health:CreateTexture(nil, "BACKGROUND")
    healthBackground:SetAllPoints()
    healthBackground:SetColorTexture(0, 0, 0, 0.6)

    card:SetScript("OnClick", function()
        if cardPetIDs[slot] then
            ns:SelectPetInJournal(cardPetIDs[slot])
        end
    end)
    card:SetScript("OnEnter", function()
        local petID = cardPetIDs[slot]
        if not petID then
            return
        end
        local _, customName, level, _, _, _, _, speciesName = C_PetJournal.GetPetInfoByPetID(petID)
        local health, maxHealth, _, _, rarity = C_PetJournal.GetPetStats(petID)
        GameTooltip:SetOwner(card, "ANCHOR_BOTTOM")
        GameTooltip:SetText(customName or speciesName, ns.GetRarityColor(rarity))
        GameTooltip:AddLine(format(L["Level %d"], level), 1, 1, 1)
        if health == 0 then
            GameTooltip:AddLine(L["Dead"], RED_FONT_COLOR:GetRGB())
        else
            GameTooltip:AddLine(format(L["Health: %d / %d (%d%%)"], health, maxHealth, floor(health / maxHealth * 100)), 1, 1, 1)
        end
        local _, ability1, ability2, ability3 = C_PetJournal.GetPetLoadOutInfo(slot)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Abilities"], NORMAL_FONT_COLOR:GetRGB())
        for _, abilityID in ipairs({ ability1, ability2, ability3 }) do
            local _, abilityName, abilityIcon = C_PetBattles.GetAbilityInfoByID(abilityID)
            GameTooltip:AddLine(format("|T%s:14:14|t %s", abilityIcon, abilityName), 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click to show it in the journal."], 0, 1, 0)
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", GameTooltip_Hide)
    return card
end

local function UpdatePetCard(card, slot)
    local petID = C_PetJournal.GetPetLoadOutInfo(slot)
    cardPetIDs[slot] = petID
    if not petID then
        card.Icon:SetTexture(nil)
        card.Border:Hide()
        card.Level:SetText("")
        card.Name:SetText(L["Empty slot"])
        card.Name:SetTextColor(GRAY_FONT_COLOR:GetRGB())
        card.Health:Hide()
        return
    end

    local _, customName, level, _, _, _, _, speciesName, icon = C_PetJournal.GetPetInfoByPetID(petID)
    local health, maxHealth, _, _, rarity = C_PetJournal.GetPetStats(petID)
    local fraction = maxHealth > 0 and health / maxHealth or 0
    card.Icon:SetTexture(icon)
    card.Icon:SetDesaturated(health == 0)
    card.Border:SetVertexColor(ns.GetRarityColor(rarity))
    card.Border:Show()
    card.Level:SetText(level < 25 and level or "")
    card.Name:SetText(customName or speciesName)
    card.Name:SetTextColor((health == 0 and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR):GetRGB())

    local color = fraction * 100 < LOW_HEALTH_PERCENT and ORANGE_FONT_COLOR or GREEN_FONT_COLOR
    card.Health:SetStatusBarColor(color.r, color.g, color.b, 0.9)
    card.Health:SetValue(fraction)
    card.Health:Show()
end

-- Builds the section inside parent and returns it (CurrentSection.HEIGHT tall; set its width).
function CurrentSection:Create(parent)
    section = CreateFrame("Frame", nil, parent)
    section:SetHeight(self.HEIGHT)

    local header = ns.TeamsPanel.CreateSectionHeader(section, L["Current"])
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")

    -- The loaded team's name; clicking it shows the team in the list. Save / Revert next to it.
    section.TeamLine = CreateFrame("Button", nil, section)
    section.TeamLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    section.TeamLine:SetPoint("RIGHT")
    section.TeamLine:SetHeight(22)

    local function CreateLineButton(text, tooltip, onClick)
        local button = CreateFrame("Button", nil, section.TeamLine, "UIPanelButtonTemplate")
        button:SetSize(62, 20)
        button:SetText(text)
        button:SetScript("OnClick", function()
            onClick(currentTeam)
        end)
        button:SetScript("OnEnter", function()
            GameTooltip:SetOwner(button, "ANCHOR_TOP")
            GameTooltip:SetText(text)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        return button
    end
    section.RevertButton = CreateLineButton(L["Revert"], L["Load the saved version of this team again."], function(team)
        Teams:Load(team)
    end)
    section.RevertButton:SetPoint("RIGHT")
    section.SaveButton = CreateLineButton(SAVE, L["Save the pets and abilities in your journal into this team."], function(team)
        Teams:UpdateFromLoadout(team)
        ns:Print(format(L["Saved changes to \"%s\"."], team.name))
        ns.TeamsPanel:Refresh()
    end)
    section.SaveButton:SetPoint("RIGHT", section.RevertButton, "LEFT", -4, 0)

    section.TeamName = section.TeamLine:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
    section.TeamName:SetPoint("LEFT", 4, 0)
    section.TeamName:SetJustifyH("LEFT")
    section.TeamName:SetWordWrap(false)

    section.TeamLine:SetScript("OnClick", function()
        if currentTeam then
            ns.TeamsPanel:ShowTeam(currentTeam)
        end
    end)
    section.TeamLine:SetScript("OnEnter", function(line)
        if currentTeam then
            GameTooltip:SetOwner(line, "ANCHOR_TOP")
            GameTooltip:SetText(currentTeam.name)
            GameTooltip:AddLine(L["Click to show it in the list."], 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    section.TeamLine:SetScript("OnLeave", GameTooltip_Hide)

    -- Three pet cards side by side.
    section.Cards = {}
    for slot = 1, NUM_SLOTS do
        local card = CreatePetCard(section, slot)
        if slot == 1 then
            card:SetPoint("TOPLEFT", section.TeamLine, "BOTTOMLEFT", 0, -4)
        else
            card:SetPoint("LEFT", section.Cards[slot - 1], "RIGHT", CARD_SPACING, 0)
        end
        section.Cards[slot] = card
    end
    section:SetScript("OnSizeChanged", function(_, width)
        local cardWidth = (width - CARD_SPACING * (NUM_SLOTS - 1)) / NUM_SLOTS
        for _, card in ipairs(section.Cards) do
            card:SetWidth(cardWidth)
        end
    end)

    -- Bottom line: the script's state on the left, the loadout's health on the right. Both explain
    -- themselves on hover.
    section.Script = CreateFrame("Frame", nil, section)
    section.Script:SetPoint("TOPLEFT", section.Cards[1], "BOTTOMLEFT", 2, -6)
    section.Script:SetSize(1, 16)
    section.Script.Text = section.Script:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    section.Script.Text:SetPoint("LEFT")
    section.Script:SetScript("OnEnter", function(frame)
        local team = currentTeam
        if not (team and team.script) then
            return
        end
        GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Script"])
        ns.Script.AddCheckToTooltip(GameTooltip, ns.Script.Check(team.script, team.pets))
        GameTooltip:Show()
    end)
    section.Script:SetScript("OnLeave", GameTooltip_Hide)

    section.Health = CreateFrame("Frame", nil, section)
    section.Health:SetPoint("TOPRIGHT", section.Cards[NUM_SLOTS], "BOTTOMRIGHT", -2, -6)
    section.Health:SetSize(1, 16)
    section.Health.Text = section.Health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    section.Health.Text:SetPoint("RIGHT")
    section.Health:SetScript("OnEnter", function(frame)
        if #injured == 0 then
            return
        end
        GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Pets in your loadout"])
        AddHealthToTooltip()
        GameTooltip:Show()
    end)
    section.Health:SetScript("OnLeave", GameTooltip_Hide)

    -- Pulsing glow around Blizzard's heal button, hidden along with it (e.g. while the journal is
    -- locked). The glow itself isn't protected, so showing it is fine during combat too.
    local healFrame = PetJournal.HealPetSpellFrame
    local healButton = healFrame and (healFrame.Button or healFrame)
    if healButton then
        healGlow = CreateFrame("Frame", nil, healFrame)
        healGlow:SetPoint("TOPLEFT", healButton, "TOPLEFT", -6, 6)
        healGlow:SetPoint("BOTTOMRIGHT", healButton, "BOTTOMRIGHT", 6, -6)
        healGlow:SetFrameLevel(healButton:GetFrameLevel() + 5)
        local texture = healGlow:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        texture:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        texture:SetBlendMode("ADD")
        local pulse = healGlow:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.25)
        fade:SetDuration(0.8)
        healGlow:SetScript("OnShow", function()
            pulse:Play()
        end)
        healGlow:SetScript("OnHide", function()
            pulse:Stop()
        end)
        healGlow:Hide()
        ns:RegisterEvent("SPELL_UPDATE_COOLDOWN", function()
            if healGlow:IsShown() or #injured > 0 then
                UpdateHealGlow()
            end
        end)
    end

    return section
end

-- Re-reads the loadout's health (for the glow on Blizzard's heal button, which shows on every tab)
-- and redraws the section when it's visible.
function CurrentSection:Refresh()
    -- Not while loading: the slots still hold the previous pets.
    injured = Teams:IsLoading() and {} or Teams:GetInjuredPets()
    UpdateHealGlow()
    if not section or not section:IsVisible() then
        return
    end

    local team = Teams:GetLoadedTeam()
    currentTeam = team
    local changed = team ~= nil and not Teams:IsLoading() and Teams:HasChanges(team)
    if team then
        local name = ns.TeamsPanel.SplitTeamName(team.name)
        section.TeamName:SetText(changed and (name .. ORANGE_FONT_COLOR:WrapTextInColorCode(L["  · changed"])) or name)
        section.TeamName:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    else
        section.TeamName:SetText(L["No team loaded"])
        section.TeamName:SetTextColor(GRAY_FONT_COLOR:GetRGB())
    end
    section.SaveButton:SetShown(changed)
    section.RevertButton:SetShown(changed)
    section.TeamName:SetPoint("RIGHT", changed and section.SaveButton or section.TeamLine, changed and "LEFT" or "RIGHT", -6, 0)

    for slot, card in ipairs(section.Cards) do
        UpdatePetCard(card, slot)
    end

    -- Script of the loaded team.
    local scriptText = ""
    if team and team.script then
        local status = ns.Script.Check(team.script, team.pets)
        local label = (SCRIPT_ICONS[status.level] or "") .. (SCRIPT_LABELS[status.level] or L["Script"])
        if status.level == "ok" and not ns.Script.CanRun() then
            scriptText = GRAY_FONT_COLOR:WrapTextInColorCode(L["Script"])
        else
            scriptText = status.color:WrapTextInColorCode(label)
        end
    elseif team then
        scriptText = GRAY_FONT_COLOR:WrapTextInColorCode(L["No script"])
    end
    section.Script.Text:SetText(scriptText)
    section.Script:SetWidth(max(1, section.Script.Text:GetStringWidth()))

    section.Health.Text:SetText(DescribeHealth())
    section.Health:SetWidth(max(1, section.Health.Text:GetStringWidth()))
end
