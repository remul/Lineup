local _, ns = ...
local L = ns.L

-- Imports Rematch team strings, as published by Xu-Fu's Pet Guides and others:
--   Name:npcIDs:petTag1:petTag2:petTag3:[P:minHP:allowMM:expectedDD:maxHP:minXP:maxXP:][N:notes]
-- npcIDs are comma-separated base 32 numbers. Notes use "\n" for line breaks and may contain a
-- tdBattlePetScript between "-----BEGIN PET BATTLE SCRIPT-----" and "-----END PET BATTLE SCRIPT-----".
--
-- A pet tag is base 32: three ability choices (0 = any, 1 or 2 = which ability of that slot),
-- one breed digit (0 = any, 3-12 = a breed, see Breeds), then the speciesID; e.g. 02282KE.
-- Special tags: ZL leveling pet, ZI ignored slot, ZR<type> random pet of a family (0 = any),
-- ZN/ZU unknown.
local Import = {}
ns.Import = Import

-- P:minHP:allowMM:expectedDD:maxHP:minXP:maxXP: (levels may be decimals like 23.5)
local PREFERENCES_PATTERN = "^P:(%d*):(%d*):(%d*):(%d*):([%d%.]*):([%d%.]*):(.*)$"
-- The lines around a script in team notes (also written by Export).
local SCRIPT_BEGIN = "-----BEGIN PET BATTLE SCRIPT-----"
local SCRIPT_END = "-----END PET BATTLE SCRIPT-----"
local SCRIPT_PATTERN = "%-%-%-%-%-BEGIN PET BATTLE SCRIPT%-%-%-%-%-(.-)%-%-%-%-%-END PET BATTLE SCRIPT%-%-%-%-%-"
Import.SCRIPT_BEGIN, Import.SCRIPT_END = SCRIPT_BEGIN, SCRIPT_END

local function ParseTag(tag)
    if tag == "" or tag == "ZI" then
        return { kind = "empty" }
    elseif tag == "ZL" then
        return { kind = "leveling" }
    elseif tag:match("^ZR") then
        return { kind = "random", petType = tonumber(tag:sub(3), 32) or 0 }
    elseif tag:match("^Z") then
        return { kind = "empty" }
    end
    local speciesID = tonumber(tag:sub(5), 32)
    if not speciesID then
        return nil
    end
    local choices = {}
    for i = 1, 3 do
        choices[i] = tonumber(tag:sub(i, i), 32) or 0
    end
    local breed = ns.Breeds.Normalize(tonumber(tag:sub(4, 4), 32))
    return { kind = "species", speciesID = speciesID, choices = choices, breed = breed }
end

-- Parses the text without touching the pet journal. Returns a table or nil, errorMessage.
---@param text string
function Import.Parse(text)
    -- Treat real line breaks like escaped ones, so pasted multi-line text works too.
    text = strtrim(text or "")
    text = text:gsub("\r\n", "\n")
    text = text:gsub("\n", "\\n")

    local name, npcIDs, tag1, tag2, tag3, extras = text:match("^(.-):([%w,]*):(%w*):(%w*):(%w*):(.*)$")
    if not name or strtrim(name) == "" then
        return nil, L["Not a team string. Paste the whole line, starting with the team name."]
    end

    local result = { name = strtrim(name), targets = {}, slots = {} }
    for npcID in npcIDs:gmatch("[^,]+") do
        result.targets[#result.targets + 1] = tonumber(npcID, 32)
    end
    for slot, tag in ipairs({ tag1, tag2, tag3 }) do
        result.slots[slot] = ParseTag(tag)
        if not result.slots[slot] then
            return nil, format(L["Pet %d has an unreadable tag \"%s\"."], slot, tag)
        end
    end

    local minHP, allowMM, expectedDD, maxHP, minXP, maxXP, rest = extras:match(PREFERENCES_PATTERN)
    if minHP then
        result.preferences = {
            minHP = tonumber(minHP),
            allowMM = allowMM == "1" or nil,
            expectedDD = tonumber(expectedDD),
            maxHP = tonumber(maxHP),
            minXP = tonumber(minXP),
            maxXP = tonumber(maxXP),
        }
        if not next(result.preferences) then
            result.preferences = nil
        end
        extras = rest
    end
    local notes = extras:match("^N:(.*)$")
    if notes then
        notes = notes:gsub("\\n", "\n")
        local script = notes:match(SCRIPT_PATTERN)
        if script then
            result.script = strtrim(script)
            notes = notes:gsub(SCRIPT_PATTERN, "")
        end
        notes = strtrim(notes)
        result.notes = notes ~= "" and notes or nil
    end
    return result
end

-- Team names often look like "Julia Stevens (Elemental)"; the target is the part before the brackets.
local function GuessTargetName(teamName)
    local name = strtrim((teamName:gsub("%s*%b()%s*$", "")))
    return name ~= "" and name or teamName
end

-- Severity of an import note: something is missing, something is off, or just good to know.
Import.ERROR, Import.WARNING, Import.INFO = "error", "warning", "info"

-- Owned pets by species ([speciesID] = { pet, ... }), for the roster list it was built from, so a big
-- import doesn't go through every pet for every slot.
local petsBySpecies, petsBySpeciesOf

local function GetPetsOfSpecies(owned, speciesID)
    if petsBySpeciesOf ~= owned then
        petsBySpecies, petsBySpeciesOf = {}, owned
        for _, pet in ipairs(owned) do
            local list = petsBySpecies[pet.speciesID]
            if not list then
                list = {}
                petsBySpecies[pet.speciesID] = list
            end
            list[#list + 1] = pet
        end
    end
    return petsBySpecies[speciesID] or {}
end

local function Any()
    return true
end

-- The pet to use for a slot: the best one of the species, or one of the wanted breed when it's as
-- good (a low-level pet of the right breed doesn't help in a level 25 fight).
local function PickPet(owned, info, used)
    local candidates = GetPetsOfSpecies(owned, info.speciesID)
    local best = ns.Roster.PickBest(candidates, Any, used)
    if best and info.breed and not ns.Breeds.PetCanBe(best.petID, info.breed) then
        local ofBreed = ns.Roster.PickBest(candidates, function(pet)
            return ns.Breeds.PetCanBe(pet.petID, info.breed)
        end, used)
        if ofBreed and ofBreed.level >= best.level then
            return ofBreed
        end
    end
    return best
end

-- What's off about the pet chosen for a species slot, e.g. { "level 18", "H/H instead of P/S" }.
local function DescribePetIssues(pet, entry)
    local issues = {}
    if pet.level < 25 then
        issues[#issues + 1] = format(L["level %d"], pet.level)
    end
    local breed = ns.Breeds.DescribePet(pet.petID)
    if entry.breed and breed and not ns.Breeds.PetCanBe(pet.petID, entry.breed) then
        issues[#issues + 1] = format(L["%s instead of %s"], breed, ns.Breeds.NAMES[entry.breed])
    end
    -- Picked abilities the pet hasn't learned yet.
    local abilities = ns.GetSpeciesAbilities(entry.speciesID)
    local abilityIDs, levels = abilities.ids, abilities.levels
    for index = 1, 3 do
        local abilityID = entry.abilities[index]
        local position = abilityID and tIndexOf(abilityIDs, abilityID)
        local needed = position and levels[position]
        if needed and needed > pet.level then
            local abilityName = ns.GetAbilityInfo(abilityID)
            issues[#issues + 1] = format(L["%s from level %d"], abilityName, needed)
        end
    end
    return issues
end

-- Turns a parsed import into a team draft, picking your best owned pets.
-- Returns draft, notes: { { severity = Import.ERROR / WARNING / INFO, text } }, one per slot that
-- needs a word, then the script's check.
function Import.BuildDraft(parsed)
    local notes = {}
    local function Note(severity, text)
        notes[#notes + 1] = { severity = severity, text = text }
    end
    local owned = ns.Roster:GetOwnedPets()
    local used = {}

    local pets = {}
    for slot, info in ipairs(parsed.slots) do
        local entry = { abilities = {} }
        if info.kind == "species" then
            entry.speciesID = info.speciesID
            entry.breed = info.breed
            local abilityList = ns.GetSpeciesAbilities(info.speciesID).ids
            for i, choice in ipairs(info.choices) do
                if choice == 1 or choice == 2 then
                    entry.abilities[i] = abilityList[i + (choice - 1) * 3]
                end
            end

            local speciesName = ns.GetSpeciesInfo(info.speciesID) or format(L["species %d"], info.speciesID)
            local pet = PickPet(owned, info, used)
            if pet then
                entry.petID = pet.petID
                used[pet.petID] = true
                local issues = DescribePetIssues(pet, entry)
                if #issues > 0 then
                    Note(Import.WARNING, format(L["Slot %d (%s): %s"], slot, speciesName, table.concat(issues, " · ")))
                end
            elseif info.breed then
                Note(Import.ERROR, format(L["Slot %d: you don't have a %s %s."], slot, ns.Breeds.NAMES[info.breed], speciesName))
            else
                Note(Import.ERROR, format(L["Slot %d: you don't have a %s."], slot, speciesName))
            end
        elseif info.kind == "random" then
            entry = { random = true, petType = info.petType }
            local family = info.petType > 0 and ns.GetFamilyName(info.petType) or L["any"]
            local count = 0
            for _, pet in ipairs(owned) do
                if pet.canBattle and pet.level >= 25 and ns.Teams.MatchesRandomSlot(entry, pet.petType) then
                    count = count + 1
                end
            end
            if count > 0 then
                Note(Import.INFO, format(L["Slot %d: a random level 25 %s pet, picked on each load (you have %d)."], slot, family, count))
            else
                Note(Import.WARNING, format(L["Slot %d: a random %s pet, but none of yours is level 25."], slot, family))
            end
        elseif info.kind == "leveling" then
            entry = { leveling = true, preferences = parsed.preferences }
            local requirement = ns.LevelingQueue.DescribePreferences(parsed.preferences)
            local label = requirement and format(L["Slot %d: leveling pet (%s)"], slot, requirement) or format(L["Slot %d: leveling pet"], slot)
            local nextPet = ns.LevelingQueue:GetNext(used, parsed.preferences)
            if nextPet then
                used[nextPet.petID] = true
                Note(Import.INFO, format(L["%s, now %s (level %d)."], label, nextPet.name, nextPet.level))
            else
                Note(Import.INFO, format(L["%s; none qualifies yet, so a level 25 pet is used."], label))
            end
        end
        pets[slot] = entry
    end

    if #parsed.targets > 1 then
        Note(Import.INFO, L["Several targets are listed; only the first is used."])
    end
    -- The script, checked against the team as imported.
    if parsed.script then
        local check = ns.Script.Check(parsed.script, pets)
        if check.level == "error" or check.level == "warning" then
            Note(Import.WARNING, L["Script: "] .. check.summary)
        end
    end

    local npcID = parsed.targets[1]
    local draft = {
        name = parsed.name,
        pets = pets,
        targetNpcID = npcID,
        targetName = npcID and GuessTargetName(parsed.name),
        script = parsed.script or "",
        notes = parsed.notes,
    }
    return draft, notes
end

-- The notes that need attention (errors and warnings), as text.
function Import.GetProblems(notes)
    local problems = {}
    for _, note in ipairs(notes) do
        if note.severity ~= Import.INFO then
            problems[#problems + 1] = note.text
        end
    end
    return problems
end

-- Splits text into teams and Rematch group headers ("__ Name:sort:icon:color:showTab: __").
-- A team starts on a line that looks like a team string; other lines continue the team above
-- (so a single team pasted with real line breaks still works).
-- Returns { entries = { { kind = "group", name, icon } | { kind = "team", parsed } }, numTeams, errors }.
function Import.ParseAll(text)
    local result = { entries = {}, numTeams = 0, errors = {} }
    local records = {}
    for line in ((text or ""):gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do
        local trimmed = strtrim(line)
        local header = trimmed:match("^__ (.+) __$")
        if header then
            local fields = { strsplit(":", header) }
            records[#records + 1] = { group = { name = strtrim(fields[1]), icon = tonumber(fields[3] or "", 32) } }
        elseif trimmed:match("^.-:[%w,]*:%w*:%w*:%w*:") then
            records[#records + 1] = { text = trimmed }
        elseif trimmed ~= "" then
            local last = records[#records]
            if last and last.text then
                last.text = last.text .. "\n" .. line
            else
                result.errors[#result.errors + 1] = trimmed
            end
        end
    end

    for _, record in ipairs(records) do
        if record.group then
            if record.group.name ~= "" then
                result.entries[#result.entries + 1] = { kind = "group", name = record.group.name, icon = record.group.icon }
            end
        else
            local parsed, err = Import.Parse(record.text)
            if parsed then
                result.entries[#result.entries + 1] = { kind = "team", parsed = parsed }
                result.numTeams = result.numTeams + 1
            else
                result.errors[#result.errors + 1] = err
            end
        end
    end
    return result
end

local function FindGroupByName(name)
    for _, group in ipairs(ns.Teams:GetGroups()) do
        if group.name == name then
            return group
        end
    end
end

-- Saves every team of a ParseAll result. Teams go into groupID unless a group header comes first.
-- With replace, a team you already had with the same name is overwritten (once: a name repeated in
-- the import is added again); otherwise, and for repeats, the new team's name gets a number. A group header
-- named ungroupedName (Rematch's "Ungrouped") puts the teams after it in no group.
-- Returns numImported, numReplaced, problems ({ teamName, list of problem strings }).
function Import.ImportAll(result, groupID, replace, ungroupedName)
    local numImported, numReplaced, problems = 0, 0, {}
    -- Teams from before the import by name, so big imports don't scan the whole list for every team.
    local teamsByName = {}
    for _, team in ipairs(ns.Teams:GetAll()) do
        teamsByName[team.name] = teamsByName[team.name] or team
    end
    for _, entry in ipairs(result.entries) do
        if entry.kind == "group" and entry.name == ungroupedName then
            groupID = nil
        elseif entry.kind == "group" then
            local group = FindGroupByName(entry.name) or ns.Teams:CreateGroup(entry.name)
            if entry.icon and not group.icon then
                ns.Teams:SetGroupIcon(group, entry.icon)
            end
            groupID = group.id
        else
            local draft, notes = Import.BuildDraft(entry.parsed)
            local teamProblems = Import.GetProblems(notes)
            draft.groupID = groupID
            local existing = replace and teamsByName[draft.name]
            if existing then
                teamsByName[draft.name] = nil
            end
            ns.Teams:Save(existing, draft)
            numImported = numImported + 1
            if existing then
                numReplaced = numReplaced + 1
            end
            if #teamProblems > 0 then
                problems[#problems + 1] = { teamName = draft.name, problems = teamProblems }
            end
        end
    end
    return numImported, numReplaced, problems
end

-- What ImportAll would do, for a confirmation prompt: "Import 12 teams? 3 replace teams you
-- already have. Creates the group "Humanoid"."
function Import.DescribeImportAll(result, replace, ungroupedName)
    local teamNames, groupNames = {}, {}
    for _, team in ipairs(ns.Teams:GetAll()) do
        teamNames[team.name] = true
    end
    for _, group in ipairs(ns.Teams:GetGroups()) do
        groupNames[group.name] = true
    end

    -- Like ImportAll: each team you have is replaced at most once; other taken names get a number.
    local numReplaced, numRenamed, newGroups = 0, 0, {}
    for _, entry in ipairs(result.entries) do
        if entry.kind == "team" then
            local name = entry.parsed.name
            if teamNames[name] == true and replace then
                numReplaced = numReplaced + 1
                teamNames[name] = "replaced"
            elseif teamNames[name] then
                numRenamed = numRenamed + 1
            end
            teamNames[name] = teamNames[name] or "imported"
        elseif entry.kind == "group" and entry.name ~= ungroupedName and not groupNames[entry.name] then
            groupNames[entry.name] = true
            newGroups[#newGroups + 1] = entry.name
        end
    end

    local lines = { format(result.numTeams == 1 and L["Import %d team?"] or L["Import %d teams?"], result.numTeams) }
    if numReplaced > 0 then
        lines[#lines + 1] = format(numReplaced == 1 and L["%d replaces a team you already have."] or L["%d replace teams you already have."], numReplaced)
    end
    if numRenamed > 0 then
        lines[#lines + 1] = format(L["Names already taken get a number (%d)."], numRenamed)
    end
    if #newGroups == 1 then
        lines[#lines + 1] = format(L["Creates the group \"%s\"."], newGroups[1])
    elseif #newGroups > 1 then
        lines[#lines + 1] = format(L["Creates %d groups."], #newGroups)
    end
    return table.concat(lines, "\n")
end

-- Runs onConfirm after asking first, but only when more than one team would be imported.
function Import.ConfirmImportAll(result, replace, ungroupedName, prefix, onConfirm)
    if result.numTeams <= 1 then
        onConfirm()
        return
    end
    ns.Dialogs.Confirm((prefix or "") .. Import.DescribeImportAll(result, replace, ungroupedName), onConfirm)
end

-- One-line summary for the import window.
function Import.Describe(parsed)
    local parts = { parsed.name }
    if parsed.targets[1] then
        parts[#parts + 1] = format(L["NPC %d"], parsed.targets[1])
    end
    if parsed.script then
        parts[#parts + 1] = L["script: "] .. ns.Script.Describe(parsed.script)
    end
    if parsed.notes then
        parts[#parts + 1] = L["notes"]
    end
    return table.concat(parts, "  ·  ")
end

local MAX_REPORTED_TEAMS = 10

-- Prints the outcome of ImportAll to chat: one line per team that needs attention (capped, so big
-- imports don't flood chat).
function Import.Report(numImported, numReplaced, problems)
    ns:Print(format(L["Imported %d teams%s."], numImported, numReplaced > 0 and format(L[" (%d replaced)"], numReplaced) or ""))
    for index, team in ipairs(problems) do
        if index > MAX_REPORTED_TEAMS then
            ns:Print(format(L["...and %d more teams need attention. Hover a team to see its pets."], #problems - MAX_REPORTED_TEAMS))
            break
        end
        ns:Print(format(L["%s: %s"], team.teamName, table.concat(team.problems, "; ")))
    end
end

-- Importing straight from Rematch while it's loaded. Rematch publishes its namespace as the global
-- "Rematch"; its own export functions produce the same team strings this importer reads.
-- tdBattlePetScript keeps scripts for Rematch teams separately, keyed by Rematch teamID, so those
-- are added to each team's notes in the usual BEGIN/END block.

function Import.IsRematchAvailable()
    local R = _G.Rematch
    return type(R) == "table" and R.teamStrings and R.teamStrings.ExportTeam and R.savedGroups
        and R.settings and R.settings.GroupOrder and true or false
end

local function GetBattleScriptCode(rematchTeamID)
    local scripts = _G.PetBattleScripts
    local plugin = scripts and scripts.GetPlugin and scripts:GetPlugin("Rematch")
    local script = plugin and plugin:GetScript(rematchTeamID)
    return script and script:GetCode()
end

local function AddScriptToTeamString(line, code)
    if line:find(SCRIPT_BEGIN, 1, true) then
        return line -- the notes already carry a script
    end
    local block = (SCRIPT_BEGIN .. "\n" .. strtrim(code) .. "\n" .. SCRIPT_END):gsub("\n", "\\n")
    local extras = line:match("^.-:[%w,]*:%w*:%w*:%w*:(.*)$") or ""
    -- Preferences are only digits and colons, so "N:" in the extras means the team has notes.
    local hasNotes = extras:find("N:", 1, true) ~= nil
    return line .. (hasNotes and "\\n\\n" or "N:") .. block
end

-- Returns all Rematch teams as import text (group headers and one team per line) and the name of
-- Rematch's ungrouped group; or nil, errorMessage.
function Import.ExportFromRematch()
    local R = _G.Rematch
    local settings = R.settings
    local includeNotes, includePreferences = settings.ExportIncludeNotes, settings.ExportIncludePreferences
    settings.ExportIncludeNotes, settings.ExportIncludePreferences = true, true

    local lines = {}
    local ok, err = pcall(function()
        for _, groupID in ipairs(settings.GroupOrder) do
            local group = R.savedGroups[groupID]
            local header = group and R.teamStrings:ExportHeader(groupID)
            if header then
                lines[#lines + 1] = header
                for _, teamID in ipairs(group.teams or {}) do
                    local line = R.teamStrings:ExportTeam(teamID)
                    if line then
                        local code = GetBattleScriptCode(teamID)
                        lines[#lines + 1] = code and AddScriptToTeamString(line, code) or line
                    end
                end
            end
        end
    end)

    settings.ExportIncludeNotes, settings.ExportIncludePreferences = includeNotes, includePreferences
    if not ok then
        return nil, err
    end
    local ungrouped = R.savedGroups["group:none"]
    return table.concat(lines, "\n"), ungrouped and ungrouped.name
end
