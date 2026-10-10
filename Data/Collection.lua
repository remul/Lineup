local _, ns = ...
local L = ns.L

-- Numbers about the pet collection, for the collection panel: how many of the journal's pets you
-- have, at level 25 and in rare quality, and the same broken down by family or by source.
local Collection = {}
ns.Collection = Collection

local MAX_LEVEL = 25
local RARE = 4

-- What a breakdown can show for each family or source. percent and average are bounded (100%,
-- level 25); the others are counts, scaled to the largest one. Labels are translated where they're
-- shown (L[label]), as the addon's language is only known once it's loaded.
Collection.METRICS = {
    { key = "collected", label = "Pets collected" },
    { key = "unique", label = "Unique pets collected" },
    { key = "missing", label = "Pets not collected" },
    { key = "percent", label = "Percent collected", max = 100, format = "%.0f%%" },
    { key = "maxLevel", label = "Pets at level 25" },
    { key = "average", label = "Average level", max = MAX_LEVEL, format = "%.1f" },
    { key = "rare", label = "Rare quality pets" },
}

-- Counts for a set of species (all of them, a family or a source).
local function NewTally()
    return {
        species = 0, -- species in the journal
        unique = 0, -- species you have
        collected = 0, -- pets you have
        maxLevel = 0, uniqueMaxLevel = 0,
        rare = 0, uniqueRare = 0,
        levels = 0, battlePets = 0, -- for the average level, which only counts battle pets
    }
end

local function AddSpecies(tally, owned)
    tally.species = tally.species + 1
    if owned then
        tally.unique = tally.unique + 1
        tally.collected = tally.collected + owned.count
        tally.maxLevel = tally.maxLevel + owned.maxLevel
        tally.uniqueMaxLevel = tally.uniqueMaxLevel + min(owned.maxLevel, 1)
        tally.rare = tally.rare + owned.rare
        tally.uniqueRare = tally.uniqueRare + min(owned.rare, 1)
        tally.levels = tally.levels + owned.levels
        tally.battlePets = tally.battlePets + owned.battlePets
    end
end

local function GetMetric(tally, key)
    if key == "missing" then
        return tally.species - tally.unique
    elseif key == "percent" then
        return tally.species > 0 and tally.unique * 100 / tally.species or 0
    elseif key == "average" then
        return tally.battlePets > 0 and tally.levels / tally.battlePets or 0
    end
    return tally[key]
end

-- Built from the roster's pet list, and again when that changes (see Roster:Invalidate).
local stats, statsPets

local function BuildStats(pets)
    -- Your pets by species: { count, maxLevel, rare, levels, battlePets }.
    local ownedBySpecies = {}
    local qualities = { 0, 0, 0, 0 }
    for _, pet in ipairs(pets) do
        local owned = ownedBySpecies[pet.speciesID]
        if not owned then
            owned = { count = 0, maxLevel = 0, rare = 0, levels = 0, battlePets = 0, petType = pet.petType }
            ownedBySpecies[pet.speciesID] = owned
        end
        owned.count = owned.count + 1
        if pet.level >= MAX_LEVEL then
            owned.maxLevel = owned.maxLevel + 1
        end
        if pet.rarity >= RARE then
            owned.rare = owned.rare + 1
        end
        if pet.canBattle then
            owned.levels = owned.levels + pet.level
            owned.battlePets = owned.battlePets + 1
        end
        if qualities[pet.rarity] then
            qualities[pet.rarity] = qualities[pet.rarity] + 1
        end
    end

    local result = { total = NewTally(), families = {}, sources = {}, qualities = qualities }
    for petType = 1, ns.NUM_FAMILIES do
        result.families[petType] = NewTally()
    end
    local function Add(speciesID, petType, source)
        local owned = ownedBySpecies[speciesID]
        AddSpecies(result.total, owned)
        if result.families[petType] then
            AddSpecies(result.families[petType], owned)
        end
        if source then
            result.sources[source] = result.sources[source] or NewTally()
            AddSpecies(result.sources[source], owned)
        end
    end
    local allSpecies = ns.Roster:GetAllSpecies()
    for speciesID, info in pairs(allSpecies) do
        Add(speciesID, info.petType, info.source)
    end
    -- Pets the journal didn't list (it shouldn't happen) still count, without a source.
    for speciesID, owned in pairs(ownedBySpecies) do
        if not allSpecies[speciesID] then
            Add(speciesID, owned.petType, nil)
        end
    end
    return result
end

-- Owned pets used in fixed team slots, each counted once.
local function CountPetsInTeams()
    local seen, count = {}, 0
    for _, team in ipairs(ns.Teams:GetAll()) do
        for _, entry in ipairs(team.pets) do
            if entry.petID and not seen[entry.petID] and C_PetJournal.GetPetInfoByPetID(entry.petID) then
                seen[entry.petID] = true
                count = count + 1
            end
        end
    end
    return count
end

-- Returns { total, families = { [petType] }, sources = { [source] }, qualities = { [rarity] = count },
-- inTeams }; total, families and sources are tallies (see NewTally).
function Collection.GetStats()
    local pets = ns.Roster:GetOwnedPets()
    if not stats or statsPets ~= pets then
        stats, statsPets = BuildStats(pets), pets
    end
    stats.inTeams = CountPetsInTeams()
    return stats
end

-- The number to show for a tally: the metric's value, and the value as text.
function Collection.Describe(tally, metric)
    local value = GetMetric(tally, metric.key)
    return value, format(metric.format or "%d", value)
end

-- Values for a whole breakdown ("families" or "sources") of stats (see GetStats):
-- { { id, value, text } } in order, and the value a full bar stands for.
function Collection.GetBreakdown(stats, groupBy, metric)
    local tallies = stats[groupBy]
    local rows, largest = {}, 1
    for id = 1, groupBy == "families" and ns.NUM_FAMILIES or C_PetJournal.GetNumPetSources() do
        local tally = tallies[id]
        if tally and tally.species > 0 then
            local value, text = Collection.Describe(tally, metric)
            rows[#rows + 1] = { id = id, value = value, text = text }
            largest = max(largest, value)
        end
    end
    return rows, metric.max or largest
end
