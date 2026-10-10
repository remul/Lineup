# Roadmap

Ideas, planned features, improvements and known issues for Lineup. Move an entry to
[CHANGELOG.md](CHANGELOG.md) when it ships, and delete it here.

## New features

- Drag team cards between groups in the Lineup window's team list.
- Add pets to the leveling queue by hand (e.g. from the pet picker), not only through its options.
- Drag and drop for other lists, e.g. pets into team slots.

## Improvements

- `/lineup` and the addon compartment button could also show the Lineup window when it's hidden.
- A quick collection summary on hover (it was on the old Pet Collection button, which the
  Statistics tab replaced).
- Remove the trailing period from one-line tooltips too, like the UI labels.
- Russian plural forms: counts use the "Питомцев: %d" form for now.

## To check in game

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
