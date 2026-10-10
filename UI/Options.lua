local _, ns = ...
local L = ns.L

-- Lineup's category in Blizzard's Options (AddOns tab), with the settings in ns.db, grouped under
-- section headers.
local Options = {}
ns.Options = Options

-- Each language by its own name, for the Language dropdown.
local LANGUAGE_NAMES = {
    enUS = "English",
    deDE = "Deutsch",
    frFR = "Français",
    itIT = "Italiano",
    ruRU = "Русский",
}

local category, layout
-- Settings by key in ns.db.
local settings = {}

local function Register(key, varType, label, default)
    local setting = Settings.RegisterAddOnSetting(category, "Lineup_" .. key, key, ns.db, varType, label, default)
    settings[key] = setting
    return setting
end

local function AddCheckbox(key, label, tooltip)
    Settings.CreateCheckbox(category, Register(key, Settings.VarType.Boolean, label, false), tooltip)
end

local function AddSection(name)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
end

local function AddButton(name, buttonText, onClick, tooltip)
    layout:AddInitializer(CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, true))
end

-- A Danger zone button: asks first (prompt formatted with the counts), or says there's nothing to do.
local function AddDangerButton(name, buttonText, tooltip, getCounts, prompt, emptyMessage, run)
    AddButton(name, buttonText, function()
        local counts = { getCounts() }
        if counts[1] == 0 then
            ns:Print(emptyMessage)
            return
        end
        ns.Dialogs.Confirm(format(prompt, unpack(counts)), function()
            run()
            ns.TeamsPanel:Refresh()
        end)
    end, tooltip)
end

local function GetLanguageOptions()
    local container = Settings.CreateControlTextContainer()
    container:Add("", L["Game language"])
    for _, locale in ipairs(ns.LOCALES) do
        container:Add(locale, LANGUAGE_NAMES[locale] or locale)
    end
    return container:GetData()
end

-- Called once ns.db is loaded.
function Options:Setup()
    category, layout = Settings.RegisterVerticalLayoutCategory(ns.TITLE)
    AddSection(L["Teams"])
    AddCheckbox("autoLoadTargetTeam", L["Load a target's team automatically"],
        L["Targeting a tamer or wild pet with exactly one team loads that team."])
    AddCheckbox("importWithoutEditor", L["Import single teams without the editor"],
        L["A single imported team is saved right away, instead of opening in the team editor to review first."])

    AddSection(L["Development"])
    AddCheckbox("debug", L["Debug messages in chat"], L["Shows team loading details in chat, for troubleshooting."])
    -- The language for Lineup only; its texts are set when the UI loads, so it needs a reload.
    Settings.CreateDropdown(category, Register("locale", Settings.VarType.String, L["Language"], ""),
        GetLanguageOptions, L["Lineup's language, for testing translations. Applies after reloading the interface."])
    Settings.SetOnValueChangedCallback("Lineup_locale", function()
        ns.Dialogs.Confirm(L["Reload the interface to switch Lineup's language?"], ReloadUI)
    end)

    -- Like GitHub's: actions that can't be undone, each confirmed first.
    AddSection(RED_FONT_COLOR:WrapTextInColorCode(L["Danger zone"]))
    AddDangerButton(L["Hidden pets"], L["Show All"], L["Shows every pet you hid in the Pet Journal again."],
        function()
            return ns.JournalFilters:CountHidden()
        end, L["Show all %d hidden pets in the Pet Journal again?"], L["No pets are hidden."], function()
            ns.JournalFilters:ResetHidden()
        end)
    AddDangerButton(L["All teams"], DELETE, L["Deletes every team. The groups stay, empty."],
        function()
            return #ns.Teams:GetAll()
        end, L["Delete all teams (%d)? This can't be undone."], L["There are no teams."], function()
            ns.Teams:DeleteAll()
        end)
    AddDangerButton(L["All groups"], DELETE, L["Deletes every group. Their teams become ungrouped."],
        function()
            return #ns.Teams:GetGroups()
        end, L["Delete all groups (%d)? Their teams become ungrouped."], L["There are no groups."], function()
            ns.Teams:DeleteAllGroups(false)
        end)
    AddDangerButton(L["All groups and teams"], DELETE, L["Deletes every group and every team."],
        function()
            local numGroups, numTeams = #ns.Teams:GetGroups(), #ns.Teams:GetAll()
            -- Nothing to do only when both are empty.
            return numGroups + numTeams, numGroups, numTeams
        end, L["Delete all groups (%2$d) and teams (%3$d)? This can't be undone."], L["There are no groups or teams."],
        function()
            ns.Teams:DeleteAllGroups(true)
            ns.Teams:DeleteAll()
        end)

    Settings.RegisterAddOnCategory(category)
end

-- Changes a setting so an open Options panel shows it too.
function Options:Set(key, value)
    settings[key]:SetValue(value)
end

-- Blizzard's Options can't be opened in combat.
function Options:Open()
    if InCombatLockdown() then
        return
    end
    Settings.OpenToCategory(category:GetID())
end
