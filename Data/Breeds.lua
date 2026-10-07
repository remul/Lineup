local _, ns = ...
local L = ns.L

-- Pet breeds (e.g. P/S). The game doesn't tell a pet's breed, so it's worked out from its stats,
-- like breed addons do, with Blizzard's tables in BreedData:
--   health = round(stamina * quality * level / 20) + 100
--   power  = round(power * quality * level / 100), and speed alike
-- where each stat is the breed's plus the species' adjustment. At level 25 exactly one breed fits;
-- at low levels several can, so matching returns a list. Breeds 3-12 are used throughout (13-22
-- are their female versions, with the same stats).
local Breeds = {}
ns.Breeds = Breeds

Breeds.NAMES = {
    [3] = "B/B", [4] = "P/P", [5] = "S/S", [6] = "H/H", [7] = "H/P",
    [8] = "P/S", [9] = "H/S", [10] = "P/B", [11] = "S/B", [12] = "H/B",
}

local NO_ADJUSTMENT = { 0, 0, 0 }
-- The game's exact rounding isn't known, so stats may be off by this much.
local TOLERANCE = 1

local function Round(value)
    return floor(value + 0.5)
end

-- 3-12 for a breed ID (13-22 become 3-12), or nil.
function Breeds.Normalize(breedID)
    if breedID and breedID >= 13 and breedID <= 22 then
        breedID = breedID - 10
    end
    return Breeds.NAMES[breedID] and breedID or nil
end

-- health, power, speed of a pet of this species, breed, level and rarity (1 = poor ... 6 =
-- legendary); nil for an unknown breed or rarity.
function Breeds.GetStats(speciesID, breedID, level, rarity)
    local data = ns.BreedData
    local breed, quality = data.breeds[breedID], data.qualities[rarity]
    if not breed or not quality then
        return nil
    end
    local adjustment = data.species[speciesID] or NO_ADJUSTMENT
    local scale = quality * level
    return Round((breed[1] + adjustment[1]) * scale / 20) + 100,
        Round((breed[2] + adjustment[2]) * scale / 100),
        Round((breed[3] + adjustment[3]) * scale / 100)
end

-- The breeds (3-12) a pet with these stats can be; empty if none fits (e.g. a species newer than
-- BreedData).
function Breeds.Match(speciesID, level, rarity, maxHealth, power, speed)
    local matches = {}
    for breedID = 3, 12 do
        local expectedHealth, expectedPower, expectedSpeed = Breeds.GetStats(speciesID, breedID, level, rarity)
        if expectedHealth and math.abs(expectedHealth - maxHealth) <= TOLERANCE
            and math.abs(expectedPower - power) <= TOLERANCE and math.abs(expectedSpeed - speed) <= TOLERANCE then
            matches[#matches + 1] = breedID
        end
    end
    return matches
end

-- Owned pets' breeds: [petID] = { stats key, matches }, redone when the pet levels or is upgraded.
local cache = {}

-- The breeds an owned pet can be (one at level 25, possibly several below; empty if unknown).
function Breeds.GetPetBreeds(petID)
    local speciesID, _, level = C_PetJournal.GetPetInfoByPetID(petID)
    local _, maxHealth, power, speed, rarity = C_PetJournal.GetPetStats(petID)
    if not speciesID or not maxHealth then
        return {}
    end
    local key = format("%d:%d:%d:%d:%d", level, rarity, maxHealth, power, speed)
    local cached = cache[petID]
    if not cached or cached.key ~= key then
        cached = { key = key, matches = Breeds.Match(speciesID, level, rarity, maxHealth, power, speed) }
        cache[petID] = cached
    end
    return cached.matches
end

-- The owned pet's breed when it's certain (3-12), else nil.
function Breeds.GetPetBreed(petID)
    local matches = Breeds.GetPetBreeds(petID)
    return #matches == 1 and matches[1] or nil
end

-- True if the pet can be this breed.
function Breeds.PetCanBe(petID, breedID)
    return tContains(Breeds.GetPetBreeds(petID), breedID)
end

-- "P/S", "P/S or S/S", "?" for more, nil if unknown.
function Breeds.Describe(matches)
    if #matches == 1 then
        return Breeds.NAMES[matches[1]]
    elseif #matches == 2 then
        return format(L["%s or %s"], Breeds.NAMES[matches[1]], Breeds.NAMES[matches[2]])
    elseif #matches > 2 then
        return "?"
    end
end

function Breeds.DescribePet(petID)
    return Breeds.Describe(Breeds.GetPetBreeds(petID))
end

-- For a team slot: its pet's breed, and the breed the team asks for when that differs:
-- "H/H (team wants P/S)". nil when there's nothing to say.
function Breeds.DescribeSlot(entry)
    local have = entry.petID and Breeds.DescribePet(entry.petID)
    local want = entry.breed and Breeds.NAMES[entry.breed]
    if want and not (entry.petID and Breeds.PetCanBe(entry.petID, entry.breed)) then
        return have and format(L["%s (team wants %s)"], have, want) or format(L["team wants %s"], want)
    end
    return have
end
