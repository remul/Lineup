<p align="center"><img src="Media/Logo.png" width="200" alt="Lineup"></p>

# Lineup

A pet battle team manager for World of Warcraft (Retail) that works inside Blizzard's Pet Journal.

Lineup adds a window next to the Pet Journal with your current target, the team you have loaded and
all your saved teams. The journal itself keeps working as before; Lineup adds a few things to it.

## Features

### Teams

- Save the three pets in your journal, with their abilities, as a team. Load a team with one click.
- Give a team a target NPC, notes and a [tdBattlePetScript](https://www.curseforge.com/wow/addons/td-battle-pet-script)
  script.
- Put teams in groups. Groups can have an icon, can be collapsed and sorted, and can be deleted with
  or without their teams.
- Search teams and groups by name or target.
- When you change a pet or an ability of the loaded team, you can save the change or go back to the
  saved team.

### Lineup window

The window next to the journal has four tabs:

- **Teams** – your target (the tamer or wild pet you have targeted) and its teams, the loaded team
  with its pets and their health, and the list of all teams.
- **Leveling Queue** – your battle pets below level 25. Teams can have leveling slots, which take
  the next pet from this queue when the team is loaded.
- **Statistics** – how many pets you have collected, how many are level 25 or rare, and how your
  collection splits by family or source.
- **Settings** – options, import and export.

A Hide / Show button next to the journal's Find Battle button hides or shows the window.

### Team editor

- Set the name, group, target, notes and script.
- Choose pets with a pet picker: search by name, species or ability, and filter by family or by
  strong / tough against an enemy family.
- A slot can also be a leveling pet, a random level 25 pet, or empty.
- Choose each pet's abilities.

### In the Pet Journal

- A row of family icons above the pet list, to filter by family.
- More options in the journal's Filter menu: **Strong vs.**, **Tough vs.**, **Breed** and **Level**.
- Each pet's breed (e.g. P/S) as a badge below its name, in the list and on the three battle slots.
- A toolbar with Revive Battle Pets, Battle Pet Bandage, Safari Hat, pet treats and Summon Random
  Favorite Pet.
- Blizzard's Revive Battle Pets button glows when a pet in your loadout is hurt or dead.

### Scripts

With [Pet Battle Scripts (tdBattlePetScript)](https://www.curseforge.com/wow/addons/td-battle-pet-script)
installed, the loaded team's script runs from the Auto button in battle. Lineup checks each script
and shows when it uses an ability the team doesn't have selected; it can select those abilities for
you.

### Import and export

- Paste one or more Rematch team strings, e.g. from [Xu-Fu's Pet Guides](https://www.wow-petguide.com).
  Pets, abilities, breeds, targets, notes and scripts are imported.
- If Rematch is installed, you can import all its teams and groups at once.
- Export a team, a group or everything as Rematch team strings, with notes and scripts.

### Other

- Breeds are worked out from each pet's stats with Blizzard's battle pet data. Imports pick your pet
  of the breed a team asks for, and tell you when you don't have it.
- A team's notes can be opened in a separate window to read during a battle.

## Installation

Copy the `Lineup_PetBattles` folder into `World of Warcraft/_retail_/Interface/AddOns/` and restart
the game.

Open the Pet Journal (`Shift+P`, Pets tab) or type `/lineup`.

## Commands

| Command         | Description                   |
|-----------------|-------------------------------|
| `/lineup`       | Open the Pet Journal          |
| `/lineup debug` | Turn debug messages on or off |

## Languages

Lineup uses the language of your game client. English, German, French, Italian and Russian are
available.

Translations are in `Locales/`. To add a language, copy `Locales/deDE.lua`, change the locale code
(e.g. `frFR`), translate the text on the right of each line and add the file to
`Lineup_PetBattles.toc`.

## Development

Lineup is Lua and XML with no build step. Link the repository into the AddOns folder and use
`/reload` in game to load changes:

```sh
ln -s "$(pwd)" "/Applications/World of Warcraft/_retail_/Interface/AddOns/Lineup_PetBattles"
```

Breed data is generated into `Data/BreedData.lua` from Blizzard's battle pet tables. After a patch
that adds pets, run `python3 tools/generate_breed_data.py` (it downloads the current tables from
[wago.tools](https://wago.tools)) and commit the result.

Textures in `Media/` that are drawn in code (rounded cards, badges, the paw) come from the other
scripts in `tools/`.

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager) (see
`.pkgmeta`) when a version tag is pushed. Before tagging, set `## Version` in
`Lineup_PetBattles.toc` to the same version; it's shown on the Settings tab. Changes are listed in
[CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
