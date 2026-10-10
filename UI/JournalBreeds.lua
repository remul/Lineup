local _, ns = ...

-- A breed badge (see ns.CreateBadge) below the pet's name, next to its icon, in the Pet Journal:
-- on the list's buttons and on the loadout's three slots, for battle pets whose breed is known
-- ("P/S", or "P/S or S/S" at low levels). Blizzard redraws them in PetJournal_InitPetButton and
-- PetJournal_UpdatePetLoadOut; the badges are updated right after.
local JournalBreeds = {}
ns.JournalBreeds = JournalBreeds

local BADGE_GAP = 4
-- Extra room between the name and the badge, so the badge doesn't touch the name's letters.
local BADGE_TOP_GAP = 2

-- Layout of Blizzard's name and sub name (the species, below a custom name) on list buttons and
-- loadout slots: the sub name's gap below the name and its width, and the name's height when it
-- shares its line with a sub name.
local LIST_LAYOUT = { subNameGap = -4, subNameWidth = 147, nameHeight = 12 }
local LOADOUT_LAYOUT = { subNameGap = -2, subNameWidth = 215, nameHeight = 12 }

-- "P/S" for a pet, or nil when it has no badge (unknown, or too many breeds fit at a low level).
local function GetBreedText(petID)
    local breed = petID and ns.Breeds.DescribePet(petID)
    return breed ~= "?" and breed or nil
end

-- Shows breed in a badge below frame's name (nil hides it), moving Blizzard's sub name to the
-- badge's right. Blizzard sets the name's height on each redraw but anchors the sub name only
-- once, so it's put back here when there's no badge.
local function UpdateBadge(frame, layout, breed, customName)
    local badge = frame.LineupPetBattlesBreedBadge
    if not badge then
        if not breed then
            return
        end
        badge = ns.CreateBadge(frame)
        badge:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, layout.subNameGap - BADGE_TOP_GAP)
        frame.LineupPetBattlesBreedBadge = badge
    end
    badge:SetText(breed)

    local subName = frame.subName
    subName:ClearAllPoints()
    if breed then
        -- Without a custom name the name is centered in a taller line; move it up like a custom
        -- name, so the badge fits below it.
        if not customName then
            frame.name:SetHeight(layout.nameHeight)
        end
        subName:SetPoint("LEFT", badge, "RIGHT", BADGE_GAP, 0)
        subName:SetWidth(layout.subNameWidth - badge:GetWidth() - BADGE_GAP)
    else
        subName:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, layout.subNameGap)
        subName:SetWidth(layout.subNameWidth)
    end
end

local function UpdateListButton(button, elementData)
    local petID, _, isOwned, customName, _, _, _, _, _, _, _, _, _, _, canBattle =
        C_PetJournal.GetPetInfoByIndex(elementData.index)
    UpdateBadge(button, LIST_LAYOUT, isOwned and canBattle and GetBreedText(petID) or nil, customName)
end

local function UpdateLoadout()
    for slot = 1, 3 do
        local plate = PetJournal.Loadout and PetJournal.Loadout["Pet" .. slot]
        if plate then
            local petID = C_PetJournal.GetPetLoadOutInfo(slot)
            local customName = petID and select(2, C_PetJournal.GetPetInfoByPetID(petID))
            -- Locked or empty slots hide the name; no badge then either.
            local breed = plate.name:IsShown() and GetBreedText(petID) or nil
            UpdateBadge(plate, LOADOUT_LAYOUT, breed, customName)
        end
    end
end

-- Called once the Pet Journal exists.
function JournalBreeds:Setup()
    if PetJournal_InitPetButton then
        hooksecurefunc("PetJournal_InitPetButton", UpdateListButton)
    end
    if PetJournal_UpdatePetLoadOut then
        hooksecurefunc("PetJournal_UpdatePetLoadOut", UpdateLoadout)
    end
end
