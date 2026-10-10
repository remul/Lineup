local _, ns = ...
local L = ns.L

-- Lineup's filters in Blizzard's Pet Journal: "Strong vs." and "Tough vs." an enemy family, breed
-- and a level range, added to the journal's own Filter menu. The journal builds its list from its
-- own filters; Lineup then leaves out the pets that don't pass these. While one is on, a small
-- button at the end of the family row shows it and clears it; the journal's Reset clears them too.
-- They last until the game is reloaded. Pets that aren't collected have no breed, so a breed
-- filter leaves them out.
-- Pets can also be hidden from the list with "Hide" in their right-click menu (and shown again
-- with "Unhide"); they stay hidden, and the Hidden pets filter leaves them out (the default), shows
-- only them or shows all pets. A collected pet is hidden by itself, one not collected by its species; Blizzard has no
-- right-click menu for those, so Lineup opens its own.
local JournalFilters = {}
ns.JournalFilters = JournalFilters

-- Level ranges for the Level submenu: label, short text for the clear button, lowest and highest.
-- Labels and the hidden pets texts below are translated where they're shown (see RangeLabel).
local LEVEL_RANGES = {
    { label = "Level 25", short = "25", min = 25, max = 25 },
    { label = "Below level 25", short = "<25", min = 1, max = 24 },
    { label = "Level %d–%d", short = "20–24", min = 20, max = 24 },
    { label = "Level %d–%d", short = "15–19", min = 15, max = 19 },
    { label = "Level %d–%d", short = "10–14", min = 10, max = 14 },
    { label = "Level %d–%d", short = "1–9", min = 1, max = 9 },
    { label = "Level %d", short = "1", min = 1, max = 1 },
}

local function RangeLabel(range)
    return format(L[range.label], range.min, range.max)
end

local strongVs, toughVs = 0, 0
local levelRange -- one of LEVEL_RANGES, or nil for any level
local breeds = {} -- [breedID] = true; none = any breed
-- Hidden pets submenu: label, short text for the clear button. HIDE_HIDDEN is the default.
local HIDE_HIDDEN = { label = "Hide hidden pets" }
local ONLY_HIDDEN = { label = "Only hidden pets", short = "Hidden" }
local ALL_PETS = { label = "All pets", short = "All pets" }
local hiddenMode = HIDE_HIDDEN
local clearButton

-- Whether a filter is changed from its default (shown by the clear button).
local function IsActive()
    return strongVs ~= 0 or toughVs ~= 0 or levelRange ~= nil or next(breeds) ~= nil or hiddenMode ~= HIDE_HIDDEN
end

local function ClearAll()
    strongVs, toughVs, levelRange = 0, 0, nil
    wipe(breeds)
    hiddenMode = HIDE_HIDDEN
end

local function IsHidden(petID, speciesID)
    if petID then
        return ns.db.hiddenPets[petID] == true
    end
    return ns.db.hiddenSpecies[speciesID] == true
end

local function Passes(petID, speciesID, level, petType)
    if hiddenMode ~= ALL_PETS and IsHidden(petID, speciesID) ~= (hiddenMode == ONLY_HIDDEN) then
        return false
    end
    -- Pets that aren't collected have no level, so a level range leaves them out.
    if levelRange and not (level and level >= levelRange.min and level <= levelRange.max) then
        return false
    end
    return ns.PetFilters.IsStrongAgainst(speciesID, strongVs) and ns.PetFilters.IsToughAgainst(petType, toughVs)
        and ns.PetFilters.HasBreed(petID, breeds)
end

-- After the journal built its list: the same list without the pets that don't pass.
local function FilterJournalList()
    if not IsActive() and not (next(ns.db.hiddenPets) or next(ns.db.hiddenSpecies)) then
        return
    end
    local dataProvider = CreateDataProvider()
    for index = 1, C_PetJournal.GetNumPets() do
        local petID, speciesID, _, _, level, _, _, _, _, petType = C_PetJournal.GetPetInfoByIndex(index)
        if speciesID and Passes(petID, speciesID, level, petType) then
            dataProvider:Insert({ index = index, petID = petID, speciesID = speciesID })
        end
    end
    PetJournal.ScrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition)
end

local function UpdateClearButton()
    if not clearButton then
        return
    end
    local icons = {}
    for _, family in ipairs({ strongVs, toughVs }) do
        if family ~= 0 then
            icons[#icons + 1] = format("|T%s:14:14|t", ns.GetFamilyIcon(family))
        end
    end
    if levelRange then
        icons[#icons + 1] = levelRange.short
    end
    icons[#icons + 1] = ns.PetFilters.DescribeBreeds(breeds)
    icons[#icons + 1] = hiddenMode.short and L[hiddenMode.short]
    clearButton.Text:SetText(table.concat(icons, " ") .. " |TInterface\\Buttons\\UI-StopButton:12:12|t")
    clearButton:SetWidth(clearButton.Text:GetStringWidth() + 10)
    clearButton:SetShown(IsActive())
end

local function Changed()
    UpdateClearButton()
    PetJournal_UpdatePetList()
end

function JournalFilters:Clear()
    ClearAll()
    Changed()
end

local function SetHidden(petID, speciesID, hidden)
    if petID then
        ns.db.hiddenPets[petID] = hidden or nil
    else
        ns.db.hiddenSpecies[speciesID] = hidden or nil
    end
    PetJournal_UpdatePetList()
end

-- How many pets and species are hidden.
function JournalFilters:CountHidden()
    local count = 0
    for _ in pairs(ns.db.hiddenPets) do
        count = count + 1
    end
    for _ in pairs(ns.db.hiddenSpecies) do
        count = count + 1
    end
    return count
end

-- Shows every hidden pet again.
function JournalFilters:ResetHidden()
    wipe(ns.db.hiddenPets)
    wipe(ns.db.hiddenSpecies)
    if PetJournal and PetJournal:IsShown() then
        PetJournal_UpdatePetList()
    end
end

local function AddHideButton(root, petID, speciesID)
    local hidden = IsHidden(petID, speciesID)
    root:CreateButton(hidden and L["Unhide"] or L["Hide"], function()
        SetHidden(petID, speciesID, not hidden)
    end)
end

-- A right-click on a list button (or its icon) of a pet that isn't collected.
local function ShowUncollectedMenu(listButton, mouseButton)
    if mouseButton ~= "RightButton" or listButton.owned or not listButton.speciesID then
        return
    end
    local speciesID = listButton.speciesID
    MenuUtil.CreateContextMenu(listButton, function(_, root)
        AddHideButton(root, nil, speciesID)
    end)
end

local hookedListButtons = {}

local function HookListButton(listButton)
    if hookedListButtons[listButton] then
        return
    end
    hookedListButtons[listButton] = true
    listButton:HookScript("OnClick", ShowUncollectedMenu)
    -- The icon is disabled for pets not collected, so it gets no clicks, only mouse ups.
    listButton.dragButton:HookScript("OnMouseUp", function(dragButton, mouseButton)
        if not dragButton:IsEnabled() then
            ShowUncollectedMenu(listButton, mouseButton)
        end
    end)
end

-- "Strong vs." / "Tough vs." submenu: any family, or one.
local function AddVsSubmenu(root, label, get, set)
    ns.PetFilters.AddFamilyOptions(root:CreateButton(label), get, function(family)
        set(family)
        Changed()
        return MenuResponse.Refresh
    end)
end

function JournalFilters:Setup()
    if not (PetJournal and PetJournal.ScrollBox and PetJournal_UpdatePetList and Menu and Menu.ModifyMenu) then
        return
    end
    hooksecurefunc("PetJournal_UpdatePetList", FilterJournalList)
    -- The journal's Reset (and anything else restoring its default filters) clears these too.
    hooksecurefunc(C_PetJournal, "SetDefaultFilters", function()
        if IsActive() then
            ClearAll()
            UpdateClearButton()
        end
    end)

    Menu.ModifyMenu("MENU_PET_COLLECTION_FILTER", function(_, root)
        root:CreateDivider()
        root:CreateTitle(ns.TITLE)
        AddVsSubmenu(root, L["Strong vs."], function() return strongVs end, function(family) strongVs = family end)
        AddVsSubmenu(root, L["Tough vs."], function() return toughVs end, function(family) toughVs = family end)
        ns.PetFilters.AddBreedSubmenu(root, L["Breed"], breeds, Changed)
        -- Level: any, or one range.
        local levelMenu = root:CreateButton(L["Level"])
        local function IsSelected(range)
            return range == levelRange
        end
        local function Select(range)
            levelRange = range
            Changed()
            return MenuResponse.Refresh
        end
        levelMenu:CreateRadio(L["Any level"], function()
            return levelRange == nil
        end, function()
            return Select(nil)
        end)
        for _, range in ipairs(LEVEL_RANGES) do
            levelMenu:CreateRadio(RangeLabel(range), IsSelected, Select, range)
        end
        -- Hidden pets: left out, only them, or all pets.
        local hiddenMenu = root:CreateButton(L["Hidden pets"])
        local function IsModeSelected(mode)
            return mode == hiddenMode
        end
        local function SelectMode(mode)
            hiddenMode = mode
            Changed()
            return MenuResponse.Refresh
        end
        for _, mode in ipairs({ HIDE_HIDDEN, ONLY_HIDDEN, ALL_PETS }) do
            hiddenMenu:CreateRadio(L[mode.label], IsModeSelected, SelectMode, mode)
        end
    end)

    -- "Hide" or "Unhide" in a pet's right-click menu. It opens from a list button (or its icon),
    -- a loadout slot or the pet card, which have the pet (or their parent has).
    Menu.ModifyMenu("MENU_PET_COLLECTION_PET", function(owner, root)
        local parent = owner:GetParent()
        local petID = owner.petID or (parent and parent.petID)
        if not petID then
            return
        end
        root:CreateDivider()
        AddHideButton(root, petID)
    end)
    if PetJournal_InitPetButton then
        hooksecurefunc("PetJournal_InitPetButton", HookListButton)
    end

    -- Shows the active filters at the end of the family row; a click clears them.
    clearButton = CreateFrame("Button", nil, PetJournal)
    clearButton:SetHeight(20)
    clearButton:SetPoint("BOTTOMRIGHT", PetJournal.ScrollBox, "TOPRIGHT", -2, 4)
    clearButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    local background = clearButton:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.5)
    clearButton.Text = clearButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clearButton.Text:SetPoint("CENTER")
    clearButton:SetScript("OnClick", function()
        JournalFilters:Clear()
    end)
    clearButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText(L["Lineup filters"])
        if strongVs ~= 0 then
            GameTooltip:AddLine(L["Strong vs."] .. " " .. ns.GetFamilyName(strongVs), 1, 1, 1)
        end
        if toughVs ~= 0 then
            GameTooltip:AddLine(L["Tough vs."] .. " " .. ns.GetFamilyName(toughVs), 1, 1, 1)
        end
        if levelRange then
            GameTooltip:AddLine(RangeLabel(levelRange), 1, 1, 1)
        end
        local breedNames = ns.PetFilters.DescribeBreeds(breeds)
        if breedNames then
            GameTooltip:AddLine(L["Breed: "] .. breedNames, 1, 1, 1)
        end
        if hiddenMode ~= HIDE_HIDDEN then
            GameTooltip:AddLine(L[hiddenMode.label], 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click to clear them."], 0, 1, 0)
        GameTooltip:Show()
    end)
    clearButton:SetScript("OnLeave", GameTooltip_Hide)
    UpdateClearButton()
end
