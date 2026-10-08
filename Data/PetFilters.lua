local _, ns = ...

-- Pet filters shared by the pet picker and the Pet Journal: abilities by name, "strong vs." or
-- "tough vs." an enemy family by the pet battle type chart (see ns.STRONG_AGAINST), and breed.
local PetFilters = {}
ns.PetFilters = PetFilters

-- True if the (lowercase) search is part of one of the species' ability names.
function PetFilters.HasAbilityMatching(speciesID, query)
    for _, name in ipairs(ns.GetSpeciesAbilities(speciesID).names) do
        if name:find(query, 1, true) then
            return true
        end
    end
    return false
end

-- True if the species can learn an ability that does extra damage to the family (0 = any family).
function PetFilters.IsStrongAgainst(speciesID, family)
    return family == 0 or ns.GetSpeciesAbilities(speciesID).strongAgainst[family] == true
end

-- True if pets of this family take less damage from the given family's attacks (0 = any family).
function PetFilters.IsToughAgainst(petType, family)
    return family == 0 or ns.WEAK_AGAINST[family] == petType
end

-- True if the owned pet can be one of the breeds ([breedID] = true; none = any breed). Pets
-- without a petID (not collected) have no breed, so they don't pass a breed filter.
function PetFilters.HasBreed(petID, breeds)
    if not next(breeds) then
        return true
    end
    for _, breedID in ipairs(petID and ns.Breeds.GetPetBreeds(petID) or {}) do
        if breeds[breedID] then
            return true
        end
    end
    return false
end

-- Short label for a breed filter: "P/S", "P/S, S/S", or nil for any breed.
function PetFilters.DescribeBreeds(breeds)
    local names = {}
    for breedID = 3, 12 do
        if breeds[breedID] then
            names[#names + 1] = ns.Breeds.NAMES[breedID]
        end
    end
    return #names > 0 and table.concat(names, ", ") or nil
end

-- Adds family choices to a menu: "Any family" (0) and a radio button per family. get() returns the
-- chosen family; select(family) stores a choice, and what it returns is the menu's response.
function PetFilters.AddFamilyOptions(menu, get, select)
    local function IsSelected(family)
        return get() == family
    end
    menu:CreateRadio(ns.L["Any family"], IsSelected, select, 0)
    for family = 1, ns.NUM_FAMILIES do
        menu:CreateRadio(ns.FormatFamily(family), IsSelected, select, family)
    end
end

-- Adds breed choices to a menu: "Any breed" and a checkbox per breed. changed() runs after every
-- change.
function PetFilters.AddBreedOptions(menu, breeds, changed)
    menu:CreateButton(ns.L["Any breed"], function()
        wipe(breeds)
        changed()
        return MenuResponse.Refresh
    end)
    menu:CreateDivider()
    for breedID = 3, 12 do
        menu:CreateCheckbox(ns.Breeds.NAMES[breedID], function()
            return breeds[breedID] == true
        end, function()
            breeds[breedID] = not breeds[breedID] or nil
            changed()
        end)
    end
end

-- The same choices in a submenu of root.
function PetFilters.AddBreedSubmenu(root, label, breeds, changed)
    PetFilters.AddBreedOptions(root:CreateButton(label), breeds, changed)
end
