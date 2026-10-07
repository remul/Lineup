local _, ns = ...
local L = ns.L

-- Window next to the team editor for choosing a team pet without the Pet Journal: your battle pets,
-- highest level first, searchable by name, species or ability (like the journal's search) and
-- filtered by family, "strong vs." and
-- "tough vs." an enemy family, and level 25. Buttons below set a leveling slot, a random level 25
-- pet (of any or one family), or an empty slot. Filters stay set until the game is reloaded.
local PetPicker = {}
ns.PetPicker = PetPicker

local PICKER_WIDTH = 340
local PICKER_HEIGHT = 470
local ROW_HEIGHT = 38
local ICON_SIZE = 30
-- The species' six abilities in a 3 x 2 grid, like the journal: each column is an ability slot,
-- the top row its first ability and the bottom row the other one.
local ABILITY_SIZE = 15
local ABILITY_SPACING = 2
local FAMILY_BUTTON_SIZE = 20
local FAMILY_BUTTON_SPACING = 6

local picker, searchBox, scrollBox, noResults, strongButton, toughButton, maxLevelCheck
local familyButtons = {}
local onSelect, taken

-- Filters: families shown ([petType] = true; none = all), enemy family the pet should be strong or
-- tough against (0 = any), level 25 only.
local families = {}
local strongVs, toughVs = 0, 0
local maxLevelOnly = false

-- A species' abilities: { ids = { six abilityIDs }, levels = { level each unlocks at },
-- names = { lowercase names }, types = { family of each }, strongAgainst = { [family] = true } }.
-- Fixed game data, so it's kept.
local abilitiesBySpecies = {}

local function GetSpeciesAbilities(speciesID)
    local abilities = abilitiesBySpecies[speciesID]
    if not abilities then
        local ids, levels = C_PetJournal.GetPetAbilityList(speciesID)
        abilities = { ids = ids, levels = levels, names = {}, types = {}, strongAgainst = {} }
        for index, abilityID in ipairs(ids) do
            local _, name, _, _, _, _, abilityType = C_PetBattles.GetAbilityInfoByID(abilityID)
            abilities.names[index] = (name or ""):lower()
            abilities.types[index] = abilityType
            if ns.STRONG_AGAINST[abilityType] then
                abilities.strongAgainst[ns.STRONG_AGAINST[abilityType]] = true
            end
        end
        abilitiesBySpecies[speciesID] = abilities
    end
    return abilities
end

-- True if the (lowercase) search is part of one of the species' ability names.
local function HasAbilityMatching(speciesID, query)
    for _, name in ipairs(GetSpeciesAbilities(speciesID).names) do
        if name:find(query, 1, true) then
            return true
        end
    end
    return false
end

local function PassesFilters(pet)
    if next(families) and not families[pet.petType] then
        return false
    elseif maxLevelOnly and pet.level < 25 then
        return false
    elseif strongVs ~= 0 and not GetSpeciesAbilities(pet.speciesID).strongAgainst[strongVs] then
        return false
    end
    -- Tough: attacks of the enemy's family do less damage to the pet's family.
    return toughVs == 0 or ns.WEAK_AGAINST[toughVs] == pet.petType
end

-- Battle pets matching the filters and the (lowercase) search in their name, species name or one
-- of their abilities, highest level and rarity first.
local function GetPets(query)
    local results = {}
    for _, pet in ipairs(ns.Roster:GetOwnedPets()) do
        if pet.canBattle and PassesFilters(pet) then
            local speciesName = ns.GetSpeciesInfo(pet.speciesID) or ""
            if not query or pet.name:lower():find(query, 1, true) or speciesName:lower():find(query, 1, true)
                or HasAbilityMatching(pet.speciesID, query) then
                results[#results + 1] = pet
            end
        end
    end
    table.sort(results, function(a, b)
        if a.level ~= b.level then
            return a.level > b.level
        elseif a.rarity ~= b.rarity then
            return a.rarity > b.rarity
        end
        return a.name < b.name
    end)
    return results
end

-- "Strong vs. [icon]" on the filter buttons, or just "Strong vs." without a family.
local function UpdateVsButton(button, label, petType)
    button:SetText(petType ~= 0 and format("%s |T%s:14:14|t", label, ns.GetFamilyIcon(petType)) or label)
end

local function UpdateFilterControls()
    local all = not next(families)
    for petType, button in ipairs(familyButtons) do
        local checked = families[petType] == true
        button.Selected:SetShown(checked)
        button.Icon:SetDesaturated(not all and not checked)
        button.Icon:SetAlpha((all or checked) and 1 or 0.5)
    end
    UpdateVsButton(strongButton, L["Strong vs."], strongVs)
    UpdateVsButton(toughButton, L["Tough vs."], toughVs)
    maxLevelCheck:SetChecked(maxLevelOnly)
end

local currentQuery -- the search, lowercase, or nil

local function Refresh()
    UpdateFilterControls()
    local query = strtrim(searchBox:GetText()):lower()
    currentQuery = query ~= "" and query or nil
    local pets = GetPets(currentQuery)
    scrollBox:SetDataProvider(CreateDataProvider(pets), ScrollBoxConstants.RetainScrollPosition)
    noResults:SetShown(#pets == 0)
end

-- Blizzard's own ability tooltip (as in the journal), or the ability's name without it.
local function ShowAbilityTooltip(owner, abilityID, speciesID, petID)
    if PetJournal_ShowAbilityTooltip and PetJournalPrimaryAbilityTooltip then
        PetJournal_ShowAbilityTooltip(owner, abilityID, speciesID, petID)
        PetJournalPrimaryAbilityTooltip:SetFrameStrata("TOOLTIP")
    else
        local _, name = C_PetBattles.GetAbilityInfoByID(abilityID)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(name)
        GameTooltip:Show()
    end
end

local function HideAbilityTooltip(owner)
    if PetJournal_HideAbilityTooltip and PetJournalPrimaryAbilityTooltip then
        PetJournal_HideAbilityTooltip(owner)
    else
        GameTooltip:Hide()
    end
end

-- What each ability icon shows: [icon frame] = { abilityID, speciesID, petID }.
local abilityOfIcon = {}

local function CreateAbilityIcons(row)
    row.Abilities = {}
    for index = 1, 6 do
        local column, line = (index - 1) % 3, index > 3 and 1 or 0
        local ability = CreateFrame("Frame", nil, row)
        ability:SetSize(ABILITY_SIZE, ABILITY_SIZE)
        ability:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6 - (2 - column) * (ABILITY_SIZE + ABILITY_SPACING),
            -(ROW_HEIGHT - 2 * ABILITY_SIZE - ABILITY_SPACING) / 2 - line * (ABILITY_SIZE + ABILITY_SPACING))
        ability.Icon = ability:CreateTexture(nil, "ARTWORK")
        ability.Icon:SetAllPoints()
        ability.Border = ability:CreateTexture(nil, "OVERLAY")
        ability.Border:SetPoint("TOPLEFT", -1, 1)
        ability.Border:SetPoint("BOTTOMRIGHT", 1, -1)
        ability.Border:SetTexture("Interface\\Common\\WhiteIconFrame")
        ability:SetScript("OnEnter", function(frame)
            local shown = abilityOfIcon[frame]
            ShowAbilityTooltip(frame, shown.abilityID, shown.speciesID, shown.petID)
        end)
        ability:SetScript("OnLeave", HideAbilityTooltip)
        row.Abilities[index] = ability
    end
end

-- Abilities the pet hasn't learned yet (by level) are dimmed. A green border marks abilities strong
-- against the "Strong vs." family, a gold one abilities matching the search.
local function UpdateAbilityIcons(row, pet)
    local abilities = GetSpeciesAbilities(pet.speciesID)
    for index, ability in ipairs(row.Abilities) do
        local abilityID = abilities.ids[index]
        abilityOfIcon[ability] = { abilityID = abilityID, speciesID = pet.speciesID, petID = pet.petID }
        if abilityID then
            local _, _, icon = C_PetBattles.GetAbilityInfoByID(abilityID)
            local learned = pet.level >= (abilities.levels[index] or 1)
            ability.Icon:SetTexture(icon)
            ability.Icon:SetDesaturated(not learned)
            ability.Icon:SetAlpha(learned and 1 or 0.5)
            local strong = strongVs ~= 0 and ns.STRONG_AGAINST[abilities.types[index]] == strongVs
            local matches = currentQuery and abilities.names[index]:find(currentQuery, 1, true)
            if strong then
                ability.Border:SetVertexColor(GREEN_FONT_COLOR:GetRGB())
            elseif matches then
                ability.Border:SetVertexColor(NORMAL_FONT_COLOR:GetRGB())
            end
            ability.Border:SetShown(strong or matches ~= nil)
            ability:Show()
        else
            ability:Hide()
        end
    end
end

-- Row: icon with rarity border, name, level and family, and the species' abilities. Pets already in
-- the team are dimmed.
local function InitRow(row, pet)
    if not row.Icon then
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.Icon = row:CreateTexture(nil, "ARTWORK")
        row.Icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.Icon:SetPoint("LEFT", 4, 0)
        row.Border = row:CreateTexture(nil, "OVERLAY")
        row.Border:SetAllPoints(row.Icon)
        row.Border:SetTexture("Interface\\Common\\WhiteIconFrame")
        CreateAbilityIcons(row)
        local abilitiesLeft = row.Abilities[1]
        row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, -2)
        row.Name:SetPoint("RIGHT", abilitiesLeft, "LEFT", -6, 0)
        row.Name:SetJustifyH("LEFT")
        row.Name:SetWordWrap(false)
        row.Details = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.Details:SetPoint("BOTTOMLEFT", row.Icon, "BOTTOMRIGHT", 8, 2)
        row.Details:SetPoint("RIGHT", abilitiesLeft, "LEFT", -6, 0)
        row.Details:SetJustifyH("LEFT")
        row.Details:SetWordWrap(false)
        row:SetScript("OnLeave", GameTooltip_Hide)
    end

    local _, _, _, _, _, _, _, speciesName, icon = C_PetJournal.GetPetInfoByPetID(pet.petID)
    local isTaken = taken[pet.petID] == true
    row.Icon:SetTexture(icon)
    row.Icon:SetDesaturated(isTaken)
    row.Border:SetVertexColor(ns.GetRarityColor(pet.rarity))
    row.Name:SetText(pet.name)
    row.Name:SetTextColor((isTaken and GRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR):GetRGB())
    row.Details:SetText(format("%s · |T%s:12:12|t %s", format(L["Level %d"], pet.level),
        ns.GetFamilyIcon(pet.petType), ns.GetFamilyName(pet.petType)))
    UpdateAbilityIcons(row, pet)
    row:SetEnabled(not isTaken)
    row:SetMotionScriptsWhileDisabled(true)

    row:SetScript("OnClick", function()
        picker:Hide()
        onSelect(pet)
    end)
    row:SetScript("OnEnter", function()
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(pet.name, ns.GetRarityColor(pet.rarity))
        if speciesName and speciesName ~= pet.name then
            GameTooltip:AddLine(speciesName, 1, 1, 1)
        end
        GameTooltip:AddLine(format(L["Level %d"], pet.level) .. " · " .. ns.GetFamilyName(pet.petType), 1, 1, 1)
        if isTaken then
            GameTooltip:AddLine(L["Already in this team."], RED_FONT_COLOR:GetRGB())
        end
        GameTooltip:Show()
    end)
end

local function CreatePicker(parent)
    picker = CreateFrame("Frame", "LineupPetPicker", parent, "ButtonFrameTemplate")
    picker:SetSize(PICKER_WIDTH, PICKER_HEIGHT)
    picker:SetToplevel(true)
    picker:EnableMouse(true)
    ButtonFrameTemplate_HidePortrait(picker)
    picker.Inset:Hide()
    tinsert(UISpecialFrames, picker:GetName())

    searchBox = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
    searchBox:SetPoint("TOPLEFT", 16, -30)
    searchBox:SetPoint("RIGHT", -12, 0)
    searchBox:SetHeight(22)
    searchBox:SetAutoFocus(false)
    searchBox.Instructions:SetText(L["Search pets and abilities"])
    searchBox:HookScript("OnTextChanged", Refresh)

    -- Family icons, like the row above the journal's list: a click on an unfiltered list shows only
    -- that family, further clicks add or remove families, right-click shows all again.
    for petType = 1, ns.NUM_FAMILIES do
        local button = CreateFrame("Button", nil, picker)
        button:SetSize(FAMILY_BUTTON_SIZE, FAMILY_BUTTON_SIZE)
        button:SetPoint("TOPLEFT", 14 + (petType - 1) * (FAMILY_BUTTON_SIZE + FAMILY_BUTTON_SPACING), -60)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button.Icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon:SetAllPoints()
        button.Icon:SetTexture(ns.GetFamilyIcon(petType))
        button.Selected = button:CreateTexture(nil, "OVERLAY")
        button.Selected:SetPoint("TOPLEFT", -3, 3)
        button.Selected:SetPoint("BOTTOMRIGHT", 3, -3)
        button.Selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        button.Selected:SetBlendMode("ADD")
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then
                wipe(families)
            else
                families[petType] = not families[petType] or nil
            end
            Refresh()
        end)
        button:SetScript("OnEnter", function()
            GameTooltip:SetOwner(button, "ANCHOR_TOP")
            GameTooltip:SetText(ns.GetFamilyName(petType))
            GameTooltip:AddLine(L["Click to filter by this family."], 1, 1, 1)
            GameTooltip:AddLine(L["Right-click to show all families."], 1, 1, 1)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        familyButtons[petType] = button
    end

    -- Strong vs. / Tough vs. an enemy family, and level 25 only.
    local function CreateVsButton(label, tooltip, get, set)
        local button = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
        button:SetSize(118, 22)
        button:SetScript("OnClick", function()
            MenuUtil.CreateContextMenu(button, function(_, root)
                root:CreateTitle(label)
                local function IsSelected(petType)
                    return get() == petType
                end
                local function Select(petType)
                    set(petType)
                    Refresh()
                end
                root:CreateRadio(L["Any family"], IsSelected, Select, 0)
                for petType = 1, ns.NUM_FAMILIES do
                    root:CreateRadio(format("|T%s:16:16|t %s", ns.GetFamilyIcon(petType), ns.GetFamilyName(petType)),
                        IsSelected, Select, petType)
                end
            end)
        end)
        button:SetScript("OnEnter", function()
            GameTooltip:SetOwner(button, "ANCHOR_TOP")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        return button
    end
    strongButton = CreateVsButton(L["Strong vs."], L["Pets that can learn an ability doing extra damage to this family."],
        function() return strongVs end, function(petType) strongVs = petType end)
    strongButton:SetPoint("TOPLEFT", 10, -88)
    toughButton = CreateVsButton(L["Tough vs."], L["Pets whose family takes less damage from this family's attacks."],
        function() return toughVs end, function(petType) toughVs = petType end)
    toughButton:SetPoint("LEFT", strongButton, "RIGHT", 4, 0)

    maxLevelCheck = CreateFrame("CheckButton", nil, picker, "UICheckButtonTemplate")
    maxLevelCheck:SetSize(24, 24)
    maxLevelCheck:SetPoint("LEFT", toughButton, "RIGHT", 6, 0)
    maxLevelCheck.Label = maxLevelCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    maxLevelCheck.Label:SetPoint("LEFT", maxLevelCheck, "RIGHT", 0, 0)
    maxLevelCheck.Label:SetText(L["Level 25"])
    maxLevelCheck:SetScript("OnClick", function(button)
        maxLevelOnly = button:GetChecked()
        Refresh()
    end)

    local inset = CreateFrame("Frame", nil, picker, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", 8, -116)
    inset:SetPoint("BOTTOMRIGHT", -8, 36)

    -- Slots without a specific pet, in three equal buttons along the bottom.
    local function Choose(entry)
        picker:Hide()
        onSelect(entry)
    end
    local buttons = {}
    local function CreateOptionButton(text, tooltip, onClick)
        local button = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
        button:SetHeight(22)
        button:SetText(text)
        button:SetScript("OnClick", onClick)
        button:SetScript("OnEnter", function()
            GameTooltip:SetOwner(button, "ANCHOR_TOP")
            GameTooltip:SetText(text)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        buttons[#buttons + 1] = button
        return button
    end
    CreateOptionButton(L["Leveling"], L["A pet from your leveling queue, picked each time the team is loaded."], function()
        Choose({ leveling = true })
    end)
    CreateOptionButton(L["Random"], L["A random level 25 pet of any family, or of one family, picked each time the team is loaded."], function(button)
        MenuUtil.CreateContextMenu(button, function(_, root)
            root:CreateTitle(L["Random level 25 pet"])
            root:CreateButton(L["Any family"], function()
                Choose({ random = true, petType = 0 })
            end)
            for petType = 1, ns.NUM_FAMILIES do
                root:CreateButton(format("|T%s:16:16|t %s", ns.GetFamilyIcon(petType), ns.GetFamilyName(petType)), function()
                    Choose({ random = true, petType = petType })
                end)
            end
        end)
    end)
    CreateOptionButton(L["Empty"], L["No pet in this slot."], function()
        Choose({})
    end)
    local buttonWidth = (PICKER_WIDTH - 2 * 8 - 2 * 4) / 3
    for index, button in ipairs(buttons) do
        button:SetPoint("BOTTOMLEFT", 8 + (index - 1) * (buttonWidth + 4), 8)
        button:SetWidth(buttonWidth)
    end

    scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", -20, 4)

    local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementInitializer("Button", InitRow)
    view:SetElementExtent(ROW_HEIGHT)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    noResults = inset:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    noResults:SetPoint("TOP", 0, -24)
    noResults:SetText(L["No pets found"])
end

-- Opens the picker next to anchor (the team editor) for a team slot. takenPetIDs are pets already in
-- the team ([petID] = true). select(choice) gets a roster entry (see Roster:GetOwnedPets), or a
-- slot without a specific pet: { leveling = true }, { random = true, petType = n } or {} (empty).
function PetPicker:Open(anchor, slot, takenPetIDs, select)
    if not picker then
        CreatePicker(anchor)
    end
    onSelect, taken = select, takenPetIDs
    picker:SetTitle(format(L["Pet for slot %d"], slot))
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    searchBox:SetText("")
    Refresh()
    picker:Show()
    picker:Raise()
    searchBox:SetFocus()
end

function PetPicker:Hide()
    if picker then
        picker:Hide()
    end
end
