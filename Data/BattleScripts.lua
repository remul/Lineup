local addonName, ns = ...
local L = ns.L

-- Runs team scripts through tdBattlePetScript (Pet Battle Scripts), if it's installed. It owns the
-- in-battle "Auto" button; each press runs the first line of the script that can act. Lineup
-- registers as one of its plugins: at the start of a battle, it asks every plugin for the current
-- key and the script for that key. Our key is the loaded team itself, and the script text stays in
-- team.script, so there's one copy; saves from tdBattlePetScript's own editor are written back to
-- the team.
local PLUGIN_NAME = "Lineup"

local function Register(PetBattleScripts)
    local Teams = ns.Teams
    local Plugin = PetBattleScripts:NewPlugin(PLUGIN_NAME)
    local PluginManager = PetBattleScripts:GetModule("PluginManager")
    local ScriptClass = PetBattleScripts:GetClass("Script")

    -- One Script object per team, rebuilt when the team's name or script changes.
    local cache = setmetatable({}, { __mode = "k" })

    local function IsTeam(key)
        return type(key) == "table" and tContains(Teams:GetAll(), key)
    end

    function Plugin:OnInitialize()
        self:SetPluginTitle(ns.TITLE)
        self:SetPluginNotes(L["Scripts of the team loaded with Lineup."])
        self:SetPluginIcon(ns.MEDIA .. "Icon")
        -- Read by tdBattlePetScript when the plugin is switched on in its options.
        self.requiredAddon = addonName
        if not PluginManager:IsPluginAllowed(PLUGIN_NAME) then
            self:SetEnabledState(false)
        end

        -- tdBattlePetScript only orders its own plugins. Put ours first: loading a Lineup team
        -- unloads Rematch's, so their keys never compete. Later moves in its options are kept.
        local orders = PetBattleScripts.db.profile.pluginOrders
        if not tContains(orders, PLUGIN_NAME) then
            tinsert(orders, 1, PLUGIN_NAME)
        end
        PluginManager:RebuildPluginOrders()
    end

    -- The loaded team, while the journal still holds its pets and abilities (otherwise the script
    -- would steer the wrong pets, so the next plugin gets a turn).
    function Plugin:GetCurrentKey()
        local team = Teams:GetLoadedTeam()
        if team and not Teams:HasChanges(team) then
            return team
        end
    end

    function Plugin:GetTitleByKey(team)
        return team.name
    end

    function Plugin:IterateKeys()
        local teams = Teams:GetAll()
        local index = 0
        return function()
            index = index + 1
            return teams[index]
        end
    end

    -- nil for a script that doesn't build: Lineup only checks a script's shape, and running a broken
    -- one raises an error on every press of the Auto button. Without it, the next plugin gets a turn.
    function Plugin:GetScript(team)
        if type(team) ~= "table" or not team.script then
            return nil
        end
        local cached = cache[team]
        if not cached or cached.script:GetCode() ~= team.script or cached.script:GetName() ~= team.name then
            local script = ScriptClass:New({ name = team.name, code = team.script }, self, team)
            cached = { script = script, valid = script:GetScript() ~= nil }
            cache[team] = cached
        end
        return cached.valid and cached.script or nil
    end

    function Plugin:IterateScripts()
        local scripts = {}
        for _, team in ipairs(Teams:GetAll()) do
            scripts[team] = self:GetScript(team)
        end
        return pairs(scripts)
    end

    -- From tdBattlePetScript's editor and import.
    function Plugin:AddScript(team, script)
        if IsTeam(team) then
            team.script = script:GetCode()
            cache[team] = nil
            PetBattleScripts:SendMessage("PET_BATTLE_SCRIPT_SCRIPT_LIST_UPDATE")
        end
    end

    function Plugin:RemoveScript(team)
        if IsTeam(team) then
            team.script = nil
            cache[team] = nil
            PetBattleScripts:SendMessage("PET_BATTLE_SCRIPT_SCRIPT_LIST_UPDATE")
        end
    end

    function Plugin:OnTooltipFormatting(tip, team)
        tip:AddLine(team.name, GREEN_FONT_COLOR:GetRGB())
        for slot = 1, #team.pets do
            local icon, name = Teams.GetSlotDisplay(team.pets[slot])
            if icon then
                tip:AddLine(format("|T%s:20|t %s", icon, name), 1, 1, 1)
            end
        end
    end
end

-- tdBattlePetScript normally loads first (OptionalDeps), and then this runs right away; with an
-- addon loader it can come later.
EventUtil.ContinueOnAddOnLoaded("tdBattlePetScript", function()
    if type(_G.PetBattleScripts) == "table" then
        Register(_G.PetBattleScripts)
    end
end)
