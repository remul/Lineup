local _, ns = ...

-- Imports Rematch team strings, as published by Xu-Fu's Pet Guides and others:
--   Name:npcIDs:petTag1:petTag2:petTag3:[P:minHP:allowMM:expectedDD:maxHP:minXP:maxXP:][N:notes]
-- npcIDs are comma-separated base 32 numbers. Notes use "\n" for line breaks and may contain a
-- tdBattlePetScript between "-----BEGIN PET BATTLE SCRIPT-----" and "-----END PET BATTLE SCRIPT-----".
--
-- A pet tag is base 32: three ability choices (0 = any, 1 or 2 = which ability of that slot),
-- one breed digit, then the speciesID; e.g. 02202KE. Special tags: ZL leveling pet, ZI ignored
-- slot, ZR<type> random pet of a family (0 = any), ZN/ZU unknown.
local Import = {}
ns.Import = Import

-- P:minHP:allowMM:expectedDD:maxHP:minXP:maxXP: (levels may be decimals like 23.5)
local PREFERENCES_PATTERN = "^P:(%d*):(%d*):(%d*):(%d*):([%d%.]*):([%d%.]*):(.*)$"
local SCRIPT_PATTERN = "%-%-%-%-%-BEGIN PET BATTLE SCRIPT%-%-%-%-%-(.-)%-%-%-%-%-END PET BATTLE SCRIPT%-%-%-%-%-"

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
    return { kind = "species", speciesID = speciesID, choices = choices }
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
        return nil, "Not a team string. Paste the whole line, starting with the team name."
    end

    local result = { name = strtrim(name), targets = {}, slots = {} }
    for npcID in npcIDs:gmatch("[^,]+") do
        result.targets[#result.targets + 1] = tonumber(npcID, 32)
    end
    for slot, tag in ipairs({ tag1, tag2, tag3 }) do
        result.slots[slot] = ParseTag(tag)
        if not result.slots[slot] then
            return nil, format("Pet %d has an unreadable tag \"%s\".", slot, tag)
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

-- Turns a parsed import into a team draft, picking your best owned pets.
-- Returns draft, warnings, problems: warnings are all notes for the player, problems the subset
-- that needs attention (missing or under-leveled pets), used when importing many teams at once.
function Import.BuildDraft(parsed)
    local warnings, problems = {}, {}
    local function Warn(text, isProblem)
        warnings[#warnings + 1] = text
        if isProblem then
            problems[#problems + 1] = text
        end
    end
    local owned = ns.Roster:GetOwnedPets()
    local used = {}

    local pets = {}
    for slot, info in ipairs(parsed.slots) do
        local entry = { abilities = {} }
        if info.kind == "species" then
            entry.speciesID = info.speciesID
            local pet = ns.Roster.PickBest(owned, function(p)
                return p.speciesID == info.speciesID
            end, used)
            local speciesName = ns.GetSpeciesInfo(info.speciesID) or ("species " .. info.speciesID)
            if pet then
                entry.petID = pet.petID
                used[pet.petID] = true
                if pet.level < 25 then
                    Warn(format("Slot %d: your %s is only level %d.", slot, speciesName, pet.level), true)
                end
            else
                Warn(format("Slot %d: you don't have a battle-ready %s.", slot, speciesName), true)
            end
            local abilityList = C_PetJournal.GetPetAbilityList(info.speciesID)
            for i, choice in ipairs(info.choices) do
                if choice == 1 or choice == 2 then
                    entry.abilities[i] = abilityList[i + (choice - 1) * 3]
                end
            end
        elseif info.kind == "random" then
            entry = { random = true, petType = info.petType }
            local family = info.petType > 0 and ns.GetFamilyName(info.petType) or "any"
            local count = 0
            for _, pet in ipairs(owned) do
                if pet.canBattle and pet.level >= 25 and ns.Teams.MatchesRandomSlot(entry, pet.petType) then
                    count = count + 1
                end
            end
            if count > 0 then
                Warn(format("Slot %d: a random level 25 %s pet, picked each time you load the team (you have %d).", slot, family, count))
            else
                Warn(format("Slot %d: a random %s pet, but you have none at level 25; your highest one is used.", slot, family), true)
            end
        elseif info.kind == "leveling" then
            entry = { leveling = true, preferences = parsed.preferences }
            local requirement = ns.LevelingQueue.DescribePreferences(parsed.preferences)
            local label = requirement and format("Slot %d is a leveling slot (%s)", slot, requirement) or format("Slot %d is a leveling slot", slot)
            local nextPet = ns.LevelingQueue:GetNext(used, parsed.preferences)
            if nextPet then
                used[nextPet.petID] = true
                Warn(format("%s: uses your leveling queue, now %s (level %d).", label, nextPet.name, nextPet.level))
            else
                Warn(format("%s: no pet in your leveling queue qualifies yet, so a level 25 pet is used instead.", label))
            end
        end
        pets[slot] = entry
    end

    if #parsed.targets > 1 then
        Warn("This team lists several targets; only the first is used.")
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
    return draft, warnings, problems
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
-- With replace, a team with the same name is overwritten instead of added again. A group header
-- named ungroupedName (Rematch's "Ungrouped") puts the teams after it in no group.
-- Returns numImported, numReplaced, problems ({ teamName, list of problem strings }).
function Import.ImportAll(result, groupID, replace, ungroupedName)
    local numImported, numReplaced, problems = 0, 0, {}
    -- Existing teams by name, so big imports don't scan the whole list for every team.
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
            local draft, _, teamProblems = Import.BuildDraft(entry.parsed)
            draft.groupID = groupID
            local existing = replace and teamsByName[draft.name]
            local team = ns.Teams:Save(existing, draft)
            teamsByName[team.name] = teamsByName[team.name] or team
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

-- One-line summary for the import window.
function Import.Describe(parsed)
    local parts = { parsed.name }
    if parsed.targets[1] then
        parts[#parts + 1] = format("NPC %d", parsed.targets[1])
    end
    if parsed.script then
        parts[#parts + 1] = "script: " .. ns.Script.Describe(parsed.script)
    end
    if parsed.notes then
        parts[#parts + 1] = "notes"
    end
    return table.concat(parts, "  ·  ")
end

local MAX_REPORTED_PROBLEMS = 10

-- Prints the outcome of ImportAll to chat (problems are capped so big imports don't flood chat).
function Import.Report(numImported, numReplaced, problems)
    ns:Print(format("Imported %d teams%s.", numImported, numReplaced > 0 and format(" (%d replaced)", numReplaced) or ""))
    local printed, total = 0, 0
    for _, team in ipairs(problems) do
        for _, problem in ipairs(team.problems) do
            total = total + 1
            if printed < MAX_REPORTED_PROBLEMS then
                ns:Print(format("%s: %s", team.teamName, problem))
                printed = printed + 1
            end
        end
    end
    if total > printed then
        ns:Print(format("...and %d more problems. Hover a team to see its pets.", total - printed))
    end
end

-- Importing straight from Rematch while it's loaded. Rematch publishes its namespace as the global
-- "Rematch"; its own export functions produce the same team strings this importer reads.
-- tdBattlePetScript keeps scripts for Rematch teams separately, keyed by Rematch teamID, so those
-- are added to each team's notes in the usual BEGIN/END block.
local SCRIPT_BEGIN = "-----BEGIN PET BATTLE SCRIPT-----"
local SCRIPT_END = "-----END PET BATTLE SCRIPT-----"

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
