local _, ns = ...

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
        if not C_PetBattles.IsInBattle() then
            ns:Print(format("Teams for %s: %s", name or "this target", table.concat(names, ", ")))
        end
    end
    ns.TeamsPanel:Refresh()
end

ns:RegisterEvent("PLAYER_TARGET_CHANGED")
