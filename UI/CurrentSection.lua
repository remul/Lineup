local _, ns = ...
local L = ns.L
local Teams = ns.Teams

-- Middle section of the Lineup window: the loaded team, and the pets in the journal's loadout
-- (what actually goes into battle, random and leveling picks included) with their health. Also
-- whether the team's script will run, and Save / Revert while the journal differs from the team.
local CurrentSection = {}
ns.CurrentSection = CurrentSection

CurrentSection.HEIGHT = 86
local NUM_SLOTS = 3
local PET_ICON_SIZE = 30
-- Health is shown like on Blizzard's pet cards: the heart from the pet battle stat icons.
local STAT_ICONS = "Interface\\PetBattles\\PetBattle-StatIcons"
local SKULL_ICON = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local HEALTH_ICON_SIZE = 12
local CARD_SPACING = 6
-- Muted text ("No script", "Empty slot"): lighter than Blizzard's grey, which disappears into the grey end of the
-- section's background (see TeamsPanel).
local MUTED_COLOR = CreateColor(0.75, 0.75, 0.75)
-- Pets below this much health get an orange warning (dead pets always get a red one).
local LOW_HEALTH_PERCENT = 50

-- Healing hurt pets is left to Blizzard's own "Revive Battle Pets" button at the top of the
-- journal (casting needs a secure button, and one inside Lineup's window would lock it during
-- combat). Lineup points at it with a glow while a pet is hurt and the spell is ready.

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
    local info = C_Spell.GetSpellCooldown(ns.REVIVE_SPELL_ID)
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
        local bandages = C_Item.GetItemCount(ns.BANDAGE_ITEM_ID)
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

-- Pet card: icon, name and health ("♥ 1000 / 1000", or a skull and "Dead") for one loadout slot.
local function CreatePetCard(parent, slot)
    local card = CreateFrame("Button", nil, parent)
    card:SetHeight(PET_ICON_SIZE + 8)
    -- A card like the team list's.
    ns.CreateCardFill(card)
    card.Outline = ns.CreateCardOutline(card)

    card.Icon = card:CreateTexture(nil, "ARTWORK")
    card.Icon:SetSize(PET_ICON_SIZE, PET_ICON_SIZE)
    card.Icon:SetPoint("LEFT", 4, 0)
    card.Border = card:CreateTexture(nil, "OVERLAY")
    card.Border:SetAllPoints(card.Icon)
    card.Border:SetTexture("Interface\\Common\\WhiteIconFrame")
    card.Level = card:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    card.Level:SetPoint("BOTTOMRIGHT", card.Icon, "BOTTOMRIGHT", 1, -1)

    card.Name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.Name:SetPoint("TOPLEFT", card.Icon, "TOPRIGHT", 5, -3)
    card.Name:SetPoint("RIGHT", -4, 0)
    card.Name:SetJustifyH("LEFT")
    card.Name:SetWordWrap(false)

    card.HealthIcon = card:CreateTexture(nil, "ARTWORK")
    card.HealthIcon:SetSize(HEALTH_ICON_SIZE, HEALTH_ICON_SIZE)
    card.HealthIcon:SetPoint("BOTTOMLEFT", card.Icon, "BOTTOMRIGHT", 4, 1)
    card.HealthText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.HealthText:SetPoint("LEFT", card.HealthIcon, "RIGHT", 3, 0)
    card.HealthText:SetPoint("RIGHT", -4, 0)
    card.HealthText:SetJustifyH("LEFT")
    card.HealthText:SetWordWrap(false)

    card:SetScript("OnClick", function()
        if cardPetIDs[slot] then
            ns:SelectPetInJournal(cardPetIDs[slot])
        end
    end)
    card:SetScript("OnEnter", function()
        ns.UpdateCardOutline(card.Outline, false, true)
        local petID = cardPetIDs[slot]
        if not petID then
            return
        end
        local _, customName, level, _, _, _, _, speciesName = C_PetJournal.GetPetInfoByPetID(petID)
        local health, maxHealth, _, _, rarity = C_PetJournal.GetPetStats(petID)
        GameTooltip:SetOwner(card, "ANCHOR_BOTTOM")
        GameTooltip:SetText(customName or speciesName, ns.GetRarityColor(rarity))
        local breed = ns.Breeds.DescribePet(petID)
        GameTooltip:AddLine(format(L["Level %d"], level) .. (breed and (" · " .. breed) or ""), 1, 1, 1)
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
    card:SetScript("OnLeave", function()
        ns.UpdateCardOutline(card.Outline, false, false)
        GameTooltip:Hide()
    end)
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
        card.Name:SetTextColor(MUTED_COLOR:GetRGB())
        card.HealthIcon:Hide()
        card.HealthText:SetText("")
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

    if health == 0 then
        card.HealthIcon:SetTexture(SKULL_ICON)
        card.HealthIcon:SetTexCoord(0, 1, 0, 1)
        card.HealthText:SetText(L["Dead"])
        card.HealthText:SetTextColor(RED_FONT_COLOR:GetRGB())
    else
        card.HealthIcon:SetTexture(STAT_ICONS)
        card.HealthIcon:SetTexCoord(0.5, 1, 0.5, 1)
        card.HealthText:SetText(format("%d / %d", health, maxHealth))
        card.HealthText:SetTextColor((fraction * 100 < LOW_HEALTH_PERCENT and ORANGE_FONT_COLOR or HIGHLIGHT_FONT_COLOR):GetRGB())
    end
    card.HealthIcon:Show()
end

-- Builds the section inside parent and returns it (CurrentSection.HEIGHT tall; set its width).
function CurrentSection:Create(parent)
    section = CreateFrame("Frame", nil, parent)
    section:SetHeight(self.HEIGHT)

    -- The loaded team's name; clicking it shows the team in the list. Save / Revert next to it.
    section.TeamLine = CreateFrame("Button", nil, section)
    section.TeamLine:SetPoint("TOPLEFT")
    section.TeamLine:SetPoint("RIGHT")
    section.TeamLine:SetHeight(22)

    local function CreateLineButton(text, tooltip, onClick)
        local button = CreateFrame("Button", nil, section.TeamLine, "UIPanelButtonTemplate")
        button:SetSize(62, 20)
        button:SetText(text)
        button:SetScript("OnClick", function()
            onClick(currentTeam)
        end)
        ns.SetTooltip(button, text, tooltip)
        return button
    end
    section.RevertButton = CreateLineButton(L["Revert"], L["Reload the saved version of this team."], function(team)
        Teams:Load(team)
    end)
    section.RevertButton:SetPoint("RIGHT")
    section.SaveButton = CreateLineButton(SAVE, L["Save your journal's pets and abilities to this team."], function(team)
        Teams:UpdateFromLoadout(team)
        ns:Print(format(L["Saved changes to \"%s\"."], team.name))
        ns.TeamsPanel:Refresh()
    end)
    section.SaveButton:SetPoint("RIGHT", section.RevertButton, "LEFT", -4, 0)

    section.TeamName = section.TeamLine:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
    section.TeamName:SetPoint("LEFT", 4, 0)
    section.TeamName:SetJustifyH("LEFT")
    section.TeamName:SetWordWrap(false)
    -- "changed" in small orange after the name; a long name is shortened before this is.
    section.TeamState = section.TeamLine:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    section.TeamState:SetPoint("LEFT", section.TeamName, "RIGHT", 6, -1)
    section.TeamState:SetTextColor(ORANGE_FONT_COLOR:GetRGB())
    section.TeamState:SetText(L["changed"])

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
        section.TeamName:SetText((ns.TeamsPanel.SplitTeamName(team.name)))
        section.TeamName:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    else
        section.TeamName:SetText(L["No team loaded"])
        section.TeamName:SetTextColor(GRAY_FONT_COLOR:GetRGB())
    end
    section.SaveButton:SetShown(changed)
    section.RevertButton:SetShown(changed)
    section.TeamState:SetShown(changed)

    -- The name gets the room left of Save / Revert and "changed", and is cut short beyond that.
    local room = section.TeamLine:GetWidth() - 4
    if changed then
        room = room - section.SaveButton:GetWidth() - 4 - section.RevertButton:GetWidth() - 6
            - section.TeamState:GetStringWidth() - 6
    end
    section.TeamName:SetWidth(max(1, min(section.TeamName:GetUnboundedStringWidth(), room)))

    for slot, card in ipairs(section.Cards) do
        UpdatePetCard(card, slot)
    end

    -- Script of the loaded team.
    local scriptText = ""
    if team and team.script then
        local status = ns.Script.Check(team.script, team.pets)
        local label = (SCRIPT_ICONS[status.level] or "") .. (SCRIPT_LABELS[status.level] or L["Script"])
        if status.level == "ok" and not ns.Script.CanRun() then
            scriptText = MUTED_COLOR:WrapTextInColorCode(L["Script"])
        else
            scriptText = status.color:WrapTextInColorCode(label)
        end
    elseif team then
        scriptText = MUTED_COLOR:WrapTextInColorCode(L["No script"])
    end
    section.Script.Text:SetText(scriptText)
    section.Script:SetWidth(max(1, section.Script.Text:GetStringWidth()))

    section.Health.Text:SetText(DescribeHealth())
    section.Health:SetWidth(max(1, section.Health.Text:GetStringWidth()))
end
