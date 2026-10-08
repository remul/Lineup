local _, ns = ...
local L = ns.L

-- The leveling queue is built automatically from your battle pets below level 25. By default it
-- has one per species (your highest) and skips species you already have at level 25; options
-- include duplicates and those species too. Its order is the chosen sort.
-- Teams can have leveling slots, which are filled from the front of the queue when loaded.
-- A leveling slot can carry Rematch-style preferences:
--   { minHP, allowMM, expectedDD, maxHP, minXP, maxXP }
-- (minXP/maxXP are levels; allowMM lets Magic and Mechanical pets ignore minHP; expectedDD is the
-- damage type the pet will take, so families weak to it are skipped.)
-- If no queue pet meets them, a level 25 pet that does is used instead.
local LevelingQueue = {}
ns.LevelingQueue = LevelingQueue

local MAGIC, MECHANICAL = 6, 10

local queue, owned

-- Picks the best pet of a species: highest level, then quality.
local function IsBetter(a, b)
    if a.level ~= b.level then
        return a.level > b.level
    end
    return a.rarity > b.rarity
end

local function ByName(a, b)
    return a.name < b.name
end

-- Sort orders for the queue; each falls back to further criteria for ties.
LevelingQueue.SORTS = {
    { key = "levelDesc", label = L["Highest level first"], compare = function(a, b)
        if a.level ~= b.level then
            return a.level > b.level
        end
        return ByName(a, b)
    end },
    { key = "levelAsc", label = L["Lowest level first"], compare = function(a, b)
        if a.level ~= b.level then
            return a.level < b.level
        end
        return ByName(a, b)
    end },
    { key = "family", label = L["Family"], compare = function(a, b)
        if a.petType ~= b.petType then
            return ns.GetFamilyName(a.petType) < ns.GetFamilyName(b.petType)
        end
        if a.level ~= b.level then
            return a.level > b.level
        end
        return ByName(a, b)
    end },
    { key = "rarity", label = L["Quality"], compare = function(a, b)
        if a.rarity ~= b.rarity then
            return a.rarity > b.rarity
        end
        if a.level ~= b.level then
            return a.level > b.level
        end
        return ByName(a, b)
    end },
    { key = "name", label = L["Name"], compare = ByName },
}

local function GetSortCompare()
    for _, sort in ipairs(LevelingQueue.SORTS) do
        if sort.key == ns.db.queueSort then
            return sort.compare
        end
    end
    return LevelingQueue.SORTS[1].compare
end

function LevelingQueue:GetSort()
    return ns.db.queueSort
end

-- Options: "queueIncludeDuplicates" and "queueIncludeMaxedSpecies".
function LevelingQueue:GetOption(key)
    return ns.db[key]
end

function LevelingQueue:SetOption(key, value)
    ns.db[key] = value
    queue = nil -- rebuilt from the cached pet list on the next Get()
    ns.TeamsPanel:Refresh()
end

function LevelingQueue:SetSort(key)
    ns.db.queueSort = key
    if queue then
        table.sort(queue, GetSortCompare())
    end
    ns.TeamsPanel:Refresh()
end

-- Returns the queue as a list of roster pets (see Roster:GetOwnedPets).
function LevelingQueue:Get()
    if queue then
        return queue
    end

    owned = ns.Roster:GetOwnedPets()
    local includeDuplicates = ns.db.queueIncludeDuplicates
    local includeMaxed = ns.db.queueIncludeMaxedSpecies

    local maxedSpecies = {}
    if not includeMaxed then
        for _, pet in ipairs(owned) do
            if pet.level >= 25 then
                maxedSpecies[pet.speciesID] = true
            end
        end
    end

    local result, bestBySpecies = {}, {}
    for _, pet in ipairs(owned) do
        if pet.canBattle and pet.level < 25 and not maxedSpecies[pet.speciesID] then
            if includeDuplicates then
                result[#result + 1] = pet
            else
                local best = bestBySpecies[pet.speciesID]
                if not best or IsBetter(pet, best) then
                    bestBySpecies[pet.speciesID] = pet
                end
            end
        end
    end
    for _, pet in pairs(bestBySpecies) do
        result[#result + 1] = pet
    end
    table.sort(result, GetSortCompare())
    queue = result
    return queue
end

-- True if the pet meets the preferences; ignoreLevel skips the level limits (for level 25 substitutes).
function LevelingQueue.MatchesPreferences(pet, preferences, ignoreLevel)
    if not preferences then
        return true
    end
    local p = preferences
    if not ignoreLevel and ((p.minXP and pet.level < p.minXP) or (p.maxXP and pet.level > p.maxXP)) then
        return false
    end
    local exemptFromMinHP = p.allowMM and (pet.petType == MAGIC or pet.petType == MECHANICAL)
    if p.minHP and pet.maxHealth < p.minHP and not exemptFromMinHP then
        return false
    end
    if p.maxHP and pet.maxHealth > p.maxHP then
        return false
    end
    if p.expectedDD and ns.STRONG_AGAINST[p.expectedDD] == pet.petType then
        return false
    end
    return true
end

-- Short description like "level 5+, not weak to Humanoid", or nil without preferences.
function LevelingQueue.DescribePreferences(preferences)
    if not preferences then
        return nil
    end
    local p, parts = preferences, {}
    if p.minXP and p.maxXP then
        parts[#parts + 1] = format(L["level %g-%g"], p.minXP, p.maxXP)
    elseif p.minXP then
        parts[#parts + 1] = format(L["level %g+"], p.minXP)
    elseif p.maxXP then
        parts[#parts + 1] = format(L["level %g or lower"], p.maxXP)
    end
    if p.minHP then
        parts[#parts + 1] = format(L["at least %d health%s"], p.minHP, p.allowMM and L[" (Magic/Mechanical exempt)"] or "")
    end
    if p.maxHP then
        parts[#parts + 1] = format(L["at most %d health"], p.maxHP)
    end
    if p.expectedDD then
        parts[#parts + 1] = format(L["not weak to %s"], ns.GetFamilyName(p.expectedDD))
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

-- First queue pet that isn't in exclude (a set of petIDs) and meets the preferences, or nil.
function LevelingQueue:GetNext(exclude, preferences)
    for _, pet in ipairs(self:Get()) do
        if (not exclude or not exclude[pet.petID]) and LevelingQueue.MatchesPreferences(pet, preferences) then
            return pet
        end
    end
end

-- Random battle-ready level 25 pet meeting the preferences (ignoring level limits), for leveling
-- slots that no queue pet qualifies for.
function LevelingQueue:GetSubstitute(exclude, preferences)
    self:Get()
    return ns.Roster.PickRandomMaxLevel(owned, function(pet)
        return pet.level >= 25 and LevelingQueue.MatchesPreferences(pet, preferences, true)
    end, exclude or {})
end

-- The pet a leveling slot would use: a queue pet, else a level 25 substitute.
-- Returns pet, isSubstitute (pet is nil if neither exists).
function LevelingQueue:PickForSlot(exclude, preferences)
    local pet = self:GetNext(exclude, preferences)
    if pet then
        return pet, false
    end
    pet = self:GetSubstitute(exclude, preferences)
    return pet, pet ~= nil
end

-- Forget the cached queue; it's rebuilt the next time it's needed.
function LevelingQueue:Invalidate()
    queue, owned = nil, nil
    ns.Roster:Invalidate()
    ns.TeamsPanel:Refresh()
end

-- Pets were added, removed or gained experience.
for _, event in ipairs({ "NEW_PET_ADDED", "PET_JOURNAL_PET_DELETED", "PET_BATTLE_LEVEL_CHANGED", "PET_BATTLE_CLOSE" }) do
    ns:RegisterEvent(event, function()
        LevelingQueue:Invalidate()
    end)
end
