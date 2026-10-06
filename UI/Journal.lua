local _, ns = ...

-- Blizzard's Pet Journal lives in the load-on-demand Blizzard_Collections addon.
EventUtil.ContinueOnAddOnLoaded("Blizzard_Collections", function()
    -- Pets can change outside battles (battle-training stones, trading), so re-read them on open.
    PetJournal:HookScript("OnShow", function()
        ns.LevelingQueue:Invalidate()
    end)
    ns.FamilyFilter:Setup()
    ns.PetToolbar:Setup()
    ns.TargetPanel:Setup()
    ns.TeamsPanel:Setup()
    ns:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
end)

-- Pets or abilities changed in the journal (by anyone): the loaded team may now show "changed".
for _, name in ipairs({ "SetAbility", "SetPetLoadOutInfo" }) do
    hooksecurefunc(C_PetJournal, name, function()
        ns.TeamsPanel:Refresh()
    end)
end

function ns:PET_JOURNAL_LIST_UPDATE()
    -- Our own pet scans change the journal filters, which fires this event too.
    if self.Roster:IsScanning() then
        return
    end
    self.FamilyFilter:Refresh()
    self.TeamsPanel:Refresh()
end

local function IsInJournalList(petID)
    for i = 1, C_PetJournal.GetNumPets() do
        if C_PetJournal.GetPetInfoByIndex(i) == petID then
            return true
        end
    end
    return false
end

-- Selects a pet in Blizzard's Pet Journal list (scrolling to it and showing its pet card). If the
-- journal's search or filters hide the pet, they're cleared first so it can be found.
function ns:SelectPetInJournal(petID)
    if not PetJournal_SelectPet then
        return
    end
    if IsInJournalList(petID) then
        PetJournal_SelectPet(PetJournal, petID)
        return
    end
    local searchBox = PetJournal.searchBox or _G.PetJournalSearchBox
    if searchBox then
        searchBox:SetText("")
    end
    C_PetJournal.ClearSearchFilter()
    C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, true)
    C_PetJournal.SetAllPetTypesChecked(true)
    C_PetJournal.SetAllPetSourcesChecked(true)
    -- The journal rebuilds its list after the filter change; select once that's done.
    C_Timer.After(0, function()
        PetJournal_SelectPet(PetJournal, petID)
    end)
end

function ns:ToggleJournal()
    ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_PETS or 2)
end

-- Global so the TOC's AddonCompartmentFunc can find it.
_G.Lineup_OnAddonCompartmentClick = function()
    ns:ToggleJournal()
end
