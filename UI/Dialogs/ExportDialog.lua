local _, ns = ...
local L = ns.L

-- Window showing exported team strings (see Export.lua), selected and ready to copy.
local ExportDialog = {}
ns.ExportDialog = ExportDialog

local DIALOG_WIDTH = 460
local DIALOG_HEIGHT = 320

local dialog, textBox, exportedText

local function CreateDialog()
    dialog = CreateFrame("Frame", "LineupExportDialog", UIParent, "ButtonFrameTemplate")
    dialog:SetSize(DIALOG_WIDTH, DIALOG_HEIGHT)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetToplevel(true)
    dialog:SetMovable(true)
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    ButtonFrameTemplate_HidePortrait(dialog)
    dialog.Inset:Hide()
    tinsert(UISpecialFrames, dialog:GetName())

    -- Addons can't write to the clipboard, so the text is selected for Ctrl+C.
    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", 16, -32)
    hint:SetPoint("RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["Press Ctrl+C to copy. Paste it into Import in Lineup or Rematch."])

    local textInset = CreateFrame("Frame", nil, dialog, "InsetFrameTemplate")
    textInset:SetPoint("TOPLEFT", 14, -56)
    textInset:SetPoint("BOTTOMRIGHT", -14, 36)

    -- Read-only: typing puts the exported text back, and any click selects all of it again.
    textBox = ns.Dialogs.CreateMultiLineEditBox(textInset, DIALOG_WIDTH - 80, function(box, userInput)
        if userInput then
            box:SetText(exportedText)
            box:HighlightText()
        end
    end)
    textBox:HookScript("OnEditFocusGained", function(box)
        box:HighlightText()
    end)
    textBox:HookScript("OnMouseUp", function(box)
        box:HighlightText()
    end)

    local closeButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    closeButton:SetPoint("BOTTOMRIGHT", -8, 6)
    closeButton:SetSize(100, 22)
    closeButton:SetText(CLOSE)
    closeButton:SetScript("OnClick", function()
        dialog:Hide()
    end)
end

-- Shows text (from Export) under the given title.
function ExportDialog:Open(title, text)
    if not dialog then
        CreateDialog()
    end
    exportedText = text
    dialog:SetTitle(title)
    textBox:SetText(text)

    local teamsPanel = ns.TeamsPanel:GetFrame()
    dialog:ClearAllPoints()
    if teamsPanel and teamsPanel:IsVisible() then
        dialog:SetPoint("TOPLEFT", teamsPanel, "TOPRIGHT", 4, 0)
    else
        dialog:SetPoint("CENTER")
    end
    dialog:Show()
    dialog:Raise()
    textBox:SetFocus()
    textBox:SetCursorPosition(0)
    textBox:HighlightText()
end
