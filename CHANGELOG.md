# Changelog

## 1.1.0

- **One Lineup window** instead of the Target and Teams windows, split into sections:
  - **Target**: the targeted tamer or wild pet with its teams and quick Load / Save.
  - **Current**: the loaded team and the three pets in your journal with names and health bars
    (click a pet to show it in the journal), whether the team's script will run, and a warning
    for dead or badly hurt pets.
  - **Teams**: the team list, with New Team, New Group and Import on the section header.

  The Leveling Queue and Settings tabs (formerly "Lineup") use the whole window.
- **Autobattle with scripts**: with [Pet Battle Scripts](https://www.curseforge.com/wow/addons/td-battle-pet-script)
  (tdBattlePetScript) installed, the loaded Lineup team's script runs from its Auto button in
  battle. Scripts stay with the team; saving in Pet Battle Scripts' editor updates the team.
- **Script checks**: scripts are checked with Pet Battle Scripts' own parser (when installed) and
  against the team: abilities the script uses but no pet has selected are flagged. Team rows show
  "Script", "Script · check abilities" or "Script · error"; the tooltip lists every problem.
- **Team editor**: a bigger script status with an icon, **Select Script Abilities** to pick the
  abilities a script needs, "Save with Errors" / "Save with Warnings", and the picked abilities
  under each pet (e.g. 1/1/2) – hover for their names, click to change them. Saving the loaded
  team also applies its abilities in the journal.
- **Pet health**: dead and hurt pets are marked, a warning shows after loading a team, and
  Blizzard's Revive Battle Pets button glows while a pet is hurt and the spell is ready.
- **Export** teams as Rematch team strings, with notes and scripts: Export Team (team menu),
  Export Group (group menu) and Export All Teams (Settings tab). Paste them into Import in Lineup
  or Rematch.

## 1.0.0

First release.

- **Teams** in a window next to Blizzard's Pet Journal: save the three slotted pets with their
  abilities, load a team with one click, and see which team is loaded. Changing a pet or ability
  shows "changed" with **Save** and **Revert**.
- **Groups** with icons, collapsible, in your own order (Sort Groups window, A–Z); search teams and
  groups by name or target; expand or collapse all groups at once.
- **Target window**: the targeted tamer or wild pet with its teams and quick Load / Save.
- **Import** Rematch team strings, one or many at once (e.g. Xu-Fu's Pet Guides): target, pets,
  abilities, notes and pet battle scripts; random-family and leveling slots with their
  preferences. Import all teams straight from Rematch, including tdBattlePetScript scripts.
- **Leveling queue**, filled automatically, sortable, optionally with duplicates and species you
  already have at 25; click a pet to show it in the journal.
- **Family filter** row above the journal's pet list.
- **Pet toolbar**: Revive Battle Pets, Battle Pet Bandage, Safari Hat, pet treats and Summon Random
  Favorite Pet.
- **Notes window** to follow a team's strategy during battles.
- Works alongside Rematch: Lineup hides while Rematch replaces the Pet Journal, and loading a
  Lineup team releases Rematch's team so its leveling queue doesn't swap your pets.
- Languages: English and German.
