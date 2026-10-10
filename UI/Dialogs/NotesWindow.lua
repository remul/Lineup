local _, ns = ...

-- A free-standing window with a team's notes, so a strategy can be followed during a pet battle
-- with the Pet Journal closed. It isn't parented to the journal and Escape doesn't close it; one
-- window is reused for whichever team was opened last.
local NotesWindow = {}
ns.NotesWindow = NotesWindow

local EXTRA_LEFT = ns.Dialogs.LEFT_BORDER_EXTRA
local WINDOW_WIDTH = 340 + EXTRA_LEFT
local WINDOW_HEIGHT = 380
local TEXT_PADDING = 8

local window, scrollFrame, content, notesText

local function CreateWindow()
    window = ns.Dialogs.CreateWindow("LineupPetBattlesNotesWindow", WINDOW_WIDTH, WINDOW_HEIGHT, true)
    window:SetPoint("CENTER", 300, 0)

    local inset = window.Inset
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", 6 + EXTRA_LEFT, -26)
    inset:SetPoint("BOTTOMRIGHT", -6, 6)

    scrollFrame = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", TEXT_PADDING, -TEXT_PADDING)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, TEXT_PADDING)

    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(WINDOW_WIDTH - 60, 1)
    scrollFrame:SetScrollChild(content)

    notesText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    notesText:SetPoint("TOPLEFT")
    notesText:SetPoint("RIGHT")
    notesText:SetJustifyH("LEFT")
    notesText:SetSpacing(3)
end

function NotesWindow:Open(team)
    if not window then
        CreateWindow()
    end

    window:SetTitle(team.name)
    notesText:SetText(team.notes or "")
    -- Size the scroll child to the text so the scroll bar covers all of it.
    content:SetHeight(math.max(notesText:GetStringHeight(), 1))

    window:Show()
    window:Raise()
    scrollFrame:SetVerticalScroll(0)
end

-- True if the team has notes to show.
function NotesWindow.HasContent(team)
    return team.notes ~= nil
end
