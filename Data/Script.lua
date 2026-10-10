local _, ns = ...
local L = ns.L

-- Light validation of tdBattlePetScript text, e.g.
--   use(Explode:282) [enemy.hp<619]
--   change(next)
-- This only checks the structure; when tdBattlePetScript is installed, its own parser has the last
-- word (see Script.Check), and it runs the scripts (see BattleScripts).
local Script = {}
ns.Script = Script

local COMMANDS = {
    use = true,
    ability = true,
    change = true,
    standby = true,
    quit = true,
    catch = true,
    test = true,
}

local function IsBalanced(text, open, close)
    local depth = 0
    for char in text:gmatch("[%" .. open .. "%" .. close .. "]") do
        depth = depth + (char == open and 1 or -1)
        if depth < 0 then
            return false
        end
    end
    return depth == 0
end

-- Returns { actions = n, abilities = { { name = "Explode", id = 282 }, ... }, errors = { "Line 3: ..." } }.
-- id is nil when the script names an ability without its ID.
function Script.Parse(text)
    local result = { actions = 0, abilities = {}, errors = {} }
    local seenAbilities = {}
    local ifDepth = 0
    local lineNumber = 0

    local function AddError(message)
        result.errors[#result.errors + 1] = format(L["Line %d: %s"], lineNumber, message)
    end

    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        lineNumber = lineNumber + 1
        line = strtrim((line:gsub("%-%-.*$", "")))

        if line == "" then
            -- Blank or comment-only line.
        elseif not IsBalanced(line, "(", ")") or not IsBalanced(line, "[", "]") then
            AddError(L["unbalanced brackets"])
        elseif line:match("^if[%s%[]") then
            ifDepth = ifDepth + 1
        elseif line == "else" then
            if ifDepth == 0 then
                AddError(L["'else' without 'if'"])
            end
        elseif line == "endif" then
            if ifDepth == 0 then
                AddError(L["'endif' without 'if'"])
            else
                ifDepth = ifDepth - 1
            end
        else
            local command = (line:match("^(%a+)") or ""):lower()
            if not COMMANDS[command] then
                AddError(format(L["unknown command '%s'"], line:match("^(%S+)") or line))
            else
                result.actions = result.actions + 1
                if command == "use" or command == "ability" then
                    local argument = line:match("^%a+%s*%((.-)%)")
                    local name, id = (argument or ""):match("^(.-):(%d+)$")
                    name = name or argument
                    id = id or (name and name:match("^%d+$"))
                    if not name or name == "" then
                        AddError(L["missing ability"])
                    elseif name:match("^#%d+$") then
                        -- use(#2): the active pet's second ability, whatever it is.
                    elseif not seenAbilities[id or name] then
                        seenAbilities[id or name] = true
                        result.abilities[#result.abilities + 1] = { name = name, id = tonumber(id) }
                    end
                end
            end
        end
    end

    if ifDepth > 0 then
        lineNumber = lineNumber + 1
        AddError(L["missing 'endif'"])
    end
    return result
end

-- tdBattlePetScript's script engine, when it's installed. Its parser knows every command and
-- condition, so it decides whether a script is valid; without it, scripts can't run at all.
local function GetDirector()
    local scripts = _G.PetBattleScripts
    return type(scripts) == "table" and scripts:GetModule("Director", true) or nil
end

function Script.CanRun()
    return GetDirector() ~= nil
end

-- Parse results and errors by script text, since team rows are checked on every redraw. Cleared
-- when it grows, e.g. from typing in the editor.
local parseCache, parseCacheSize = {}, 0
local PARSE_CACHE_LIMIT = 200

local function ParseAndValidate(text)
    local director = GetDirector()
    local cached = parseCache[text]
    if cached and cached.checkedByDirector == (director ~= nil) then
        return cached.parsed, cached.errors
    end

    local parsed = Script.Parse(text)
    local errors = parsed.errors
    if director then
        local built, err = director:BuildScript(text)
        errors = built and {} or { tostring(err) }
    end

    if parseCacheSize >= PARSE_CACHE_LIMIT then
        wipe(parseCache)
        parseCacheSize = 0
    end
    parseCache[text] = { parsed = parsed, errors = errors, checkedByDirector = director ~= nil }
    parseCacheSize = parseCacheSize + 1
    return parsed, errors
end

-- Like tdBattlePetScript: by ID when the script gives one, otherwise by name in the game's language.
local function IsAbility(ability, abilityID)
    if ability.id then
        return ability.id == abilityID
    end
    return ability.name == ns.GetAbilityInfo(abilityID)
end

-- Where a species can pick the ability: abilitySlot (1-3), abilityID; nil if it can't learn it.
local function FindAbilitySlot(speciesID, ability)
    for position, abilityID in ipairs(ns.GetSpeciesAbilities(speciesID).ids) do
        if IsAbility(ability, abilityID) then
            return (position - 1) % 3 + 1, abilityID
        end
    end
end

-- Checks the abilities the script uses against the team. Each must be one a team pet's species
-- can learn, picked in its slot or left open ("any" in imports, or "keep current"). Random and
-- leveling slots don't count: scripts don't rely on those pets' abilities.
-- Returns warnings, fixes: fixes = { { slot, abilitySlot, abilityID } } select abilities a pet
-- can learn but doesn't have picked, unless the script needs what's picked there now.
local function CheckAbilities(abilities, pets)
    local warnings, fixes = {}, {}
    local needed = {} -- [slot] = { [abilitySlot] = true }, picks the script already relies on
    local missing = {}
    for _, ability in ipairs(abilities) do
        local found, fix = false, nil
        for slot = 1, #pets do
            local entry = pets[slot]
            local abilitySlot, abilityID
            if entry.speciesID then
                abilitySlot, abilityID = FindAbilitySlot(entry.speciesID, ability)
            end
            if abilitySlot then
                local selected = entry.abilities and entry.abilities[abilitySlot]
                if not selected or IsAbility(ability, selected) then
                    found = true
                    needed[slot] = needed[slot] or {}
                    needed[slot][abilitySlot] = true
                    break
                end
                fix = fix or { slot = slot, abilitySlot = abilitySlot, abilityID = abilityID }
            end
        end
        if not found then
            missing[#missing + 1] = { ability = ability, fix = fix }
        end
    end

    for _, entry in ipairs(missing) do
        local ability, fix = entry.ability, entry.fix
        local name = ability.id and GetAbilityName(ability.id) or ability.name
        if fix then
            local _, petName = ns.Teams.GetSlotDisplay(pets[fix.slot])
            warnings[#warnings + 1] = format(L["%s isn't selected on %s (slot %d)."], name, petName, fix.slot)
            local taken = needed[fix.slot] and needed[fix.slot][fix.abilitySlot]
            if not taken then
                needed[fix.slot] = needed[fix.slot] or {}
                needed[fix.slot][fix.abilitySlot] = true
                fixes[#fixes + 1] = fix
            end
        else
            warnings[#warnings + 1] = format(ability.id and L["No pet in this team has %s."]
                or L["No pet in this team has an ability named \"%s\"."], name)
        end
    end
    return warnings, fixes
end

-- Picks the abilities from Check's fixes in the given pets (a team or a draft).
function Script.ApplyFixes(pets, fixes)
    for _, fix in ipairs(fixes) do
        local entry = pets[fix.slot]
        entry.abilities = entry.abilities or {}
        entry.abilities[fix.abilitySlot] = fix.abilityID
    end
end

local STATUS_COLORS = {
    none = GRAY_FONT_COLOR,
    error = RED_FONT_COLOR,
    warning = ORANGE_FONT_COLOR,
    -- The Dragonkin family's green rather than Blizzard's, which is kept for "this is your target".
    ok = ns.GetFamilyColor(2),
}

-- The state of a script: { level = "none" | "error" | "warning" | "ok", problems = { "..." },
-- fixes, color, summary }. "warning" means it's valid but won't work as written: the team lacks an
-- ability. pets (optional) are the team's pets, for that ability check and its fixes (see
-- CheckAbilities).
function Script.Check(text, pets)
    local status = { level = "none", problems = {} }
    if text and strtrim(text) ~= "" then
        local parsed, errors = ParseAndValidate(text)
        if #errors > 0 then
            status.level, status.problems = "error", errors
        else
            if pets then
                status.problems, status.fixes = CheckAbilities(parsed.abilities, pets)
            end
            status.level = #status.problems > 0 and "warning" or "ok"
            status.summary = format(L["%d actions, %d abilities"], parsed.actions, #parsed.abilities)
        end
    end

    local problems = status.problems
    if status.level == "none" then
        status.summary = L["No script"]
    elseif #problems > 0 then
        status.summary = problems[1] .. (#problems > 1 and format(L[" (+%d more)"], #problems - 1) or "")
    end
    status.color = STATUS_COLORS[status.level]
    return status
end

-- True for a script that's ready but can't run, because tdBattlePetScript isn't installed: shown
-- muted then, rather than looking ready.
function Script.IsReadyButIdle(status)
    return status.level == "ok" and not Script.CanRun()
end

-- Badge text and colour for a checked script: readyText (translated) when it's fine, what's wrong
-- otherwise, coloured like its status; plain "Script" muted while it can't run (IsReadyButIdle).
local PROBLEM_BADGES = {
    warning = "Script · check abilities",
    error = "Script · error",
}

function Script.GetBadge(status, readyText)
    if Script.IsReadyButIdle(status) then
        return L["Script"], ns.MUTED_COLOR
    end
    local problem = PROBLEM_BADGES[status.level]
    return problem and L[problem] or readyText, status.color
end

-- Tooltip lines for a checked script: every problem (or the summary), and a note when scripts
-- can't run because tdBattlePetScript is missing.
function Script.AddCheckToTooltip(tooltip, status)
    if #status.problems > 0 then
        for _, problem in ipairs(status.problems) do
            tooltip:AddLine(problem, status.color.r, status.color.g, status.color.b, true)
        end
    else
        tooltip:AddLine(status.summary, status.color:GetRGB())
    end
    if status.level ~= "none" and not Script.CanRun() then
        tooltip:AddLine(L["Install Pet Battle Scripts (tdBattlePetScript) to run scripts in battle."], 0.6, 0.6, 0.6, true)
    end
end

-- One-line summary for the UI: summary, color.
function Script.Describe(text, pets)
    local status = Script.Check(text, pets)
    return status.summary, status.color
end
