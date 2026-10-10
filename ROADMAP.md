# Roadmap

Ideas, planned features, improvements and known issues for Lineup. Move an entry to
[CHANGELOG.md](CHANGELOG.md) when it ships, and delete it here. Within each section, the most
useful entries come first.

## New features

### Teams

- **Win/loss record per team**: count wins and losses when a battle ends with a team loaded
  (`PET_BATTLE_FINAL_ROUND`), show them on the team card and in the editor, and sort or search by
  them. Rematch has this, so it would also come along on import from Rematch.
- **Load the target's team with a key binding** (Bindings.xml): one key to load the team for the
  tamer you're targeting, or cycle through its teams when it has several.
- **Drag team cards between groups** in the Lineup window's team list.
- **Undo for deleting**: keep the last deleted team or group (and the last Danger zone action)
  until the next reload, with an Undo button in the chat message.

### Pet Journal

- **Hide a whole species**, collected copies included, not just one pet or an uncollected entry.

### Leveling queue

- **Add pets by hand** (e.g. from the pet picker or the journal's right-click menu), not only
  through the queue's options.
- **Drag and drop** for other lists, e.g. pets from the pet picker into team slots.

### Options

Pet Journal toggles for what Lineup adds there, for players who only want part of it:

- breed badges in the list and on the battle slots
- the family filter row
- the pet toolbar
- the glow on Revive Battle Pets while a pet is hurt
- showing the Lineup window with the journal

For teams: ask before auto-loading a team over unsaved changes, auto-load for tamers only (not wild
pets), and a chat line when a team loads.

## Improvements

- `/lineup` and the addon compartment button could also show the Lineup window when it's hidden.
- Jumping to a pet from Lineup (e.g. from a team) can't select it while Lineup's journal filters
  (Strong vs., Tough vs., Breed, Level, Hidden pets) leave it out; clear them first like the
  journal's own filters.
- A quick collection summary on hover (it was on the old Pet Collection button, which the
  Statistics tab replaced).
- The Settings tab holds no settings any more: rename it (e.g. "About") or move Import & Export
  onto the Teams tab.
- Remove the trailing period from one-line tooltips too, like the UI labels.
- Russian plural forms: counts use the "Питомцев: %d" form or brackets ("(%d)") for now.
- Released or caged pets stay in the hidden pets list; drop them when the journal no longer has
  them.

## To check in game

1.8.0:

- Hide / Unhide on an uncollected pet's icon (it's disabled, so it only gets mouse ups); on its
  name it always works.
- The Hidden pets filter's three choices, the clear button's text, and Reset.
- Switching the language in Options, after the reload: tabs, filter menus, queue sorts and
  statistics all switch, not only some texts.
- The Danger zone buttons and their confirmations; deleting all teams while one is loaded.
- Importing the 10 to 500 team test files (`scratch/`): how long the import and the team list take.

Next release:

- The Duplicates and Level 25 copies filters, alone and together with Blizzard's filters and
  search; how fast the list updates with a large collection.
- The "Hidden" badge on hidden pets (Only hidden pets, All pets): it doesn't cover long names or
  the level, and goes away on Unhide.
- Dragging a pet from the journal's list or loadout onto a slot in the team editor; dropping one
  that's already in another slot swaps the two.
- The Revive glow on the toolbar's own button (Blizzard's, which it used to sit on, is hidden).
- Statistics and the leveling queue after the roster change (owned pets now come from
  `GetOwnedPetIDs`; only the species list still changes the journal's filters, once per session).
- No blocked-action errors with the journal open in combat; other addons' widgets near the toolbar
  stay visible.

Older:

- Badges: text and descenders ("y", "g") fit; the quality badges on the Statistics tab fit in one
  row in every language.
- Breed badge on the journal's battle slots doesn't crowd the health bar.
- Leveling queue: a click on a row still selects the pet when drag and drop is on; the drop line
  lines up with the rows.
- Longer French and Russian labels (tabs, buttons, badges) fit.
- Translations read well to native speakers (French, Italian, Russian).

## Known issues

- Making room for the Lineup window next to the journal (the journal's `extraWidth` for Blizzard's
  panel manager) touches protected UI. It waits for combat to end, but if Lineup is ever blamed for
  blocked actions in combat with other windows (Character, Talents, Spellbook), this is the likely
  cause; the fallback is to drop the feature.
- The journal's pet count (Blizzard's) still counts hidden pets.
- Texts must be translated where they're shown, never while a file loads: the Language option is
  only known once saved settings load, so anything translated earlier stays in the game's language.
