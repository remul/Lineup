local _, ns = ...
local L = ns.L

-- Tracks the targeted NPC so teams made for it can be suggested.
local Target = {}
ns.Target = Target

-- Returns npcID, name for an NPC unit, or nil.
function Target.GetNpc(unit)
    local guid = UnitGUID(unit)
    if not guid or (issecretvalue and issecretvalue(guid)) then
        return nil
    end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then
        return nil
    end
    return tonumber(npcID), UnitName(unit)
end

-- True if Rematch is set to replace the Pet Journal: then it hides Blizzard's journal (and Lineup,
-- which is part of it), so Lineup stays quiet.
local function IsRematchInJournal()
    local rematch = _G.Rematch
    return type(rematch) == "table" and type(rematch.settings) == "table" and rematch.settings.UseDefaultJournal == false
end

function Target:IsCurrent(npcID)
    return npcID ~= nil and npcID == self.npcID
end

function ns:PLAYER_TARGET_CHANGED()
    local npcID, name = Target.GetNpc("target")
    if npcID == Target.npcID then
        return
    end
    Target.npcID, Target.name = npcID, name

    local teams = ns.Teams:GetForTarget(npcID)
    if #teams > 0 then
        local names = {}
        for i, team in ipairs(teams) do
            names[i] = team.name
            ns.Teams:SetCollapsed(team.groupID, false)
        end
        if not C_PetBattles.IsInBattle() and not IsRematchInJournal() then
            ns:Print(format(L["Teams for %s: %s"], name or L["this target"], table.concat(names, ", ")))
        end
    end
    ns.TeamsPanel:Refresh()
end

ns:RegisterEvent("PLAYER_TARGET_CHANGED")
