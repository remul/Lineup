local _, ns = ...

-- Light validation of tdBattlePetScript text, e.g.
--   use(Explode:282) [enemy.hp<619]
--   change(next)
-- This only checks the structure so imports can be sanity-checked; running scripts comes later.
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

-- Returns { actions = n, abilities = { "Explode", ... }, errors = { "Line 3: ..." } }.
function Script.Parse(text)
    local result = { actions = 0, abilities = {}, errors = {} }
    local seenAbilities = {}
    local ifDepth = 0
    local lineNumber = 0

    local function AddError(message)
        result.errors[#result.errors + 1] = format("Line %d: %s", lineNumber, message)
    end

    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        lineNumber = lineNumber + 1
        line = strtrim((line:gsub("%-%-.*$", "")))

        if line == "" then
            -- Blank or comment-only line.
        elseif not IsBalanced(line, "(", ")") or not IsBalanced(line, "[", "]") then
            AddError("unbalanced brackets")
        elseif line:match("^if[%s%[]") then
            ifDepth = ifDepth + 1
        elseif line == "else" then
            if ifDepth == 0 then
                AddError("'else' without 'if'")
            end
        elseif line == "endif" then
            if ifDepth == 0 then
                AddError("'endif' without 'if'")
            else
                ifDepth = ifDepth - 1
            end
        else
            local command = (line:match("^(%a+)") or ""):lower()
            if not COMMANDS[command] then
                AddError(format("unknown command '%s'", line:match("^(%S+)") or line))
            else
                result.actions = result.actions + 1
                if command == "use" or command == "ability" then
                    local argument = line:match("^%a+%s*%((.-)%)")
                    local name = argument and (argument:match("^(.-):%d+$") or argument)
                    if not name or name == "" then
                        AddError("missing ability")
                    elseif not seenAbilities[name] then
                        seenAbilities[name] = true
                        result.abilities[#result.abilities + 1] = name
                    end
                end
            end
        end
    end

    if ifDepth > 0 then
        lineNumber = lineNumber + 1
        AddError("missing 'endif'")
    end
    return result
end

-- One-line summary for the UI.
function Script.Describe(text)
    if not text or strtrim(text) == "" then
        return "No script", GRAY_FONT_COLOR
    end
    local result = Script.Parse(text)
    if #result.errors > 0 then
        return result.errors[1] .. (#result.errors > 1 and format(" (+%d more)", #result.errors - 1) or ""), RED_FONT_COLOR
    end
    return format("%d actions, %d abilities", result.actions, #result.abilities), GREEN_FONT_COLOR
end
