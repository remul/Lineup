local _, ns = ...
local L = ns.L
local Collection = ns.Collection

-- The Statistics tab of the Lineup window, about your pet collection: how much of it you have on
-- the window itself (like the Settings tab's header), then sunk into it an overview (collected,
-- level 25, rare, quality) and bars per family or per source for a chosen number (see
-- Collection.METRICS).
local StatisticsView = {}
ns.StatisticsView = StatisticsView

local TABLE_ROW_HEIGHT = 18
-- x of the Unique and Total columns' right edges, from the content's right edge.
local UNIQUE_COLUMN_X, TOTAL_COLUMN_X = -70, 0
-- Bar rows shrink to this height at most so every family or source fits.
local BAR_ROW_HEIGHT, BAR_ROW_MIN_HEIGHT = 22, 16
local BAR_LABEL_WIDTH = 118
local BAR_VALUE_WIDTH = 48
local SOURCE_BAR_COLOR = CreateColor(0.85, 0.68, 0.28)
local BREAKDOWN_PADDING = 8
-- Extra room left and right of the data in both insets, beyond the usual section padding.
local SIDE_PADDING = 10
-- Space below the quality legend.
local BOTTOM_PADDING = 6
-- Between the quality legend's entries ("Rare 123 • Uncommon 45"): a grey bullet.
local LEGEND_SEPARATOR = "  |cff808080\226\128\162|r  "
local DROPDOWN_HEIGHT = 26
local BY_FAMILY, BY_SOURCE = "families", "sources"

local view, header, overview, breakdown
-- What the bars are split by and the number they show; stay chosen until the game is reloaded.
local breakdownBy = BY_FAMILY
local metric = Collection.METRICS[1]

local function FormatNumber(number)
    return BreakUpLargeNumbers(number)
end

local function GetSourceName(source)
    return _G["BATTLE_PET_SOURCE_" .. source] or format(L["Source %d"], source)
end

local function CreateText(parent, fontObject, justify)
    local text = parent:CreateFontString(nil, "OVERLAY", fontObject)
    text:SetJustifyH(justify or "LEFT")
    return text
end

-- Header, on the window above the insets: "You have 1,234 of the journal's 1,800 pets." and a bar
-- for the share.

local HEADER_TOP = -40
-- Gap between the headline and the bar, and the bar's share of the header's width.
local HEADER_GAP = 14
local PROGRESS_WIDTH = 0.8
local HEADER_HEIGHT = 18 + HEADER_GAP + 20

local function CreateHeader(parent)
    local edge = ns.TeamsPanel.SECTION_INSET
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", edge, HEADER_TOP)
    frame:SetPoint("TOPRIGHT", -edge, HEADER_TOP)
    frame:SetHeight(HEADER_HEIGHT)

    frame.Headline = CreateText(frame, "GameFontNormalLarge", "CENTER")
    frame.Headline:SetPoint("TOPLEFT")
    frame.Headline:SetPoint("RIGHT")

    frame.Progress = CreateFrame("StatusBar", nil, frame)
    frame.Progress:SetPoint("TOP", frame.Headline, "BOTTOM", 0, -HEADER_GAP)
    frame:SetScript("OnSizeChanged", function(_, width)
        frame.Progress:SetWidth(width * PROGRESS_WIDTH)
    end)
    frame.Progress:SetHeight(20)
    frame.Progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.Progress:SetStatusBarColor(0.1, 0.65, 0.15)
    frame.Progress.Background = frame.Progress:CreateTexture(nil, "BACKGROUND")
    frame.Progress.Background:SetAllPoints()
    frame.Progress.Background:SetColorTexture(0, 0, 0, 0.5)
    frame.Progress.Text = CreateText(frame.Progress, "GameFontHighlight", "CENTER")
    frame.Progress.Text:SetPoint("CENTER")

    header = frame
    return frame
end

local function RefreshHeader(total)
    -- The numbers in white, so they stand out from the gold sentence.
    header.Headline:SetText(format(L["You have %s of the journal's %s pets"],
        WHITE_FONT_COLOR:WrapTextInColorCode(FormatNumber(total.unique)),
        WHITE_FONT_COLOR:WrapTextInColorCode(FormatNumber(total.species))))
    header.Progress:SetMinMaxValues(0, max(total.species, 1))
    header.Progress:SetValue(total.unique)
    header.Progress.Text:SetText(format(L["%.1f%% collected"], total.species > 0 and total.unique * 100 / total.species or 0))
end

-- Overview, as a section of the window (see TeamsPanel.CreateSectionInset)

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

local Overview = {}
-- The table (header, 3 rows, divider, 4 rows), then the quality bar and legend.
Overview.HEIGHT = 8 * TABLE_ROW_HEIGHT + 10 + 14 + 12 + 6 + 12 + 6 + 12 + BOTTOM_PADDING

function Overview:Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(self.HEIGHT)

    -- Counts: unique (species) and total (pets), then single numbers in the Total column.
    local columns = CreateTableRow(frame, "", frame)
    columns:ClearAllPoints()
    columns:SetPoint("TOPLEFT")
    columns:SetPoint("RIGHT")
    columns.Unique:SetFontObject("GameFontNormalSmall")
    columns.Unique:SetText(L["Unique"])
    columns.Total:SetFontObject("GameFontNormalSmall")
    columns.Total:SetText(L["Total"])

    frame.Collected = CreateTableRow(frame, L["Collected"], columns)
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

    overview = frame
    return frame
end

local function RefreshOverview(stats)
    local total = stats.total
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
    local barWidth = overview.QualityBar:GetWidth()
    local legend = {}
    for rarity = 4, 1, -1 do
        local count = stats.qualities[rarity]
        local segment = overview.QualitySegments[rarity]
        segment:SetWidth(max(barWidth * count / max(total.collected, 1), 0.001))
        segment:SetShown(count > 0)
        local r, g, b = ns.GetRarityColor(rarity)
        legend[#legend + 1] = format("|cff%02x%02x%02x%s|r %s", r * 255, g * 255, b * 255,
            _G["ITEM_QUALITY" .. (rarity - 1) .. "_DESC"], FormatNumber(count))
    end
    overview.QualityLegend:SetText(table.concat(legend, LEGEND_SEPARATOR))
end

-- Breakdown (families or sources), filling the rest of the tab

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

local function CreateBarRow(parent)
    local row = CreateFrame("Frame", nil, parent)
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
    frame:SetPoint("TOPLEFT", BREAKDOWN_PADDING + SIDE_PADDING, -BREAKDOWN_PADDING)
    frame:SetPoint("BOTTOMRIGHT", -BREAKDOWN_PADDING - SIDE_PADDING, BREAKDOWN_PADDING)

    -- Families or sources on the left, the number the bars show on the right.
    frame.ByDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    frame.ByDropdown:SetPoint("TOPLEFT")
    frame.ByDropdown:SetWidth(BAR_LABEL_WIDTH)
    frame.ByDropdown:SetupMenu(function(_, root)
        local function IsSelected(each)
            return each == breakdownBy
        end
        local function Select(each)
            breakdownBy = each
            StatisticsView:Refresh()
        end
        root:CreateRadio(L["Families"], IsSelected, Select, BY_FAMILY)
        root:CreateRadio(L["Sources"], IsSelected, Select, BY_SOURCE)
    end)

    frame.MetricDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    frame.MetricDropdown:SetPoint("LEFT", frame.ByDropdown, "RIGHT", 8, 0)
    frame.MetricDropdown:SetPoint("RIGHT")
    frame.MetricDropdown:SetupMenu(function(_, root)
        local function IsSelected(each)
            return each == metric
        end
        local function Select(each)
            metric = each
            StatisticsView:Refresh()
        end
        for _, each in ipairs(Collection.METRICS) do
            root:CreateRadio(each.label, IsSelected, Select, each)
        end
    end)

    frame.Rows = {}
    breakdown = frame
end

local function RefreshBreakdown(stats)
    breakdown.ByDropdown:GenerateMenu()
    breakdown.MetricDropdown:GenerateMenu()

    local byFamily = breakdownBy == BY_FAMILY
    local values, fullBar = Collection.GetBreakdown(breakdownBy, metric)
    local rowsHeight = breakdown:GetHeight() - DROPDOWN_HEIGHT - 8
    local rowHeight = max(BAR_ROW_MIN_HEIGHT, min(BAR_ROW_HEIGHT, floor(rowsHeight / max(#values, 1))))
    for index, entry in ipairs(values) do
        local row = breakdown.Rows[index] or CreateBarRow(breakdown)
        breakdown.Rows[index] = row
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -DROPDOWN_HEIGHT - 8 - (index - 1) * rowHeight)
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

-- View

function StatisticsView:Create(parent)
    view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view:Hide()

    CreateHeader(view)

    -- The overview sunk into the window below the header, like a section (see
    -- TeamsPanel.CreateSectionInset), with the breakdown in a second inset under it.
    local padding = ns.TeamsPanel.SECTION_INSET - ns.TeamsPanel.INSET_LEFT
    local overviewTop = HEADER_TOP - HEADER_HEIGHT - 12
    local overviewInset = CreateFrame("Frame", nil, view, "InsetFrameTemplate")
    overviewInset:SetPoint("TOPLEFT", ns.TeamsPanel.INSET_LEFT, overviewTop)
    overviewInset:SetPoint("TOPRIGHT", ns.TeamsPanel.INSET_RIGHT, overviewTop)
    overviewInset:SetHeight(Overview.HEIGHT + 2 * padding)
    local overviewSection = Overview:Create(overviewInset)
    overviewSection:SetPoint("TOPLEFT", padding + SIDE_PADDING, -padding)
    overviewSection:SetPoint("TOPRIGHT", -padding - SIDE_PADDING, -padding)

    local inset = CreateFrame("Frame", nil, view, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", overviewInset, "BOTTOMLEFT", 0, -ns.TeamsPanel.INSET_GAP)
    inset:SetPoint("BOTTOMRIGHT", ns.TeamsPanel.INSET_RIGHT, 26)
    CreateBreakdown(inset)

    -- Pets changed (see Roster:Invalidate): redraw once the new list can be read.
    hooksecurefunc(ns.Roster, "Invalidate", function()
        ns.TeamsPanel:Refresh()
    end)
    return view
end

function StatisticsView:Refresh()
    if not view or not view:IsVisible() then
        return
    end
    local stats = Collection.GetStats()
    RefreshHeader(stats.total)
    RefreshOverview(stats)
    RefreshBreakdown(stats)
end
