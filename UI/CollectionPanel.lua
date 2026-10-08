local _, ns = ...
local L = ns.L
local Collection = ns.Collection

-- A button next to the Pet Journal's "Total Pets" count, opening a panel about your collection:
-- an overview (collected, level 25, rare, quality), and bars per family or per source for a chosen
-- number (see Collection.METRICS). Hovering the button sums it up.
local CollectionPanel = {}
ns.CollectionPanel = CollectionPanel

local EXTRA_LEFT = ns.Dialogs.LEFT_BORDER_EXTRA
local BUTTON_ATLAS = "communities-icon-searchmagnifyingglass"
local BUTTON_SIZE = 16
local PANEL_WIDTH = 340 + EXTRA_LEFT
local PANEL_HEIGHT = 400
local PADDING = 12
-- Width inside the panel's inset, less padding.
local CONTENT_WIDTH = PANEL_WIDTH - 12 - EXTRA_LEFT - 2 * PADDING
local TABLE_ROW_HEIGHT = 18
-- x of the Unique and Total columns' right edges, from the content's right edge.
local UNIQUE_COLUMN_X, TOTAL_COLUMN_X = -70, 0
local BAR_ROW_HEIGHT = 22
local BAR_LABEL_WIDTH = 118
local BAR_VALUE_WIDTH = 48
local SOURCE_BAR_COLOR = CreateColor(0.85, 0.68, 0.28)

local TAB_OVERVIEW, TAB_FAMILIES, TAB_SOURCES = 1, 2, 3

local panel, overview, breakdown, metricDropdown
local currentTab = TAB_OVERVIEW
-- The number the bars show; stays chosen until the game is reloaded.
local metric = Collection.METRICS[1]

local function FormatNumber(number)
    return BreakUpLargeNumbers(number)
end

local function GetSourceName(source)
    return _G["BATTLE_PET_SOURCE_" .. source] or format(L["Source %d"], source)
end

-- Overview

local function CreateText(parent, fontObject, justify)
    local text = parent:CreateFontString(nil, "OVERLAY", fontObject)
    text:SetJustifyH(justify or "LEFT")
    return text
end

-- A table row: label on the left, unique and total counts in their columns.
local function CreateTableRow(parent, label, anchor, offsetY)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(TABLE_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or 0)
    row:SetPoint("RIGHT", parent)
    row.Label = CreateText(row, "GameFontHighlight")
    row.Label:SetPoint("LEFT")
    row.Label:SetText(label)
    row.Unique = CreateText(row, "GameFontHighlight", "RIGHT")
    row.Unique:SetPoint("RIGHT", UNIQUE_COLUMN_X, 0)
    row.Total = CreateText(row, "GameFontHighlight", "RIGHT")
    row.Total:SetPoint("RIGHT", TOTAL_COLUMN_X, 0)
    return row
end

local function CreateOverview(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", PADDING, -PADDING)
    frame:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    -- "You have 1,234 of the journal's 1,800 pets." and a bar for the share.
    frame.Headline = CreateText(frame, "GameFontHighlight")
    frame.Headline:SetPoint("TOPLEFT")
    frame.Headline:SetPoint("RIGHT")

    frame.Progress = CreateFrame("StatusBar", nil, frame)
    frame.Progress:SetPoint("TOPLEFT", frame.Headline, "BOTTOMLEFT", 0, -8)
    frame.Progress:SetPoint("RIGHT")
    frame.Progress:SetHeight(16)
    frame.Progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.Progress:SetStatusBarColor(0.1, 0.65, 0.15)
    frame.Progress.Background = frame.Progress:CreateTexture(nil, "BACKGROUND")
    frame.Progress.Background:SetAllPoints()
    frame.Progress.Background:SetColorTexture(0, 0, 0, 0.5)
    frame.Progress.Text = CreateText(frame.Progress, "GameFontHighlightSmall", "CENTER")
    frame.Progress.Text:SetPoint("CENTER")

    -- Counts: unique (species) and total (pets), then single numbers in the Total column.
    local header = CreateTableRow(frame, "", frame.Progress, -14)
    header.Unique:SetFontObject("GameFontNormalSmall")
    header.Unique:SetText(L["Unique"])
    header.Total:SetFontObject("GameFontNormalSmall")
    header.Total:SetText(L["Total"])

    frame.Collected = CreateTableRow(frame, L["Collected"], header)
    frame.MaxLevel = CreateTableRow(frame, L["Level 25"], frame.Collected)
    frame.Rare = CreateTableRow(frame, L["Rare quality"], frame.MaxLevel)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    local thickness = ns.SetDividerTexture(divider)
    divider:SetHeight(thickness)
    divider:SetPoint("TOPLEFT", frame.Rare, "BOTTOMLEFT", 0, -5)
    divider:SetPoint("RIGHT")

    frame.Duplicates = CreateTableRow(frame, L["Duplicates"], frame.Rare, -10)
    frame.Missing = CreateTableRow(frame, L["Not collected"], frame.Duplicates)
    frame.Average = CreateTableRow(frame, L["Average battle pet level"], frame.Missing)
    frame.InTeams = CreateTableRow(frame, L["Pets in your teams"], frame.Average)

    -- Quality: one bar split by the share of each quality, and the counts below it.
    local qualityTitle = CreateText(frame, "GameFontNormal")
    qualityTitle:SetPoint("TOPLEFT", frame.InTeams, "BOTTOMLEFT", 0, -14)
    qualityTitle:SetText(QUALITY)

    frame.QualityBar = CreateFrame("Frame", nil, frame)
    frame.QualityBar:SetPoint("TOPLEFT", qualityTitle, "BOTTOMLEFT", 0, -6)
    frame.QualityBar:SetPoint("RIGHT")
    frame.QualityBar:SetHeight(12)
    local background = frame.QualityBar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.5)
    -- Rare first, so the best part of the collection reads first.
    frame.QualitySegments = {}
    local previous
    for rarity = 4, 1, -1 do
        local segment = frame.QualityBar:CreateTexture(nil, "ARTWORK")
        segment:SetPoint("TOP")
        segment:SetPoint("BOTTOM")
        if previous then
            segment:SetPoint("LEFT", previous, "RIGHT")
        else
            segment:SetPoint("LEFT")
        end
        segment:SetColorTexture(ns.GetRarityColor(rarity))
        frame.QualitySegments[rarity] = segment
        previous = segment
    end

    frame.QualityLegend = CreateText(frame, "GameFontHighlightSmall")
    frame.QualityLegend:SetPoint("TOPLEFT", frame.QualityBar, "BOTTOMLEFT", 0, -6)
    frame.QualityLegend:SetPoint("RIGHT")
    frame.QualityLegend:SetSpacing(2)
    return frame
end

local function RefreshOverview(stats)
    local total = stats.total
    overview.Headline:SetText(format(L["You have %s of the journal's %s pets."],
        FormatNumber(total.unique), FormatNumber(total.species)))
    overview.Progress:SetMinMaxValues(0, max(total.species, 1))
    overview.Progress:SetValue(total.unique)
    overview.Progress.Text:SetText(format(L["%.1f%% collected"], total.species > 0 and total.unique * 100 / total.species or 0))

    overview.Collected.Unique:SetText(FormatNumber(total.unique))
    overview.Collected.Total:SetText(FormatNumber(total.collected))
    overview.MaxLevel.Unique:SetText(FormatNumber(total.uniqueMaxLevel))
    overview.MaxLevel.Total:SetText(FormatNumber(total.maxLevel))
    overview.Rare.Unique:SetText(FormatNumber(total.uniqueRare))
    overview.Rare.Total:SetText(FormatNumber(total.rare))
    overview.Duplicates.Total:SetText(FormatNumber(total.collected - total.unique))
    overview.Missing.Total:SetText(FormatNumber(total.species - total.unique))
    overview.Average.Total:SetText(format("%.1f", total.battlePets > 0 and total.levels / total.battlePets or 0))
    overview.InTeams.Total:SetText(FormatNumber(stats.inTeams))

    -- Segment widths by share; a texture can't be 0 wide, so empty ones are hidden instead.
    local legend = {}
    for rarity = 4, 1, -1 do
        local count = stats.qualities[rarity]
        local segment = overview.QualitySegments[rarity]
        segment:SetWidth(max(CONTENT_WIDTH * count / max(total.collected, 1), 0.001))
        segment:SetShown(count > 0)
        local r, g, b = ns.GetRarityColor(rarity)
        legend[#legend + 1] = format("|cff%02x%02x%02x%s|r %s", r * 255, g * 255, b * 255,
            _G["ITEM_QUALITY" .. (rarity - 1) .. "_DESC"], FormatNumber(count))
    end
    overview.QualityLegend:SetText(table.concat(legend, "   "))
end

-- Breakdown (families or sources)

local function ShowRowTooltip(row)
    local tally = row.tally
    if not tally then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.Label:GetText())
    for _, each in ipairs(Collection.METRICS) do
        local _, text = Collection.Describe(tally, each)
        local shade = each == metric and 1 or 0.75
        GameTooltip:AddDoubleLine(each.label, text, shade, shade, shade, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function CreateBarRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(BAR_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent.Dropdown, "BOTTOMLEFT", 0, -10 - (index - 1) * BAR_ROW_HEIGHT)
    row:SetPoint("RIGHT")

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT")
    row.Label = CreateText(row, "GameFontHighlightSmall")
    row.Label:SetWordWrap(false)

    row.Value = CreateText(row, "GameFontHighlightSmall", "RIGHT")
    row.Value:SetPoint("RIGHT")
    row.Value:SetWidth(BAR_VALUE_WIDTH)

    row.Bar = CreateFrame("StatusBar", nil, row)
    row.Bar:SetPoint("LEFT", BAR_LABEL_WIDTH, 0)
    row.Bar:SetPoint("RIGHT", row.Value, "LEFT", -6, 0)
    row.Bar:SetHeight(12)
    row.Bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.Bar.Background = row.Bar:CreateTexture(nil, "BACKGROUND")
    row.Bar.Background:SetAllPoints()
    row.Bar.Background:SetColorTexture(0, 0, 0, 0.5)

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    return row
end

local function CreateBreakdown(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", PADDING, -PADDING)
    frame:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    local label = CreateText(frame, "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, -5)
    label:SetText(L["Show"])

    metricDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    metricDropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
    metricDropdown:SetPoint("RIGHT")
    metricDropdown:SetupMenu(function(_, root)
        local function IsSelected(each)
            return each == metric
        end
        local function Select(each)
            metric = each
            CollectionPanel:Refresh()
        end
        for _, each in ipairs(Collection.METRICS) do
            root:CreateRadio(each.label, IsSelected, Select, each)
        end
    end)
    frame.Dropdown = metricDropdown

    frame.Rows = {}
    return frame
end

local function RefreshBreakdown(stats)
    local byFamily = currentTab ~= TAB_SOURCES
    local values, fullBar = Collection.GetBreakdown(byFamily and "families" or "sources", metric)
    for index, entry in ipairs(values) do
        local row = breakdown.Rows[index] or CreateBarRow(breakdown, index)
        breakdown.Rows[index] = row
        row.tally = (byFamily and stats.families or stats.sources)[entry.id]

        row.Icon:SetShown(byFamily)
        row.Label:ClearAllPoints()
        if byFamily then
            row.Icon:SetTexture(ns.GetFamilyIcon(entry.id))
            row.Label:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
            row.Label:SetText(ns.GetFamilyName(entry.id))
        else
            row.Label:SetPoint("LEFT")
            row.Label:SetText(GetSourceName(entry.id))
        end
        row.Label:SetPoint("RIGHT", row.Bar, "LEFT", -6, 0)

        local color = byFamily and ns.GetFamilyColor(entry.id) or SOURCE_BAR_COLOR
        row.Bar:SetStatusBarColor(color:GetRGB())
        row.Bar:SetMinMaxValues(0, fullBar)
        row.Bar:SetValue(entry.value)
        row.Value:SetText(entry.text)
        row:Show()
    end
    for index = #values + 1, #breakdown.Rows do
        breakdown.Rows[index]:Hide()
    end
end

-- Panel

local function SelectTab(tab)
    currentTab = tab
    PanelTemplates_SetTab(panel, tab)
    overview:SetShown(tab == TAB_OVERVIEW)
    breakdown:SetShown(tab ~= TAB_OVERVIEW)
    CollectionPanel:Refresh()
end

local function CreatePanel(anchor)
    panel = CreateFrame("Frame", "LineupCollectionPanel", PetJournal, "ButtonFrameTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    ButtonFrameTemplate_HidePortrait(panel)
    panel:SetTitle(L["Pet Collection"])
    tinsert(UISpecialFrames, panel:GetName())
    panel:Hide()

    local inset = panel.Inset
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", 6 + EXTRA_LEFT, -26)
    inset:SetPoint("BOTTOMRIGHT", -6, 6)

    overview = CreateOverview(inset)
    breakdown = CreateBreakdown(inset)

    panel.Tabs = {}
    local tabLabels = { [TAB_OVERVIEW] = L["Overview"], [TAB_FAMILIES] = L["Families"], [TAB_SOURCES] = L["Sources"] }
    for index, label in ipairs(tabLabels) do
        local tab = CreateFrame("Button", "LineupCollectionPanelTab" .. index, panel, "PanelTabButtonTemplate")
        tab:SetID(index)
        tab:SetText(label)
        PanelTemplates_TabResize(tab, 0)
        tab:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            SelectTab(index)
        end)
        if index == 1 then
            tab:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 11, 2)
        else
            tab:SetPoint("LEFT", panel.Tabs[index - 1], "RIGHT", 3, 0)
        end
        panel.Tabs[index] = tab
    end
    PanelTemplates_SetNumTabs(panel, #panel.Tabs)

    panel:SetScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        SelectTab(currentTab)
    end)
    panel:SetScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)
    -- Closed along with the journal, so it doesn't pop up again next time.
    PetJournal:HookScript("OnHide", function()
        panel:Hide()
    end)
end

local function ShowButtonTooltip(button)
    local total = Collection.GetStats().total
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Pet Collection"])
    GameTooltip:AddDoubleLine(L["Unique pets"], FormatNumber(total.unique), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Total pets"], FormatNumber(total.collected), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Not collected"], FormatNumber(total.species - total.unique), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Average battle pet level"],
        format("%.1f", total.battlePets > 0 and total.levels / total.battlePets or 0), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Click for details."], 0, 1, 0)
    GameTooltip:Show()
end

-- Called once the Pet Journal exists.
function CollectionPanel:Setup()
    local petCount = PetJournal.PetCount
    if not petCount then
        return
    end

    local button = CreateFrame("Button", nil, PetJournal)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetPoint("LEFT", petCount, "RIGHT", 4, 0)
    button:SetFrameLevel(petCount:GetFrameLevel() + 2)
    -- A flat symbol rather than a framed icon; it lights up while hovered.
    button:SetNormalAtlas(BUTTON_ATLAS)
    button:SetHighlightAtlas(BUTTON_ATLAS, "ADD")
    button:SetScript("OnClick", function()
        GameTooltip:Hide()
        panel:SetShown(not panel:IsShown())
    end)
    button:SetScript("OnEnter", ShowButtonTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)

    CreatePanel(button)
    -- Pets changed (see Roster:Invalidate): redraw once the new list can be read.
    hooksecurefunc(ns.Roster, "Invalidate", function()
        C_Timer.After(0, function()
            CollectionPanel:Refresh()
        end)
    end)
end

function CollectionPanel:Refresh()
    if not panel or not panel:IsVisible() then
        return
    end
    local stats = Collection.GetStats()
    if currentTab == TAB_OVERVIEW then
        RefreshOverview(stats)
    else
        metricDropdown:GenerateMenu()
        RefreshBreakdown(stats)
    end
end
