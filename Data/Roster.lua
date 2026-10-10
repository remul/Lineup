local _, ns = ...

-- Your pets, read without touching the Pet Journal where possible: owned pets come from
-- C_PetJournal.GetOwnedPetIDs. Only the list of every species (collected or not, with its source)
-- needs the journal's own list, which its filters limit; see ScanJournal.
local Roster = {}
ns.Roster = Roster

local scanning = false

-- The journal's filter state: collected / not collected, families, sources and search text.
local function SaveJournalFilters()
    local J = C_PetJournal
    local saved = {
        collected = J.IsFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED),
        notCollected = J.IsFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED),
        search = J.GetSearchFilter() or "",
        families = {},
        sources = {},
    }
    for family = 1, J.GetNumPetTypes() do
        saved.families[family] = J.IsPetTypeChecked(family)
    end
    for source = 1, J.GetNumPetSources() do
        saved.sources[source] = J.IsPetSourceChecked(source)
    end
    return saved
end

local function RestoreJournalFilters(saved)
    local J = C_PetJournal
    J.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, saved.collected)
    J.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, saved.notCollected)
    for family, checked in ipairs(saved.families) do
        J.SetPetTypeFilter(family, checked)
    end
    for source, checked in ipairs(saved.sources) do
        J.SetPetSourceChecked(source, checked)
    end
    if saved.search ~= "" then
        J.SetSearchFilter(saved.search)
    end
end

-- Runs scan(onlySource) once per pet source with the journal listing every species of that source,
-- then puts the player's filters back. The open journal stops listening meanwhile and is redrawn
-- once at the end, instead of after every filter change.
local function ScanJournal(scan)
    local J = C_PetJournal
    local saved = SaveJournalFilters()
    local journalListens = PetJournal and PetJournal:IsEventRegistered("PET_JOURNAL_LIST_UPDATE")
    if journalListens then
        PetJournal:UnregisterEvent("PET_JOURNAL_LIST_UPDATE")
    end
    scanning = true

    J.ClearSearchFilter()
    J.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, true)
    J.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, true)
    J.SetAllPetTypesChecked(true)
    -- Errors are reported, but never leave the journal widened.
    xpcall(function()
        for source = 1, J.GetNumPetSources() do
            J.SetAllPetSourcesChecked(false)
            J.SetPetSourceChecked(source, true)
            scan(source)
        end
    end, CallErrorHandler)

    RestoreJournalFilters(saved)
    scanning = false
    if journalListens then
        PetJournal:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
        if PetJournal:IsShown() then
            PetJournal_UpdatePetList()
        end
    end
end

-- True while ScanJournal has the journal's filters changed (its list updates can be ignored).
function Roster:IsScanning()
    return scanning
end

local cachedPets

-- Forget the cached list; it's rebuilt the next time it's needed.
function Roster:Invalidate()
    cachedPets = nil
end

-- Returns a list of { petID, speciesID, name, level, rarity, maxHealth, petType, canBattle } for every
-- owned pet. The list is cached until Invalidate() (the leveling queue calls it when pets change,
-- and whenever the Pet Journal opens).
function Roster:GetOwnedPets()
    if cachedPets then
        return cachedPets
    end
    local pets = {}
    for _, petID in ipairs(C_PetJournal.GetOwnedPetIDs()) do
        local info = C_PetJournal.GetPetInfoTableByPetID(petID)
        if info then
            local _, maxHealth, _, _, rarity = C_PetJournal.GetPetStats(petID)
            pets[#pets + 1] = {
                petID = petID,
                speciesID = info.speciesID,
                name = info.customName or info.name,
                level = info.petLevel or 1,
                rarity = rarity or 1,
                maxHealth = maxHealth or 0,
                petType = info.petType,
                canBattle = info.canBattle,
            }
        end
    end
    cachedPets = pets
    return pets
end

-- Every species in the journal, collected or not: [speciesID] = { petType, canBattle, source }.
-- source is the index of its pet source (BATTLE_PET_SOURCE_n); the journal can only filter by
-- source, not say it, so each source is listed on its own. Species only change with patches, so
-- the result is kept for the session.
local allSpecies

function Roster:GetAllSpecies()
    if allSpecies then
        return allSpecies
    end
    local species = {}
    ScanJournal(function(source)
        for index = 1, C_PetJournal.GetNumPets() do
            local _, speciesID, _, _, _, _, _, _, _, petType, _, _, _, _, canBattle = C_PetJournal.GetPetInfoByIndex(index)
            if speciesID and not species[speciesID] then
                species[speciesID] = { petType = petType, canBattle = canBattle, source = source }
            end
        end
    end)
    allSpecies = species
    return species
end

-- Random battle-ready level 25 pet matching the predicate (or the best one if none is level 25).
function Roster.PickRandomMaxLevel(pets, predicate, exclude)
    local candidates = {}
    for _, pet in ipairs(pets) do
        if pet.canBattle and pet.level >= 25 and not exclude[pet.petID] and predicate(pet) then
            candidates[#candidates + 1] = pet
        end
    end
    if #candidates > 0 then
        return candidates[math.random(#candidates)]
    end
    return Roster.PickBest(pets, predicate, exclude)
end

-- Best battle-ready pet matching the predicate: highest level, then quality. Skips petIDs in exclude.
function Roster.PickBest(pets, predicate, exclude)
    local best
    for _, pet in ipairs(pets) do
        if pet.canBattle and not exclude[pet.petID] and predicate(pet) then
            if not best or pet.level > best.level or (pet.level == best.level and pet.rarity > best.rarity) then
                best = pet
            end
        end
    end
    return best
end
