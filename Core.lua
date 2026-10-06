local addonName, ns = ...
local L = ns.L

-- The display name. The folder (addonName) is "Lineup_PetBattles", since "Lineup" is taken on CurseForge.
ns.TITLE = "Lineup"
-- Path to the addon's own textures, e.g. ns.MEDIA .. "Icon".
ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

-- Defaults are copied into the saved variables on first load and whenever new keys are added.
local DEFAULTS = {
    debug = false,
    teams = {},
    groups = {},
    nextGroupID = 1,
    ungroupedCollapsed = false,
    queueSort = "levelDesc",
    queueIncludeDuplicates = false,
    queueIncludeMaxedSpecies = false,
}

local CHAR_DEFAULTS = {}

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = type(value) == "table" and CopyTable(value) or value
        elseif type(value) == "table" and type(target[key]) == "table" then
            ApplyDefaults(target[key], value)
        end
    end
end

function ns:Print(...)
    print("|cff33ff99" .. ns.TITLE .. "|r:", ...)
end

function ns:Debug(...)
    if self.db and self.db.debug then
        self:Print("|cff888888[debug]|r", ...)
    end
end

-- Pet families, indexed by pet type.
local FAMILY_SUFFIX = {
    "Humanoid", "Dragon", "Flying", "Undead", "Critter",
    "Magical", "Elemental", "Beast", "Water", "Mechanical",
}
ns.NUM_FAMILIES = #FAMILY_SUFFIX

function ns.GetFamilyIcon(petType)
    return "Interface\\Icons\\Icon_PetFamily_" .. FAMILY_SUFFIX[petType]
end

function ns.GetFamilyName(petType)
    return _G["BATTLE_PET_NAME_" .. petType]
end

-- Colours matching the family icons, for family tags.
local FAMILY_COLORS = {
    CreateColor(0.31, 0.69, 1.00), -- Humanoid
    CreateColor(0.45, 0.85, 0.35), -- Dragonkin
    CreateColor(1.00, 0.85, 0.30), -- Flying
    CreateColor(0.72, 0.58, 0.82), -- Undead
    CreateColor(0.82, 0.62, 0.42), -- Critter
    CreateColor(0.78, 0.48, 1.00), -- Magic
    CreateColor(1.00, 0.55, 0.20), -- Elemental
    CreateColor(1.00, 0.38, 0.32), -- Beast
    CreateColor(0.30, 0.85, 0.90), -- Aquatic
    CreateColor(0.75, 0.75, 0.75), -- Mechanical
}

function ns.GetFamilyColor(petType)
    return FAMILY_COLORS[petType]
end

-- English family names, as used in team names from Xu-Fu's Pet Guides on any client language.
local ENGLISH_FAMILY_NAMES = {
    "Humanoid", "Dragonkin", "Flying", "Undead", "Critter",
    "Magic", "Elemental", "Beast", "Aquatic", "Mechanical",
}

-- Pet type for a family name (English or the client's language), or nil.
function ns.FindFamilyByName(name)
    name = name:lower()
    for petType = 1, ns.NUM_FAMILIES do
        if name == ENGLISH_FAMILY_NAMES[petType]:lower() or name == ns.GetFamilyName(petType):lower() then
            return petType
        end
    end
end

-- Inline icons for pets that can't fight well: dead (skull) and hurt (warning sign).
ns.DEAD_ICON = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14:14|t"
ns.HURT_ICON = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14:14|t"

-- r, g, b for a battle pet quality (1 = poor ... 4 = rare).
function ns.GetRarityColor(rarity)
    local color = ITEM_QUALITY_COLORS[(rarity or 1) - 1]
    if color then
        return color.r, color.g, color.b
    end
    return NORMAL_FONT_COLOR:GetRGB()
end

-- Returns speciesName, icon for a speciesID, or nil if the species doesn't exist.
-- (For an invalid speciesID the API returns the function itself instead of nil.)
function ns.GetSpeciesInfo(speciesID)
    local name, icon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    if type(name) ~= "string" then
        return nil
    end
    return name, icon
end

-- Event dispatch: ns:RegisterEvent("EVENT_NAME", callback) calls callback(...) when it fires.
-- Without a callback, ns:EVENT_NAME(...) is called. An event can have several callbacks.
local frame = CreateFrame("Frame")
-- [event] = { { key = callback or METHOD, run = function(...) } }. Lists are replaced, not changed
-- in place, so a callback can unregister itself while the event is being dispatched.
local callbacks = {}
local METHOD = {} -- key for the ns:EVENT_NAME handler

frame:SetScript("OnEvent", function(_, event, ...)
    local list = callbacks[event]
    if list then
        for _, entry in ipairs(list) do
            entry.run(...)
        end
    end
end)

local function AddCallback(event, callback)
    local list = CopyTable(callbacks[event] or {}, true)
    tinsert(list, {
        key = callback or METHOD,
        run = callback or function(...)
            -- Calls the ns:EVENT_NAME handler; the IDE can't tell which method that is.
            ---@diagnostic disable-next-line: param-type-mismatch
            ns[event](ns, ...)
        end,
    })
    callbacks[event] = list
end

function ns:RegisterEvent(event, callback)
    AddCallback(event, callback)
    frame:RegisterEvent(event)
end

-- Like RegisterEvent, but only for one unit (e.g. UNIT_AURA for "player"), so the game doesn't
-- deliver the event for every unit around. Only use it for events no one listens to for all units.
function ns:RegisterUnitEvent(event, unit, callback)
    AddCallback(event, callback)
    frame:RegisterUnitEvent(event, unit)
end

-- Removes the callback given to RegisterEvent (without one: the ns:EVENT_NAME handler). Other
-- callbacks for the event keep running.
function ns:UnregisterEvent(event, callback)
    local key = callback or METHOD
    local list = {}
    for _, entry in ipairs(callbacks[event] or {}) do
        if entry.key ~= key then
            list[#list + 1] = entry
        end
    end
    if #list > 0 then
        callbacks[event] = list
    else
        callbacks[event] = nil
        frame:UnregisterEvent(event)
    end
end

-- Lifecycle
function ns:ADDON_LOADED(loadedName)
    if loadedName ~= addonName then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")

    LineupDB = LineupDB or {}
    LineupCharDB = LineupCharDB or {}
    ApplyDefaults(LineupDB, DEFAULTS)
    ApplyDefaults(LineupCharDB, CHAR_DEFAULTS)
    self.db = LineupDB
    self.charDb = LineupCharDB
end

ns:RegisterEvent("ADDON_LOADED")

-- Slash commands
SLASH_LINEUP1 = "/lineup"

SlashCmdList.LINEUP = function(msg)
    local cmd = strtrim(msg or ""):lower()

    if cmd == "" then
        ns:ToggleJournal()
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns:Print(L["Debug"], ns.db.debug and L["enabled"] or L["disabled"])
        ns.TeamsPanel:Refresh() -- keeps the setting's checkbox on the Settings tab in sync
    else
        ns:Print(L["Commands:"])
        print(L["  /lineup - open the Pet Journal"])
        print(L["  /lineup debug - toggle debug output"])
    end
end
