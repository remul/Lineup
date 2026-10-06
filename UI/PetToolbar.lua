local _, ns = ...
local L = ns.L

-- A row of pet utility buttons replacing the Pet Journal's own "Revive Battle Pets" and "Summon
-- Random Favorite Pet" buttons, in the same spot. Spells, items and toys use secure action buttons,
-- whose attributes can only change out of combat; setup and updates wait for combat to end.
local PetToolbar = {}
ns.PetToolbar = PetToolbar

local BUTTON_SIZE = 26
local BUTTON_SPACING = 3
-- Extra gap between groups of buttons.
local GROUP_SPACING = 20
-- Gap between the bar's right edge and the right edge of the journal's content.
local RIGHT_MARGIN = 8

local REVIVE_SPELL_ID = 125439
local BANDAGE_ITEM_ID = 86143
local SAFARI_HAT_ITEM_ID = 92738
local LESSER_PET_TREAT_ITEM_ID = 98112
local PET_TREAT_ITEM_ID = 98114

-- Left to right, in groups: healing, leveling, summoning. The bar ends where Blizzard's buttons were.
local BUTTONS = {
    { key = "revive", group = 1, spellID = REVIVE_SPELL_ID },
    { key = "bandage", group = 1, itemID = BANDAGE_ITEM_ID, showCount = true },
    { key = "safariHat", group = 2, toyID = SAFARI_HAT_ITEM_ID, cancelBuff = true },
    { key = "lesserPetTreat", group = 2, itemID = LESSER_PET_TREAT_ITEM_ID, showCount = true },
    { key = "petTreat", group = 2, itemID = PET_TREAT_ITEM_ID, showCount = true },
    { key = "summon", group = 3, icon = "Interface\\Icons\\INV_Pet_Achievement_CaptureAWildPet",
      title = L["Summon Random Favorite Pet"], hint = L["Right-click to summon a random pet from your whole collection."] },
}

-- x offset of each button from the bar's left edge, x centers of the dividers between groups,
-- and the bar's total width.
local function GetLayout()
    local offsets, dividers, x = {}, {}, 0
    for index, info in ipairs(BUTTONS) do
        if index > 1 then
            local newGroup = info.group ~= BUTTONS[index - 1].group
            local gap = BUTTON_SPACING + (newGroup and GROUP_SPACING or 0)
            if newGroup then
                -- Whole pixels, so every divider renders the same.
                dividers[#dividers + 1] = x + math.floor(gap / 2)
            end
            x = x + gap
        end
        offsets[index] = x
        x = x + BUTTON_SIZE
    end
    return offsets, dividers, x
end

local bar
local buttons = {}
local pendingSetup = false
local HideTextBehindBar
-- Blizzard buttons we've hooked to stay hidden.
local keptHidden = {}

-- Returns the buff's name if the item's buff (e.g. Safari Hat) is on the player.
local function GetItemBuff(itemID)
    local buffName, spellID = C_Item.GetItemSpell(itemID)
    if buffName and spellID and C_UnitAuras.GetPlayerAuraBySpellID(spellID) then
        return buffName
    end
end

local function GetIcon(info)
    if info.icon then
        return info.icon
    elseif info.spellID then
        return C_Spell.GetSpellTexture(info.spellID)
    end
    return C_Item.GetItemIconByID(info.itemID or info.toyID)
end

local function UpdateCooldown(button)
    local info = button.info
    local start, duration, enabled
    if info.spellID then
        local cooldown = C_Spell.GetSpellCooldown(info.spellID)
        if cooldown then
            start, duration, enabled = cooldown.startTime, cooldown.duration, cooldown.isEnabled
        end
    elseif info.itemID or info.toyID then
        start, duration, enabled = C_Container.GetItemCooldown(info.itemID or info.toyID)
    end
    if start and duration and enabled then
        button.Cooldown:SetCooldown(start, duration)
    else
        button.Cooldown:Clear()
    end
end

-- Count, dimming and (for the Safari Hat) use/remove toggling. Attribute changes wait for combat.
local function UpdateButton(button)
    local info = button.info
    local usable = true

    if info.itemID then
        local count = C_Item.GetItemCount(info.itemID)
        usable = count > 0
        if info.showCount then
            button.Count:SetText(count)
        end
    elseif info.toyID then
        usable = PlayerHasToy(info.toyID)
    end
    button.Icon:SetDesaturated(not usable)
    button.Icon:SetAlpha(usable and 1 or 0.6)

    if info.cancelBuff then
        local buffName = GetItemBuff(info.toyID or info.itemID)
        button.Cancel:SetShown(buffName ~= nil)
        -- Only touch the secure attributes when switching between "use" and "remove".
        local wantedType = buffName and "cancelaura" or "toy"
        if not InCombatLockdown() and button:GetAttribute("type") ~= wantedType then
            button:SetAttribute("type", wantedType)
            if buffName then
                button:SetAttribute("unit", "player")
                button:SetAttribute("spell", buffName)
            else
                button:SetAttribute("toy", info.toyID)
            end
        end
    end
    UpdateCooldown(button)
end

local function Button_OnEnter(button)
    local info = button.info
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    if info.spellID then
        GameTooltip:SetSpellByID(info.spellID)
    elseif info.toyID then
        GameTooltip:SetToyByItemID(info.toyID)
    elseif info.itemID then
        GameTooltip:SetItemByID(info.itemID)
    else
        GameTooltip:SetText(info.title)
        GameTooltip:AddLine(info.hint, 1, 1, 1, true)
    end
    if info.cancelBuff and button.Cancel:IsShown() then
        GameTooltip:AddLine(L["Click to remove it."], 0, 1, 0)
    end
    GameTooltip:Show()
end

local function CreateToolbarButton(info, index, offset)
    local isSecure = info.spellID or info.itemID or info.toyID
    local button = CreateFrame("Button", "LineupToolbarButton" .. index, bar, isSecure and "SecureActionButtonTemplate" or nil)
    button.info = info
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetPoint("LEFT", offset, 0)
    button:RegisterForClicks("AnyUp", "AnyDown")

    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetAllPoints()
    button.Icon:SetTexture(GetIcon(info))
    button.Icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)

    button.Border = button:CreateTexture(nil, "OVERLAY")
    button.Border:SetAllPoints()
    button.Border:SetTexture("Interface\\Common\\WhiteIconFrame")
    button.Border:SetVertexColor(0.6, 0.6, 0.6)

    button.Count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.Count:SetPoint("BOTTOMRIGHT", -1, 1)

    -- Red arrow while a removable buff (Safari Hat) is active.
    button.Cancel = button:CreateTexture(nil, "OVERLAY", nil, 1)
    button.Cancel:SetSize(20, 20)
    button.Cancel:SetPoint("BOTTOMRIGHT", 2, -2)
    button.Cancel:SetTexture("Interface\\Buttons\\UI-MicroStream-Red")
    button.Cancel:Hide()

    button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.Cooldown:SetAllPoints(button.Icon)

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    if info.spellID then
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", info.spellID)
    elseif info.itemID then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", "item:" .. info.itemID)
    elseif info.toyID then
        button:SetAttribute("type", "toy")
        button:SetAttribute("toy", info.toyID)
    else
        -- Summon: left-click a random favorite, right-click any random pet.
        button:SetScript("OnClick", function(_, mouseButton, down)
            if not down then
                C_PetJournal.SummonRandomPet(mouseButton ~= "RightButton")
            end
        end)
    end

    button:SetScript("OnEnter", Button_OnEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

-- Blizzard's own buttons, which the toolbar replaces. They're found by what they cast (or, as a
-- backup, by name) rather than by frame names, which have changed between game versions.
local SUMMON_RANDOM_FAVORITE_SPELL_ID = 243819
local SEARCH_DEPTH = 4
local blizzardButtons

-- True if the frame casts the spell: its "spell" attribute (an ID or the spell's name) or the
-- spellID field Blizzard's newer buttons carry.
local function CastsSpell(frame, spellID)
    local spell = frame:GetAttribute("spell")
    if spell and (tonumber(spell) == spellID or spell == C_Spell.GetSpellName(spellID)) then
        return true
    end
    return frame.spellID == spellID
end

local function SearchButtons(frame, depth, found)
    for _, child in ipairs({ frame:GetChildren() }) do
        local name = child:GetName() or ""
        if not found.heal and (CastsSpell(child, REVIVE_SPELL_ID) or name:find("HealPet")) then
            found.heal = child
        elseif not found.summon and (CastsSpell(child, SUMMON_RANDOM_FAVORITE_SPELL_ID) or name:find("RandomFavorite")) then
            found.summon = child
        end
        if depth < SEARCH_DEPTH then
            SearchButtons(child, depth + 1, found)
        end
    end
end

local function GetBlizzardButtons()
    if not blizzardButtons then
        blizzardButtons = {}
        SearchButtons(PetJournal, 1, blizzardButtons)
        ns:Debug("Pet Journal buttons found:", blizzardButtons.heal and (blizzardButtons.heal:GetName() or "heal") or "no heal",
            blizzardButtons.summon and (blizzardButtons.summon:GetName() or "summon") or "no summon")
    end
    return blizzardButtons.heal, blizzardButtons.summon
end

local function HideBlizzardButtons()
    if InCombatLockdown() then
        return
    end
    local heal, summon = GetBlizzardButtons()
    for _, button in pairs({ heal = heal, summon = summon }) do
        button:Hide()
    end
end

local function Overlaps(region, frame)
    local left, right, top, bottom = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
    if not (left and frame:GetLeft()) then
        return false
    end
    return left < frame:GetRight() and right > frame:GetLeft() and bottom < frame:GetTop() and top > frame:GetBottom()
end

-- Collects the Pet Journal's text and buttons, skipping our own bar.
local function CollectJournalWidgets(frame, depth, fontStrings, journalButtons)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            fontStrings[#fontStrings + 1] = region
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child ~= bar then
            local objectType = child:GetObjectType()
            if objectType == "Button" or objectType == "CheckButton" then
                journalButtons[#journalButtons + 1] = child
            end
            if depth < SEARCH_DEPTH then
                CollectJournalWidgets(child, depth + 1, fontStrings, journalButtons)
            end
        end
    end
end

-- Hides Blizzard text and buttons in the Pet Journal that sit under the bar, whatever Blizzard
-- calls them. Text is safe to hide any time; buttons can be protected, so only out of combat.
local blizzardHidden = false

HideTextBehindBar = function()
    -- Anything hidden stays hidden (buttons are hooked), so one successful pass is enough.
    if blizzardHidden or not bar or not bar:IsVisible() then
        return
    end
    local fontStrings, journalButtons = {}, {}
    CollectJournalWidgets(PetJournal, 1, fontStrings, journalButtons)
    for _, fontString in ipairs(fontStrings) do
        if fontString:IsVisible() and fontString:GetText() and fontString:GetText() ~= "" and Overlaps(fontString, bar) then
            ns:Debug("Hiding journal text under the toolbar:", fontString:GetName() or fontString:GetText())
            fontString:SetAlpha(0)
        end
    end
    if not InCombatLockdown() then
        blizzardHidden = true
        for _, button in ipairs(journalButtons) do
            if button:IsVisible() and Overlaps(button, bar) then
                ns:Debug("Hiding journal button under the toolbar:", button:GetName() or button:GetDebugName())
                button:Hide()
                if not keptHidden[button] then
                    keptHidden[button] = true
                    button:HookScript("OnShow", function(self)
                        if not InCombatLockdown() then
                            self:Hide()
                        end
                    end)
                end
            end
        end
    end
end

-- Keeps the bar at its height but moves it so its right edge lines up with the right edge of the
-- journal's content (the inset holding the pet card).
local function AlignRight(anchor)
    local edgeFrame = PetJournal.RightInset or PetJournal
    local edge = edgeFrame:GetRight()
    local right = bar:GetRight()
    if not (anchor and edge and right) then
        return
    end
    local shift = math.floor(edge - RIGHT_MARGIN - right + 0.5)
    if shift == 0 then
        return
    end
    local _, _, _, x = bar:GetPoint(1)
    bar:ClearAllPoints()
    bar:SetPoint("RIGHT", anchor, "RIGHT", (x or 0) + shift, 0)
end

local function Setup()
    local heal, summon = GetBlizzardButtons()

    bar = CreateFrame("Frame", nil, PetJournal)
    local offsets, dividers, width = GetLayout()
    bar:SetSize(width, BUTTON_SIZE)
    for _, x in ipairs(dividers) do
        local divider = bar:CreateTexture(nil, "ARTWORK")
        PixelUtil.SetSize(divider, 1, BUTTON_SIZE - 4)
        PixelUtil.SetPoint(divider, "LEFT", bar, "LEFT", x, 0)
        divider:SetColorTexture(1, 0.82, 0, 0.8)
    end
    -- In the spot of the rightmost Blizzard button; the journal's top-right corner if none was found.
    local anchor = summon or heal
    if anchor then
        bar:SetPoint("RIGHT", anchor, "RIGHT")
        bar:SetFrameLevel(anchor:GetFrameLevel() + 2)
    else
        bar:SetPoint("TOPRIGHT", PetJournal, "TOPRIGHT", -8, -28)
    end

    for index, info in ipairs(BUTTONS) do
        buttons[index] = CreateToolbarButton(info, index, offsets[index])
    end

    -- Blizzard may show its buttons again when the journal opens.
    for _, button in pairs({ heal = heal, summon = summon }) do
        button:HookScript("OnShow", HideBlizzardButtons)
    end
    HideBlizzardButtons()

    -- Positions are only known once the journal is drawn: then line the bar up on the right and
    -- hide whatever of Blizzard's is underneath it.
    local function AfterLayout()
        AlignRight(anchor)
        HideTextBehindBar()
    end
    bar:SetScript("OnShow", function()
        PetToolbar:Refresh()
        C_Timer.After(0, AfterLayout)
    end)
    PetToolbar:Refresh()
    C_Timer.After(0, AfterLayout)
end

function PetToolbar:Refresh()
    if not bar or not bar:IsVisible() then
        return
    end
    for _, button in ipairs(buttons) do
        UpdateButton(button)
    end
end

-- Called once the Pet Journal exists. Secure buttons can't be set up in combat.
function PetToolbar:Setup()
    if InCombatLockdown() then
        pendingSetup = true
        return
    end
    Setup()
end

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingSetup then
        pendingSetup = false
        Setup()
    end
    HideBlizzardButtons()
    PetToolbar:Refresh()
    if HideTextBehindBar then
        HideTextBehindBar()
    end
end)

local function OnToolbarEvent()
    PetToolbar:Refresh()
end
for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED", "TOYS_UPDATED" }) do
    ns:RegisterEvent(event, OnToolbarEvent)
end
-- Safari Hat and treat buffs: only the player's auras matter.
ns:RegisterUnitEvent("UNIT_AURA", "player", OnToolbarEvent)
