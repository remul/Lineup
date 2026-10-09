local _, ns = ...
local L = ns.L

-- Lineup's filters in Blizzard's Pet Journal: "Strong vs." and "Tough vs." an enemy family, breed
-- and a level range, added to the journal's own Filter menu. The journal builds its list from its
-- own filters; Lineup then leaves out the pets that don't pass these. While one is on, a small
-- button at the end of the family row shows it and clears it; the journal's Reset clears them too.
-- They last until the game is reloaded. Pets that aren't collected have no breed, so a breed
-- filter leaves them out.
local JournalFilters = {}
ns.JournalFilters = JournalFilters

-- Level ranges for the Level submenu: label, short text for the clear button, lowest and highest.
local LEVEL_RANGES = {
    { label = L["Level 25"], short = "25", min = 25, max = 25 },
    { label = L["Below level 25"], short = "<25", min = 1, max = 24 },
    { label = format(L["Level %d–%d"], 20, 24), short = "20–24", min = 20, max = 24 },
    { label = format(L["Level %d–%d"], 15, 19), short = "15–19", min = 15, max = 19 },
    { label = format(L["Level %d–%d"], 10, 14), short = "10–14", min = 10, max = 14 },
    { label = format(L["Level %d–%d"], 1, 9), short = "1–9", min = 1, max = 9 },
    { label = format(L["Level %d"], 1), short = "1", min = 1, max = 1 },
}

local strongVs, toughVs = 0, 0
local levelRange -- one of LEVEL_RANGES, or nil for any level
local breeds = {} -- [breedID] = true; none = any breed
local clearButton

local function IsActive()
    return strongVs ~= 0 or toughVs ~= 0 or levelRange ~= nil or next(breeds) ~= nil
end

local function ClearAll()
    strongVs, toughVs, levelRange = 0, 0, nil
    wipe(breeds)
end

local function Passes(petID, speciesID, level, petType)
    -- Pets that aren't collected have no level, so a level range leaves them out.
    if levelRange and not (level and level >= levelRange.min and level <= levelRange.max) then
        return false
    end
    return ns.PetFilters.IsStrongAgainst(speciesID, strongVs) and ns.PetFilters.IsToughAgainst(petType, toughVs)
        and ns.PetFilters.HasBreed(petID, breeds)
end

-- After the journal built its list: the same list without the pets that don't pass.
local function FilterJournalList()
    if not IsActive() then
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
            levelMenu:CreateRadio(range.label, IsSelected, Select, range)
        end
    end)

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
            GameTooltip:AddLine(levelRange.label, 1, 1, 1)
        end
        local breedNames = ns.PetFilters.DescribeBreeds(breeds)
        if breedNames then
            GameTooltip:AddLine(L["Breed: "] .. breedNames, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click to clear them."], 0, 1, 0)
        GameTooltip:Show()
    end)
    clearButton:SetScript("OnLeave", GameTooltip_Hide)
    UpdateClearButton()
end
