local _, ns = ...

-- Small wrapper around StaticPopup for confirmations.
local Dialogs = {}
ns.Dialogs = Dialogs

StaticPopupDialogs.LINEUP_PETBATTLES_CONFIRM = {
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
    StaticPopup_Show("LINEUP_PETBATTLES_CONFIRM", prompt, nil, { onAccept = onAccept })
end

-- Two choices and Cancel, e.g. Replace / Keep Both. The button texts are set on each show.
StaticPopupDialogs.LINEUP_PETBATTLES_CHOOSE = {
    text = "%s",
    button1 = OKAY,
    button2 = CANCEL,
    button3 = OKAY,
    OnShow = function(popup, data)
        popup:GetButton1():SetText(data.firstText)
        popup:GetButton3():SetText(data.secondText)
    end,
    OnAccept = function(_, data)
        data.onFirst()
    end,
    OnAlt = function(_, data)
        data.onSecond()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function Dialogs.Choose(prompt, firstText, onFirst, secondText, onSecond)
    StaticPopup_Show("LINEUP_PETBATTLES_CHOOSE", prompt, nil,
        { firstText = firstText, onFirst = onFirst, secondText = secondText, onSecond = onSecond })
end

-- ButtonFrameTemplate's left border is wider than its right one, so content needs this much more
-- room on the left than on the right to sit evenly between them. Windows are this much wider too.
Dialogs.LEFT_BORDER_EXTRA = 5

-- A draggable window (ButtonFrameTemplate, without the portrait) above other UI, closed by Escape.
-- A free-standing one (freeStanding) sits lower and stays open on Escape, e.g. for use in battle.
function Dialogs.CreateWindow(name, width, height, freeStanding)
    local window = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
    window:SetSize(width, height)
    window:SetFrameStrata(freeStanding and "HIGH" or "DIALOG")
    window:SetToplevel(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    ButtonFrameTemplate_HidePortrait(window)
    if not freeStanding then
        tinsert(UISpecialFrames, name)
    end
    return window
end

-- A red message below editBox saying what's wrong with its input (e.g. "A team needs a name"),
-- rather than a chat message. Returns a function that shows a message, or hides it with nil.
-- Typing in the box hides it too.
function Dialogs.CreateInputError(editBox)
    local text = editBox:GetParent():CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    text:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -1)
    text:SetJustifyH("LEFT")
    text:Hide()
    editBox:HookScript("OnTextChanged", function(_, userInput)
        if userInput then
            text:Hide()
        end
    end)
    return function(message)
        text:SetText(message or "")
        text:SetShown(message ~= nil)
    end
end

-- A small up or down arrow button for moving an entry in a list (delta -1 = up, 1 = down);
-- onClick runs on a click. Disable it at the list's ends.
function Dialogs.CreateArrowButton(parent, delta, onClick)
    local texturePrefix = delta < 0 and "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton"
        or "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton"
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(24, 24)
    button:SetNormalTexture(texturePrefix .. "-Up")
    button:SetPushedTexture(texturePrefix .. "-Down")
    button:SetDisabledTexture(texturePrefix .. "-Disabled")
    button:SetHighlightTexture(texturePrefix .. "-Highlight", "ADD")
    button:SetScript("OnClick", onClick)
    return button
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
