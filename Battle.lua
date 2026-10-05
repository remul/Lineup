local _, ns = ...

function ns:OnEnable()
    self:RegisterEvent("PET_BATTLE_OPENING_START")
    self:RegisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE")
    self:RegisterEvent("PET_BATTLE_CLOSE")
end

function ns:PET_BATTLE_OPENING_START()
    local isWild = C_PetBattles.IsWildBattle()
    self:Debug("Battle started", isWild and "(wild)" or "")
end

function ns:PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE(round)
    local owner = Enum.BattlePetOwner.Ally
    local index = C_PetBattles.GetActivePet(owner)
    local health = C_PetBattles.GetHealth(owner, index)
    local maxHealth = C_PetBattles.GetMaxHealth(owner, index)
    self:Debug("Round", round, "active pet", index, health .. "/" .. maxHealth)
end

-- Fires twice per battle; IsInBattle() is false on the second call.
function ns:PET_BATTLE_CLOSE()
    if C_PetBattles.IsInBattle() then
        return
    end
    self:Debug("Battle ended")
end
