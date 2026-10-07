local _, ns = ...

-- Small wrapper around StaticPopup for confirmations.
local Dialogs = {}
ns.Dialogs = Dialogs

StaticPopupDialogs.LINEUP_CONFIRM = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        data.onAccept()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function Dialogs.Confirm(prompt, onAccept)
    StaticPopup_Show("LINEUP_CONFIRM", prompt, nil, { onAccept = onAccept })
end

-- Windows the player has dragged somewhere, and those already watched for that ([frame] = true).
local movedWindows, watchedWindows = {}, {}

-- Positions a window as it opens: centered on the screen, or where the player last dragged it
-- (until the game is reloaded).
function Dialogs.PlaceWindow(frame)
    if not watchedWindows[frame] then
        watchedWindows[frame] = true
        frame:HookScript("OnDragStop", function()
            movedWindows[frame] = true
        end)
    end
    if not movedWindows[frame] then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end
end

-- A scrolling multi-line text box filling inset (an InsetFrameTemplate frame).
-- The edit box is only as tall as its text, so clicks on the empty area below it focus the box
-- and put the cursor at the end. onTextChanged(editBox, userInput) is optional.
function Dialogs.CreateMultiLineEditBox(inset, width, onTextChanged)
    local scrollFrame = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    -- Edit boxes default to 255 bytes, which cuts off team strings with notes and scripts.
    editBox:SetMaxLetters(0)
    editBox:SetMaxBytes(0)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    -- A multi-line edit box needs a real starting size; with no height it lays out (and keeps)
    -- text wrongly. Keep it at least as tall as the visible area so all of it is clickable.
    editBox:SetSize(width, 64)
    scrollFrame:SetScript("OnSizeChanged", function(_, frameWidth, frameHeight)
        editBox:SetWidth(frameWidth)
        editBox:SetHeight(frameHeight)
    end)
    editBox:SetScript("OnEscapePressed", EditBox_ClearFocus)
    editBox:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
    editBox:SetScript("OnUpdate", function(box, elapsed)
        ScrollingEdit_OnUpdate(box, elapsed, scrollFrame)
    end)
    editBox:SetScript("OnTextChanged", function(box, userInput)
        ScrollingEdit_OnTextChanged(box, scrollFrame)
        if onTextChanged then
            onTextChanged(box, userInput)
        end
    end)
    scrollFrame:SetScrollChild(editBox)

    local function FocusAtEnd()
        editBox:SetFocus()
        editBox:SetCursorPosition(#editBox:GetText())
    end
    for _, region in ipairs({ inset, scrollFrame }) do
        region:EnableMouse(true)
        region:SetScript("OnMouseDown", FocusAtEnd)
    end

    return editBox
end
