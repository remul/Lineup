local _, ns = ...

-- Translations. Strings are looked up by their English text, e.g. L["Load Team"]; without a
-- translation for the client's language the English text is used, so nothing ever shows up empty.
-- Each language has its own file that calls ns.RegisterLocale (see deDE.lua).
local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
ns.L = L

-- The languages Lineup has, English first, then in the order they register.
ns.LOCALES = { "enUS" }
local translations = {} -- [locale] = strings

local function Apply(strings)
    for key, value in pairs(strings) do
        L[key] = value
    end
end

-- Keeps a language's strings, and uses them if the game client uses this language (e.g. "deDE").
function ns.RegisterLocale(locale, strings)
    translations[locale] = strings
    ns.LOCALES[#ns.LOCALES + 1] = locale
    if GetLocale() == locale then
        Apply(strings)
    end
end

-- Uses another language than the game's (the Language option), once the addon is loaded and before
-- any of its windows are built. Strings must be looked up after this, never at file load.
function ns.SetLocale(locale)
    wipe(L)
    Apply(translations[locale] or {})
end
