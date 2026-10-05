local _, ns = ...

-- A team is:
--   name        "Major Payne"
--   groupID  number, or nil for ungrouped
--   pets        { [slot] = { petID = "BattlePet-...", speciesID = number, abilities = { id, id, id } } }
--               (petID is nil for a pet you don't own; abilities may be nil for "keep current";
--               { leveling = true, preferences = {...} } is a leveling slot, filled from the leveling
--               queue on load; see LevelingQueue for preferences;
--               { random = true, petType = n } is a random level 25 pet of that family (0 = any family),
--               picked again every time the team is loaded)
--   targetNpcID number, the NPC this team is for (optional)
--   targetName  string (optional)
--   script      tdBattlePetScript text (optional)
--   notes       strategy notes (optional)
-- A group is { id = number, name = "...", collapsed = bool, icon = fileID or path (optional) }.
local Teams = {}
ns.Teams = Teams

local NUM_SLOTS = 3

-- Teams
function Teams:GetAll()
    return ns.db.teams
end

function Teams:CaptureLoadout()
    local pets = {}
    for slot = 1, NUM_SLOTS do
        local petID, ability1, ability2, ability3 = C_PetJournal.GetPetLoadOutInfo(slot)
        local speciesID = petID and C_PetJournal.GetPetInfoByPetID(petID)
        pets[slot] = { petID = petID, speciesID = speciesID, abilities = { ability1, ability2, ability3 } }
    end
    return pets
end

-- True if a pet of this family can fill the random slot.
function Teams.MatchesRandomSlot(entry, petType)
    return entry.petType == 0 or entry.petType == petType
end

-- The team last loaded (remembered per character by name, since teams have no IDs).
local loadedTeam

function Teams:GetLoadedTeam()
    if not loadedTeam and ns.charDb.loadedTeamName then
        for _, team in ipairs(self:GetAll()) do
            if team.name == ns.charDb.loadedTeamName then
                loadedTeam = team
                break
            end
        end
    end
    return loadedTeam
end

local function SetLoadedTeam(team)
    loadedTeam = team
    ns.charDb.loadedTeamName = team and team.name
end

-- True when the journal's current loadout fits this team (any pet of the right family for random
-- slots, anything for leveling slots).
local function LoadoutMatches(team)
    for slot = 1, NUM_SLOTS do
        local petID = C_PetJournal.GetPetLoadOutInfo(slot)
        local entry = team.pets[slot]
        if entry.random then
            local petType = petID and select(10, C_PetJournal.GetPetInfoByPetID(petID))
            if not petType or not Teams.MatchesRandomSlot(entry, petType) then
                return false
            end
        elseif not entry.leveling and petID ~= entry.petID then
            return false
        end
    end
    return true
end

-- True for the team you loaded last, while its pets are still in the journal. (Matching the
-- loadout alone isn't enough: with random slots, several teams can fit the same pets.)
function Teams:IsLoaded(team)
    return team == self:GetLoadedTeam() and LoadoutMatches(team)
end

-- A draft is an editable copy of a team; Save() writes it back (or creates a new team).
function Teams:CreateDraft(team)
    if team then
        return {
            name = team.name,
            groupID = team.groupID,
            pets = CopyTable(team.pets),
            targetNpcID = team.targetNpcID,
            targetName = team.targetName,
            script = team.script or "",
            notes = team.notes,
        }
    end
    return {
        name = format("Team %d", #self:GetAll() + 1),
        pets = self:CaptureLoadout(),
        script = "",
    }
end

function Teams:Save(team, draft)
    if not team then
        team = {}
        tinsert(ns.db.teams, team)
    end
    team.name = draft.name
    team.groupID = draft.groupID
    team.pets = draft.pets
    team.targetNpcID = draft.targetNpcID
    team.targetName = draft.targetNpcID and draft.targetName or nil
    team.script = draft.script ~= "" and draft.script or nil
    team.notes = draft.notes
    if team == loadedTeam then
        SetLoadedTeam(team) -- keep the remembered name in sync after a rename
    end
    return team
end

-- Returns icon, name, level, isMissing, rarity for a team slot; icon is nil for an empty slot.
-- level and rarity are nil when the slot isn't one specific pet (random slots, missing pets).
function Teams.GetSlotDisplay(entry)
    if entry.random then
        if entry.petType == 0 then
            return "Interface\\Icons\\INV_Misc_QuestionMark", "Random level 25 pet", nil, false
        end
        return ns.GetFamilyIcon(entry.petType), format("Random level 25 %s pet", ns.GetFamilyName(entry.petType)), nil, false
    end
    if entry.leveling then
        local pet = ns.LevelingQueue:GetNext(nil, entry.preferences)
        if pet then
            local _, _, _, _, _, _, _, _, icon = C_PetJournal.GetPetInfoByPetID(pet.petID)
            return icon, "Leveling: " .. pet.name, pet.level, false, pet.rarity
        end
        -- The substitute is picked at random on load, so show the slot generically.
        local requirement = ns.LevelingQueue.DescribePreferences(entry.preferences)
        local reason = requirement and format("no leveling pet is %s", requirement) or "leveling queue is empty"
        return "Interface\\Icons\\INV_Pet_BattlePetTraining", format("Any level 25 pet (%s)", reason), nil, false
    end
    if entry.petID then
        local _, customName, level, _, _, _, _, speciesName, icon = C_PetJournal.GetPetInfoByPetID(entry.petID)
        if icon then
            local _, _, _, _, rarity = C_PetJournal.GetPetStats(entry.petID)
            return icon, customName or speciesName, level, false, rarity
        end
    end
    if entry.speciesID then
        local speciesName, icon = ns.GetSpeciesInfo(entry.speciesID)
        return icon, (speciesName or "Unknown pet") .. " (not collected)", nil, true
    end
    return nil
end

function Teams:Overwrite(team)
    team.pets = self:CaptureLoadout()
end

-- New team from the current loadout, aimed at the given NPC.
function Teams:CreateForTarget(npcID, name)
    local draft = self:CreateDraft(nil)
    draft.name = name or draft.name
    draft.targetNpcID = npcID
    draft.targetName = name
    return self:Save(nil, draft)
end

function Teams:Delete(team)
    if team == self:GetLoadedTeam() then
        SetLoadedTeam(nil)
    end
    tDeleteItem(ns.db.teams, team)
end

function Teams:GetForTarget(npcID)
    local result = {}
    for _, team in ipairs(self:GetAll()) do
        if npcID and team.targetNpcID == npcID then
            result[#result + 1] = team
        end
    end
    return result
end

function Teams:CanLoad()
    if C_PetBattles.IsInBattle() then
        return false, "You can't change pets during a battle."
    end
    if not C_PetJournal.IsJournalUnlocked() then
        return false, "The Pet Journal is locked."
    end
    return true
end

-- Loading works from a plan of { slot, petID, abilities }: everything is set, then the journal is
-- checked and anything that didn't stick is set again, a few times, since the journal applies
-- loadout changes asynchronously.
local LOAD_RETRY_DELAY = 0.25
local LOAD_MAX_ATTEMPTS = 5
local loadToken = 0

-- What of this step isn't in the journal yet: { petID, abilities = { [index] = id } }, or nil when done
-- (or when the slot is locked).
local function GetMissing(step)
    local loadedPetID, ability1, ability2, ability3, locked = C_PetJournal.GetPetLoadOutInfo(step.slot)
    if locked then
        return nil
    end
    local loadedAbilities = { ability1, ability2, ability3 }
    local missing = { abilities = {} }
    if loadedPetID ~= step.petID then
        missing.petID = step.petID
    end
    for index = 1, 3 do
        local abilityID = step.abilities[index]
        if abilityID and abilityID ~= loadedAbilities[index] then
            missing.abilities[index] = abilityID
        end
    end
    if missing.petID or next(missing.abilities) then
        return missing
    end
end

local function IsPlanDone(plan)
    for _, step in ipairs(plan) do
        if GetMissing(step) then
            return false
        end
    end
    return true
end

local function RunPlan(plan, token, attempt)
    if token ~= loadToken then
        return -- a newer load replaced this one
    end
    for _, step in ipairs(plan) do
        local missing = GetMissing(step)
        if missing then
            ns:Debug(format("Load attempt %d, slot %d: pet %s, abilities %s", attempt, step.slot,
                tostring(missing.petID or "ok"), next(missing.abilities) and "missing" or "ok"))
            if missing.petID then
                C_PetJournal.SetPetLoadOutInfo(step.slot, missing.petID)
            end
            for index, abilityID in pairs(missing.abilities) do
                C_PetJournal.SetAbility(step.slot, index, abilityID)
            end
        end
    end
    if not IsPlanDone(plan) and attempt < LOAD_MAX_ATTEMPTS then
        C_Timer.After(LOAD_RETRY_DELAY, function()
            RunPlan(plan, token, attempt + 1)
        end)
        return
    end
    ns:Debug(IsPlanDone(plan) and "Team loaded." or "Gave up loading; some slots didn't take.")
    -- Blizzard's loadout panel doesn't always redraw after an addon changes the slots.
    if PetJournal_UpdatePetLoadOut and PetJournal and PetJournal:IsShown() then
        PetJournal_UpdatePetLoadOut()
    end
    ns.TeamsPanel:Refresh()
end

function Teams:Load(team)
    local ok, reason = self:CanLoad()
    if not ok then
        ns:Print(reason)
        return
    end

    -- Random and leveling slots skip the team's own pets and the pets currently slotted (so they
    -- don't just shuffle pets between slots).
    local exclude = {}
    for slot = 1, NUM_SLOTS do
        local entry = team.pets[slot]
        if entry.petID then
            exclude[entry.petID] = true
        end
        local loadedPetID = C_PetJournal.GetPetLoadOutInfo(slot)
        if loadedPetID and (entry.random or entry.leveling) then
            exclude[loadedPetID] = true
        end
    end

    local plan = {}
    for slot = 1, NUM_SLOTS do
        local entry = team.pets[slot]
        local petID, abilities = nil, {}
        if entry.random then
            local pet = ns.Roster.PickRandomMaxLevel(ns.Roster:GetOwnedPets(), function(p)
                return Teams.MatchesRandomSlot(entry, p.petType)
            end, exclude)
            if pet then
                petID = pet.petID
            else
                local family = entry.petType > 0 and ns.GetFamilyName(entry.petType) or "battle"
                ns:Print(format("Slot %d of \"%s\": you have no %s pet.", slot, team.name, family))
            end
        elseif entry.leveling then
            local pet, isSubstitute = ns.LevelingQueue:PickForSlot(exclude, entry.preferences)
            if pet then
                petID = pet.petID
                if isSubstitute then
                    ns:Print(format("Slot %d: no leveling pet qualifies yet, using %s.", slot, pet.name))
                end
            else
                ns:Print(format("Slot %d of \"%s\": no leveling pet or suitable level 25 pet found.", slot, team.name))
            end
        elseif entry.petID and C_PetJournal.GetPetInfoByPetID(entry.petID) then
            petID = entry.petID
            for index = 1, 3 do
                abilities[index] = entry.abilities[index]
            end
        elseif entry.petID or entry.speciesID then
            local _, name = Teams.GetSlotDisplay(entry)
            ns:Print(format("Slot %d of \"%s\": %s isn't in your collection.", slot, team.name, name))
        end

        if petID then
            exclude[petID] = true
            plan[#plan + 1] = { slot = slot, petID = petID, abilities = abilities }
        end
    end

    ns:Debug(format("Loading \"%s\": %d slot(s) planned.", team.name, #plan))
    SetLoadedTeam(team)
    loadToken = loadToken + 1
    RunPlan(plan, loadToken, 1)
end

-- Groups
function Teams:GetGroups()
    return ns.db.groups
end

function Teams:GetGroup(groupID)
    for _, group in ipairs(ns.db.groups) do
        if group.id == groupID then
            return group
        end
    end
end

function Teams:CreateGroup(name)
    local group = { id = ns.db.nextGroupID, name = name, collapsed = false }
    ns.db.nextGroupID = group.id + 1
    tinsert(ns.db.groups, group)
    return group
end

function Teams:RenameGroup(group, name)
    group.name = name
end

function Teams:SetGroupIcon(group, icon)
    group.icon = icon
end

-- Teams in a deleted group become ungrouped.
-- Groups are shown in the order of the saved list; delta -1 moves a group up, 1 moves it down.
function Teams:MoveGroup(group, delta)
    local groups = ns.db.groups
    local index = tIndexOf(groups, group)
    local target = index and index + delta
    if target and target >= 1 and target <= #groups then
        groups[index], groups[target] = groups[target], groups[index]
    end
end

function Teams:DeleteGroup(group)
    for _, team in ipairs(self:GetAll()) do
        if team.groupID == group.id then
            team.groupID = nil
        end
    end
    tDeleteItem(ns.db.groups, group)
end

-- Collapse state; a nil groupID means the "Ungrouped" group.
function Teams:IsCollapsed(groupID)
    local group = groupID and self:GetGroup(groupID)
    if group then
        return group.collapsed
    end
    return ns.db.ungroupedCollapsed
end

function Teams:SetCollapsed(groupID, collapsed)
    local group = groupID and self:GetGroup(groupID)
    if group then
        group.collapsed = collapsed
    else
        ns.db.ungroupedCollapsed = collapsed
    end
end
