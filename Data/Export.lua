local _, ns = ...

-- Teams as Rematch team strings, the format the importer reads (see Import.lua), so they can be
-- shared or imported again, in Lineup or in Rematch:
--   Name:npcID:petTag1:petTag2:petTag3:[P:minHP:allowMM:expectedDD:maxHP:minXP:maxXP:][N:notes]
-- The team's script goes into the notes, between the BEGIN/END PET BATTLE SCRIPT lines.
local Export = {}
ns.Export = Export

local SCRIPT_BEGIN = "-----BEGIN PET BATTLE SCRIPT-----"
local SCRIPT_END = "-----END PET BATTLE SCRIPT-----"
local BASE32_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUV"

local function ToBase32(number)
    number = floor(number)
    local digits = ""
    repeat
        local digit = number % 32
        digits = BASE32_DIGITS:sub(digit + 1, digit + 1) .. digits
        number = floor(number / 32)
    until number == 0
    return digits
end

-- Colons separate the fields, so they can't be part of a name.
local function CleanName(name)
    return (name:gsub(":", ""))
end

-- Pet tag: the three ability choices (0 = any, 1 or 2), breed (0 = any; Lineup doesn't track
-- breeds), then the speciesID; or ZL (leveling), ZR<family> (random) and ZI (empty).
local function PetTag(entry)
    if entry.leveling then
        return "ZL"
    elseif entry.random then
        return "ZR" .. ToBase32(entry.petType or 0)
    elseif not entry.speciesID then
        return "ZI"
    end
    local choices = ns.Teams.GetAbilityChoices(entry) or {}
    return format("%d%d%d0%s", choices[1] or 0, choices[2] or 0, choices[3] or 0, ToBase32(entry.speciesID))
end

-- P:minHP:allowMM:expectedDD:maxHP:minXP:maxXP: from the first leveling slot with preferences.
local function Preferences(team)
    for _, entry in ipairs(team.pets) do
        local preferences = entry.leveling and entry.preferences
        if preferences and next(preferences) then
            return format("P:%s:%s:%s:%s:%s:%s:", preferences.minHP or "", preferences.allowMM and "1" or "",
                preferences.expectedDD or "", preferences.maxHP or "", preferences.minXP or "", preferences.maxXP or "")
        end
    end
    return ""
end

-- The notes field: notes, then the script block; line breaks written as "\n".
local function Notes(team)
    local parts = {}
    if team.notes and strtrim(team.notes) ~= "" then
        parts[#parts + 1] = strtrim(team.notes)
    end
    if team.script and strtrim(team.script) ~= "" then
        parts[#parts + 1] = SCRIPT_BEGIN .. "\n" .. strtrim(team.script) .. "\n" .. SCRIPT_END
    end
    if #parts == 0 then
        return ""
    end
    return "N:" .. table.concat(parts, "\n\n"):gsub("\r?\n", "\\n")
end

function Export.Team(team)
    local tags = {}
    for slot = 1, 3 do
        tags[slot] = team.pets[slot] and PetTag(team.pets[slot]) or "ZI"
    end
    return format("%s:%s:%s:%s:%s:", CleanName(team.name), team.targetNpcID and ToBase32(team.targetNpcID) or "",
        tags[1], tags[2], tags[3]) .. Preferences(team) .. Notes(team)
end

-- Group header line, as Rematch writes them: __ Name:sort:icon:color: __ (only name and icon).
local function GroupHeader(group)
    local icon = group.icon
    if type(icon) == "string" then
        icon = tonumber(icon) or GetFileIDFromPath(icon)
    end
    return format("__ %s::%s:: __", CleanName(group.name), icon and ToBase32(icon) or "")
end

local function SortedTeams(groupID)
    local teams = {}
    for _, team in ipairs(ns.Teams:GetAll()) do
        if team.groupID == groupID then
            teams[#teams + 1] = team
        end
    end
    table.sort(teams, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return teams
end

-- The group's header and its teams, one per line.
function Export.Group(group)
    local lines = { GroupHeader(group) }
    for _, team in ipairs(SortedTeams(group.id)) do
        lines[#lines + 1] = Export.Team(team)
    end
    return table.concat(lines, "\n")
end

-- Every team: ungrouped ones first (before any header, so they stay ungrouped on import), then
-- each group in order.
function Export.All()
    local lines = {}
    local groupExists = {}
    for _, group in ipairs(ns.Teams:GetGroups()) do
        groupExists[group.id] = true
    end
    for _, team in ipairs(ns.Teams:GetAll()) do
        if not groupExists[team.groupID] then
            lines[#lines + 1] = Export.Team(team)
        end
    end
    table.sort(lines, function(a, b)
        return a:lower() < b:lower()
    end)
    for _, group in ipairs(ns.Teams:GetGroups()) do
        lines[#lines + 1] = Export.Group(group)
    end
    return table.concat(lines, "\n")
end
