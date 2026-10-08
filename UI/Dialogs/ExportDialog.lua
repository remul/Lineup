local _, ns = ...
local L = ns.L

-- Window showing exported team strings (see Export.lua), selected and ready to copy.
local ExportDialog = {}
ns.ExportDialog = ExportDialog

local EXTRA_LEFT = ns.Dialogs.LEFT_BORDER_EXTRA
local DIALOG_WIDTH = 460 + EXTRA_LEFT
local DIALOG_HEIGHT = 320

local dialog, textBox, exportedText

local function CreateDialog()
    dialog = ns.Dialogs.CreateWindow("LineupExportDialog", DIALOG_WIDTH, DIALOG_HEIGHT)
    dialog.Inset:Hide()

    -- Addons can't write to the clipboard, so the text is selected for Ctrl+C.
    local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", 16 + EXTRA_LEFT, -32)
    hint:SetPoint("RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["Press Ctrl+C to copy. Paste it into Import in Lineup or Rematch."])

    local textInset = CreateFrame("Frame", nil, dialog, "InsetFrameTemplate")
    textInset:SetPoint("TOPLEFT", 14 + EXTRA_LEFT, -56)
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

    ns.Dialogs.PlaceWindow(dialog)
    dialog:Show()
    dialog:Raise()
    textBox:SetFocus()
    textBox:SetCursorPosition(0)
    textBox:HighlightText()
end
