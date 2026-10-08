local _, ns = ...
local L = ns.L

-- A team is:
--   name        "Major Payne"
--   groupID     number, or nil for ungrouped
--   pets        { [slot] = { petID = "BattlePet-...", speciesID = number, abilities = { id, id, id },
--                 breed = 3-12 (optional: the breed the team asks for, e.g. from an import) } }
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

-- True for the team you loaded last. (Matching the loadout alone isn't enough: with random slots,
-- several teams can fit the same pets.) It stays loaded when you change pets or abilities;
-- HasChanges() tells whether it still matches.
function Teams:IsLoaded(team)
    return team ~= nil and team == self:GetLoadedTeam()
end

-- True if a fixed pet's saved ability differs from the one selected in the journal.
local function AbilitiesDiffer(team)
    for slot = 1, NUM_SLOTS do
        local entry = team.pets[slot]
        if not entry.random and not entry.leveling and entry.petID then
            local _, ability1, ability2, ability3 = C_PetJournal.GetPetLoadOutInfo(slot)
            local loaded = { ability1, ability2, ability3 }
            for index = 1, 3 do
                local saved = entry.abilities and entry.abilities[index]
                if saved and saved ~= loaded[index] then
                    return true
                end
            end
        end
    end
    return false
end

-- True if the journal's pets or abilities no longer match the saved team.
function Teams:HasChanges(team)
    return not LoadoutMatches(team) or AbilitiesDiffer(team)
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
        name = format(L["Team %d"], #self:GetAll() + 1),
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
        -- Abilities edited in the team editor go into the journal too, so the loaded team doesn't
        -- show up as changed right after saving it.
        self:ApplyAbilities(team)
    end
    return team
end

-- Returns icon, name, level, isMissing, rarity for a team slot; icon is nil for an empty slot.
-- level and rarity are nil when the slot isn't one specific pet (random slots, missing pets).
function Teams.GetSlotDisplay(entry)
    if entry.random then
        if entry.petType == 0 then
            return "Interface\\Icons\\INV_Misc_QuestionMark", L["Random level 25 pet"], nil, false
        end
        return ns.GetFamilyIcon(entry.petType), format(L["Random level 25 %s pet"], ns.GetFamilyName(entry.petType)), nil, false
    end
    if entry.leveling then
        local pet = ns.LevelingQueue:GetNext(nil, entry.preferences)
        if pet then
            local _, _, _, _, _, _, _, _, icon = C_PetJournal.GetPetInfoByPetID(pet.petID)
            return icon, L["Leveling: "] .. pet.name, pet.level, false, pet.rarity
        end
        -- The substitute is picked at random on load, so show the slot generically.
        local requirement = ns.LevelingQueue.DescribePreferences(entry.preferences)
        local reason = requirement and format(L["no leveling pet is %s"], requirement) or L["leveling queue is empty"]
        return "Interface\\Icons\\INV_Pet_BattlePetTraining", format(L["Any level 25 pet (%s)"], reason), nil, false
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
        return icon, (speciesName or L["Unknown pet"]) .. L[" (not collected)"], nil, true
    end
    return nil
end

-- Which of the two abilities each ability slot picks: { 1, 2, nil } (nil = left open, "keep
-- current"), plus the species' ability list (slot n picks list[n] or list[n + 3]). nil for slots
-- without a specific species (random, leveling, empty).
function Teams.GetAbilityChoices(entry)
    if not entry.speciesID then
        return nil
    end
    local list = ns.GetSpeciesAbilities(entry.speciesID).ids
    local choices = {}
    for index = 1, 3 do
        local selected = entry.abilities and entry.abilities[index]
        if selected == list[index] then
            choices[index] = 1
        elseif selected and selected == list[index + 3] then
            choices[index] = 2
        end
    end
    return choices, list
end

-- Saves the journal's current pets and abilities into the team. Random and leveling slots stay
-- random/leveling while the slotted pet still fits them; other slots take the slotted pet.
function Teams:UpdateFromLoadout(team)
    local captured = self:CaptureLoadout()
    for slot = 1, NUM_SLOTS do
        local entry = team.pets[slot]
        local current = captured[slot]
        local petType = current.petID and select(10, C_PetJournal.GetPetInfoByPetID(current.petID))
        local keepRandom = entry.random and petType and Teams.MatchesRandomSlot(entry, petType)
        local keepLeveling = entry.leveling and current.petID
        if not keepRandom and not keepLeveling then
            team.pets[slot] = current
        end
    end
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

-- Pets in the journal's loadout below full health: { { slot, petID, name, percent, dead } }.
-- The loadout rather than a team, since that's what goes into battle (random and leveling slots
-- included).
function Teams:GetInjuredPets()
    local injured = {}
    for slot = 1, NUM_SLOTS do
        local petID = C_PetJournal.GetPetLoadOutInfo(slot)
        if petID then
            local health, maxHealth = C_PetJournal.GetPetStats(petID)
            if maxHealth > 0 and health < maxHealth then
                local _, customName, _, _, _, _, _, speciesName = C_PetJournal.GetPetInfoByPetID(petID)
                injured[#injured + 1] = {
                    slot = slot,
                    petID = petID,
                    name = customName or speciesName,
                    percent = floor(health / maxHealth * 100),
                    dead = health == 0,
                }
            end
        end
    end
    return injured
end

-- "Mr. Bigglesworth (40%), Anubisath Idol (dead)"
function Teams.DescribeInjuredPets(injured)
    local parts = {}
    for i, pet in ipairs(injured) do
        parts[i] = format(pet.dead and L["%s (dead)"] or L["%s (%d%%)"], pet.name, pet.percent)
    end
    return table.concat(parts, ", ")
end

function Teams:CanLoad()
    if C_PetBattles.IsInBattle() then
        return false, L["You can't change pets during a battle."]
    end
    if not C_PetJournal.IsJournalUnlocked() then
        return false, L["The Pet Journal is locked."]
    end
    return true
end

-- Loading works from a plan of { slot, petID, abilities }: everything is set, then the journal is
-- checked and anything that didn't stick is set again, a few times, since the journal applies
-- loadout changes asynchronously.
local LOAD_RETRY_DELAY = 0.25
local LOAD_MAX_ATTEMPTS = 5
local loadToken = 0
local loading = false

-- True while a team is still being put into the journal (the loadout is in flux, so it shouldn't
-- be compared with the team yet).
function Teams:IsLoading()
    return loading
end

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
    loading = false
    ns:Debug(IsPlanDone(plan) and "Team loaded." or "Gave up loading; some slots didn't take.")
    local injured = Teams:GetInjuredPets()
    if #injured > 0 and not plan.quiet then
        ns:Print(format(L["Not at full health: %s"], Teams.DescribeInjuredPets(injured)))
    end
    -- Blizzard's loadout panel doesn't always redraw after an addon changes the slots.
    if PetJournal_UpdatePetLoadOut and PetJournal and PetJournal:IsShown() then
        PetJournal_UpdatePetLoadOut()
    end
    ns.TeamsPanel:Refresh()
end

-- If Rematch is running, tell it none of its teams is loaded anymore. Otherwise it keeps filling
-- the leveling slots of its last team from its own queue (after battles or level-ups) and would
-- swap pets in the Lineup team. Its leveling slots are cleared first, then its own unload runs.
local function ReleaseRematchTeam()
    local rematch = _G.Rematch
    if type(rematch) ~= "table" or type(rematch.settings) ~= "table" then
        return
    end
    pcall(function()
        if type(rematch.settings.SpecialSlots) == "table" then
            wipe(rematch.settings.SpecialSlots)
        end
        if rematch.settings.currentTeamID and rematch.loadTeam and rematch.loadTeam.UnloadTeam then
            rematch.loadTeam:UnloadTeam()
        end
    end)
end

-- Sets the team's saved abilities on the pets in the journal, where the slot still holds the
-- team's pet. Pets aren't touched, nor random or leveling slots (they'd be picked again).
function Teams:ApplyAbilities(team)
    if not self:CanLoad() then
        return
    end
    local plan = { quiet = true }
    for slot = 1, NUM_SLOTS do
        local entry = team.pets[slot]
        if entry.petID and entry.abilities and entry.petID == C_PetJournal.GetPetLoadOutInfo(slot) then
            plan[#plan + 1] = { slot = slot, petID = entry.petID, abilities = entry.abilities }
        end
    end
    if #plan == 0 or IsPlanDone(plan) then
        return
    end
    loading = true
    loadToken = loadToken + 1
    RunPlan(plan, loadToken, 1)
end

function Teams:Load(team)
    local ok, reason = self:CanLoad()
    if not ok then
        ns:Print(reason)
        return
    end
    ReleaseRematchTeam()

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
                local family = entry.petType > 0 and ns.GetFamilyName(entry.petType) or L["battle"]
                ns:Print(format(L["Slot %d of \"%s\": you have no %s pet."], slot, team.name, family))
            end
        elseif entry.leveling then
            local pet, isSubstitute = ns.LevelingQueue:PickForSlot(exclude, entry.preferences)
            if pet then
                petID = pet.petID
                if isSubstitute then
                    ns:Print(format(L["Slot %d: no leveling pet qualifies yet, using %s."], slot, pet.name))
                end
            else
                ns:Print(format(L["Slot %d of \"%s\": no leveling pet or suitable level 25 pet found."], slot, team.name))
            end
        elseif entry.petID and C_PetJournal.GetPetInfoByPetID(entry.petID) then
            petID = entry.petID
            for index = 1, 3 do
                abilities[index] = entry.abilities[index]
            end
        elseif entry.petID or entry.speciesID then
            local _, name = Teams.GetSlotDisplay(entry)
            ns:Print(format(L["Slot %d of \"%s\": %s isn't in your collection."], slot, team.name, name))
        end

        if petID then
            exclude[petID] = true
            plan[#plan + 1] = { slot = slot, petID = petID, abilities = abilities }
        end
    end

    ns:Debug(format("Loading \"%s\": %d slot(s) planned.", team.name, #plan))
    SetLoadedTeam(team)
    loading = true
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

-- Groups are shown in the order of the saved list; delta -1 moves a group up, 1 moves it down.
function Teams:MoveGroup(group, delta)
    local groups = ns.db.groups
    local index = tIndexOf(groups, group)
    local target = index and index + delta
    if target and target >= 1 and target <= #groups then
        groups[index], groups[target] = groups[target], groups[index]
    end
end

function Teams:SortGroupsByName()
    table.sort(ns.db.groups, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
end

function Teams:GetGroupTeams(group)
    local teams = {}
    for _, team in ipairs(self:GetAll()) do
        if team.groupID == group.id then
            teams[#teams + 1] = team
        end
    end
    return teams
end

-- Teams in a deleted group become ungrouped, or with deleteTeams are deleted along with it.
function Teams:DeleteGroup(group, deleteTeams)
    for _, team in ipairs(self:GetGroupTeams(group)) do
        if deleteTeams then
            self:Delete(team)
        else
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

-- True if any group is collapsed, or "Ungrouped" while it has teams (otherwise it isn't shown).
function Teams:IsAnyCollapsed()
    local groupExists = {}
    for _, group in ipairs(ns.db.groups) do
        if group.collapsed then
            return true
        end
        groupExists[group.id] = true
    end
    if ns.db.ungroupedCollapsed then
        for _, team in ipairs(self:GetAll()) do
            if not groupExists[team.groupID] then
                return true
            end
        end
    end
    return false
end

function Teams:SetAllCollapsed(collapsed)
    for _, group in ipairs(ns.db.groups) do
        group.collapsed = collapsed
    end
    ns.db.ungroupedCollapsed = collapsed
end

function Teams:SetCollapsed(groupID, collapsed)
    local group = groupID and self:GetGroup(groupID)
    if group then
        group.collapsed = collapsed
    else
        ns.db.ungroupedCollapsed = collapsed
    end
end
