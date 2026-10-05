local _, ns = ...

-- Lists owned pets. The journal API only returns pets matching the journal's filters (shared with
-- Blizzard's Pet Journal), so they are widened for the scan and restored afterwards.
local Roster = {}
ns.Roster = Roster

-- There is no getter for the journal's search text, so remember it as it's set.
local searchText = ""
local expanding = false

hooksecurefunc(C_PetJournal, "SetSearchFilter", function(text)
    if not expanding then
        searchText = text or ""
    end
end)
hooksecurefunc(C_PetJournal, "ClearSearchFilter", function()
    if not expanding then
        searchText = ""
    end
end)

local function WithAllOwnedPets(callback)
    local J = C_PetJournal
    local collected = J.IsFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED)
    local notCollected = J.IsFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED)
    local types, sources = {}, {}
    for i = 1, J.GetNumPetTypes() do
        types[i] = J.IsPetTypeChecked(i)
    end
    for i = 1, J.GetNumPetSources() do
        sources[i] = J.IsPetSourceChecked(i)
    end

    expanding = true
    J.ClearSearchFilter()
    J.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, true)
    J.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, false)
    J.SetAllPetTypesChecked(true)
    J.SetAllPetSourcesChecked(true)

    callback()

    J.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, collected)
    J.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, notCollected)
    for i, checked in ipairs(types) do
        J.SetPetTypeFilter(i, checked)
    end
    for i, checked in ipairs(sources) do
        J.SetPetSourceChecked(i, checked)
    end
    J.SetSearchFilter(searchText)
    expanding = false
end

-- True while the journal filters are widened for a scan (its PET_JOURNAL_LIST_UPDATEs can be ignored).
function Roster:IsScanning()
    return expanding
end

local cachedPets

-- Forget the cached list; it's rebuilt the next time it's needed.
function Roster:Invalidate()
    cachedPets = nil
end

-- Returns a list of { petID, speciesID, name, level, rarity, maxHealth, petType, canBattle } for every
-- owned pet. The list is cached until Invalidate() (the leveling queue calls it when pets change).
function Roster:GetOwnedPets()
    if cachedPets then
        return cachedPets
    end
    local pets = {}
    WithAllOwnedPets(function()
        for i = 1, C_PetJournal.GetNumPets() do
            local petID, speciesID, owned, customName, level, _, _, speciesName, _, petType,
                _, _, _, _, canBattle = C_PetJournal.GetPetInfoByIndex(i)
            if petID and owned then
                local _, maxHealth, _, _, rarity = C_PetJournal.GetPetStats(petID)
                pets[#pets + 1] = {
                    petID = petID,
                    speciesID = speciesID,
                    name = customName or speciesName,
                    level = level or 1,
                    rarity = rarity or 1,
                    maxHealth = maxHealth or 0,
                    petType = petType,
                    canBattle = canBattle,
                }
            end
        end
    end)
    cachedPets = pets
    return pets
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
