local addonName, ns = ...
local L = ns.L

-- The display name. The folder (addonName) is "Lineup_PetBattles", since "Lineup" is taken on CurseForge.
ns.TITLE = "Lineup"
-- Path to the addon's own textures, e.g. ns.MEDIA .. "Icon".
ns.MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

-- Defaults are copied into the saved variables on first load and whenever new keys are added.
local DEFAULTS = {
    debug = false,
    autoLoadTargetTeam = false,
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

-- The pet battle type chart, by family index (1 Humanoid, 2 Dragonkin, 3 Flying, 4 Undead,
-- 5 Critter, 6 Magic, 7 Elemental, 8 Beast, 9 Aquatic, 10 Mechanical): abilities of a family deal
-- 50% more damage to STRONG_AGAINST[family] and a third less to WEAK_AGAINST[family].
ns.STRONG_AGAINST = { 2, 6, 9, 1, 4, 3, 10, 5, 7, 8 }
ns.WEAK_AGAINST = { 8, 4, 2, 9, 1, 10, 5, 3, 6, 7 }

-- English family names, as used in team names from Xu-Fu's Pet Guides on any client language.
local ENGLISH_FAMILY_NAMES = {
    "Humanoid", "Dragonkin", "Flying", "Undead", "Critter",
    "Magic", "Elemental", "Beast", "Aquatic", "Mechanical",
}

-- [lowercase family name, English and the client's language] = pet type; built on first use.
local familiesByName

-- Pet type for a family name (English or the client's language), or nil.
function ns.FindFamilyByName(name)
    if not familiesByName then
        familiesByName = {}
        for petType = 1, ns.NUM_FAMILIES do
            familiesByName[ENGLISH_FAMILY_NAMES[petType]:lower()] = petType
            familiesByName[ns.GetFamilyName(petType):lower()] = petType
        end
    end
    return familiesByName[name:lower()]
end

-- A species' abilities: { ids = { six abilityIDs }, levels = { level each unlocks at },
-- names = { lowercase names }, types = { family of each }, strongAgainst = { [family] = true } }.
-- In the journal's order: ability slot n picks ids[n] or ids[n + 3]. Fixed game data, so it's
-- kept; don't change the tables.
local abilitiesBySpecies = {}

function ns.GetSpeciesAbilities(speciesID)
    local abilities = abilitiesBySpecies[speciesID]
    if not abilities then
        local ids, levels = C_PetJournal.GetPetAbilityList(speciesID)
        abilities = { ids = ids or {}, levels = levels or {}, names = {}, types = {}, strongAgainst = {} }
        for index, abilityID in ipairs(abilities.ids) do
            local _, name, _, _, _, _, abilityType = C_PetBattles.GetAbilityInfoByID(abilityID)
            abilities.names[index] = (name or ""):lower()
            abilities.types[index] = abilityType
            if ns.STRONG_AGAINST[abilityType] then
                abilities.strongAgainst[ns.STRONG_AGAINST[abilityType]] = true
            end
        end
        abilitiesBySpecies[speciesID] = abilities
    end
    return abilities
end

-- Inline icons for pets that can't fight well: dead (skull) and hurt (warning sign).
ns.DEAD_ICON = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14:14|t"
ns.HURT_ICON = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14:14|t"

-- Rounded card textures (see tools/generate_rounded_textures.py): white, tinted with
-- SetVertexColor, and drawn as nine-slices so the corners keep their size at any card size.
local ROUNDED_FILL = ns.MEDIA .. "RoundedFill"
local ROUNDED_BORDER = ns.MEDIA .. "RoundedBorder"
local ROUNDED_MARGIN = 10

-- A rounded rectangle filling parent (or, with border, its outline), colored r, g, b, a.
function ns.CreateRoundedTexture(parent, layer, subLevel, r, g, b, a, border)
    local texture = parent:CreateTexture(nil, layer, nil, subLevel)
    texture:SetTexture(border and ROUNDED_BORDER or ROUNDED_FILL)
    texture:SetTextureSliceMargins(ROUNDED_MARGIN, ROUNDED_MARGIN, ROUNDED_MARGIN, ROUNDED_MARGIN)
    texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    texture:SetVertexColor(r, g, b, a)
    texture:SetAllPoints()
    return texture
end

-- The divider line of Blizzard's own Settings panel (thin, fading out at both ends).
local DIVIDER_ATLAS = "Options_HorizontalDivider"
local DIVIDER_INFO = C_Texture.GetAtlasInfo(DIVIDER_ATLAS)

-- Makes texture a divider line, lying or (vertical) upright, and returns its thickness; the caller
-- sets the length. Without the atlas it's a thin gold line.
function ns.SetDividerTexture(texture, vertical)
    if not DIVIDER_INFO then
        texture:SetColorTexture(1, 0.82, 0, 0.5)
        return 1
    end
    if vertical then
        -- The same art turned a quarter (rotating it instead would stretch it): the frame's left
        -- edge runs along the art's length, its top edge across it.
        local info = DIVIDER_INFO
        texture:SetTexture(info.file or info.filename)
        texture:SetTexCoord(info.leftTexCoord, info.topTexCoord, info.rightTexCoord, info.topTexCoord,
            info.leftTexCoord, info.bottomTexCoord, info.rightTexCoord, info.bottomTexCoord)
    else
        texture:SetAtlas(DIVIDER_ATLAS)
    end
    return DIVIDER_INFO.height
end

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
