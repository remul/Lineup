local _, ns = ...

-- A row of family icons above the Pet Journal list. It drives Blizzard's own family filter,
-- so it stays in sync with the journal's filter dropdown.
local FamilyFilter = {}
ns.FamilyFilter = FamilyFilter

local BUTTON_SIZE = 20
local BUTTON_SPACING = 4
local BAR_HEIGHT = BUTTON_SIZE + 8

local buttons = {}

local function AllTypesChecked()
    for petType = 1, C_PetJournal.GetNumPetTypes() do
        if not C_PetJournal.IsPetTypeChecked(petType) then
            return false
        end
    end
    return true
end

local function NoTypeChecked()
    for petType = 1, C_PetJournal.GetNumPetTypes() do
        if C_PetJournal.IsPetTypeChecked(petType) then
            return false
        end
    end
    return true
end

-- Left-click on an unfiltered list shows only that family; further clicks add or remove families.
-- Right-click clears the family filter.
local function Button_OnClick(button, mouseButton)
    if mouseButton == "RightButton" then
        C_PetJournal.SetAllPetTypesChecked(true)
    elseif AllTypesChecked() then
        C_PetJournal.SetAllPetTypesChecked(false)
        C_PetJournal.SetPetTypeFilter(button.petType, true)
    else
        C_PetJournal.SetPetTypeFilter(button.petType, not C_PetJournal.IsPetTypeChecked(button.petType))
        if NoTypeChecked() then
            C_PetJournal.SetAllPetTypesChecked(true)
        end
    end
    FamilyFilter:Refresh()
end

local function Button_OnEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(ns.GetFamilyName(button.petType))
    GameTooltip:AddLine("Click to filter by this family.", 1, 1, 1)
    GameTooltip:AddLine("Right-click to show all families.", 1, 1, 1)
    GameTooltip:Show()
end

-- Shift every top anchor of a region down to free up space above it.
local function MoveTopDown(region, offset, onlyUnlessRelativeTo)
    local points = {}
    for i = 1, region:GetNumPoints() do
        points[i] = { region:GetPoint(i) }
    end
    for _, p in ipairs(points) do
        local point, relativeTo, relativePoint, x, y = unpack(p)
        if point:find("TOP") and relativeTo ~= onlyUnlessRelativeTo then
            region:SetPoint(point, relativeTo, relativePoint, x, y - offset)
        end
    end
end

function FamilyFilter:Setup()
    local scrollBox = PetJournal.ScrollBox
    if not scrollBox then
        ns:Print("Couldn't find the Pet Journal list; the family filter is disabled.")
        return
    end

    MoveTopDown(scrollBox, BAR_HEIGHT)
    if PetJournal.ScrollBar then
        MoveTopDown(PetJournal.ScrollBar, BAR_HEIGHT, scrollBox)
    end

    local bar = CreateFrame("Frame", nil, PetJournal)
    bar:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    bar:SetPoint("BOTTOMLEFT", scrollBox, "TOPLEFT", 4, 4)

    for petType = 1, ns.NUM_FAMILIES do
        local button = CreateFrame("Button", nil, bar)
        button.petType = petType
        button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        button:SetPoint("LEFT", (petType - 1) * (BUTTON_SIZE + BUTTON_SPACING), 0)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        button.Icon = button:CreateTexture(nil, "ARTWORK")
        button.Icon:SetAllPoints()
        button.Icon:SetTexture(ns.GetFamilyIcon(petType))

        button.Selected = button:CreateTexture(nil, "OVERLAY")
        button.Selected:SetPoint("TOPLEFT", -3, 3)
        button.Selected:SetPoint("BOTTOMRIGHT", 3, -3)
        button.Selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        button.Selected:SetBlendMode("ADD")

        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:SetScript("OnClick", Button_OnClick)
        button:SetScript("OnEnter", Button_OnEnter)
        button:SetScript("OnLeave", GameTooltip_Hide)
        buttons[petType] = button
    end

    PetJournal:HookScript("OnShow", function()
        FamilyFilter:Refresh()
    end)
    self:Refresh()
end

function FamilyFilter:Refresh()
    local all = AllTypesChecked()
    for petType, button in ipairs(buttons) do
        local checked = C_PetJournal.IsPetTypeChecked(petType)
        button.Selected:SetShown(not all and checked)
        button.Icon:SetDesaturated(not all and not checked)
        button.Icon:SetAlpha((all or checked) and 1 or 0.5)
    end
end
