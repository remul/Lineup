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

-- Adds the strings if the game client uses this language (e.g. "deDE").
function ns.RegisterLocale(locale, strings)
    if GetLocale() ~= locale then
        return
    end
    for key, value in pairs(strings) do
        L[key] = value
    end
end
