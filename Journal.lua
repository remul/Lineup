local _, ns = ...

-- Blizzard's Pet Journal lives in the load-on-demand Blizzard_Collections addon.
EventUtil.ContinueOnAddOnLoaded("Blizzard_Collections", function()
    ns.FamilyFilter:Setup()
    ns.PetToolbar:Setup()
    ns.TargetPanel:Setup()
    ns.TeamsPanel:Setup()
    ns:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
end)

function ns:PET_JOURNAL_LIST_UPDATE()
    -- Our own pet scans change the journal filters, which fires this event too.
    if self.Roster:IsScanning() then
        return
    end
    self.FamilyFilter:Refresh()
    self.TeamsPanel:Refresh()
end

function ns:ToggleJournal()
    ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_PETS or 2)
end

-- Global so the TOC's AddonCompartmentFunc can find it.
_G.Lineup_OnAddonCompartmentClick = function()
    ns:ToggleJournal()
end
