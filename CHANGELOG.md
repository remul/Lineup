# Changelog

## 1.10.0

- **Import single teams without the editor**: a new option (Teams) saves a single imported team
  right away instead of opening it in the team editor first.
- Importing a team whose name you already have asks whether to **replace** it or **keep both**.
- Team names are unique: a name that's taken gets a number ("Name (2)"), and the team editor says
  when another team already has the name.
- Bulk imports replace each team you have at most once; a name repeated in the import is added
  with a number instead of overwriting the team imported just before. The confirmation says how
  many names get a number.

## 1.9.0

- **Saved data starts fresh**: Lineup's saved variables are renamed (`LineupPetBattlesDB`,
  `LineupPetBattlesCharDB`) so they can't clash with another addon called Lineup. Teams, groups,
  hidden pets and settings from earlier versions aren't carried over; export your teams with an
  older version first if you want to keep them.
- **Duplicates** and **Level 25 copies** filters in the journal's Filter menu: show only species
  you have more than once, or by how many you have at level 25 (at least one, at least two, none).
- **Hidden** badge on hidden pets when the Hidden pets filter shows them.
- **Drag pets from the Pet Journal** (its list or loadout) onto a slot in the team editor; dropping
  a pet that's already in the team swaps the two slots.
- The Revive Battle Pets glow is on the pet toolbar's button (it never showed before).
- Faster: owned pets are read without changing the journal's filters, the new filters and team
  search keep their results, imports find your pets by species, and Statistics does less work per
  redraw.
- Fixed: the Open Options button caused a blocked-action error in combat; it's disabled then.
- Fixed: the pet toolbar could be moved in combat, and could hide other addons' buttons under it.

## 1.8.0

- **Hide pets** in the Pet Journal: "Hide" in a pet's right-click menu takes it out of the list,
  "Unhide" brings it back. Pets you haven't collected can be hidden too (by species). A new
  **Hidden pets** filter in the journal's Filter menu hides them (the default), shows only them
  or shows all pets.
- **Lineup in Blizzard's Options** (AddOns tab): the settings moved there from the Settings tab,
  grouped under Teams and Development. The Settings tab has an Open Options button.
- **Language option** under Development: switch Lineup's language (to test translations),
  applied after a reload.
- **Danger zone** in the options: show all hidden pets again, delete all teams, all groups, or
  both. Each one asks first.
- The **Ungrouped** header shows even when there are no groups.
- Statistics: less space above the overview and above the quality bar, a smaller, centred
  quality legend, and the source bars sit a bit higher, so sources fit better.
- A roadmap of planned features (ROADMAP.md).

## 1.7.0

- **French, Italian and Russian** translations.
- **Custom order for the leveling queue**: a new "Custom" sort where you drag pets into your own
  order, or move them with the arrows. Leveling slots use that order. It's kept while you use
  another sort; pets that reach level 25 drop out of it.
- **Drag and drop** in the Sort Groups window as well. Rows that can be dragged have a grip.
- The Sort Groups window shows groups as cards like the group headers in the Lineup window, with
  their team count.
- Shorter README.
- Fixed: a German message read "der Familie beliebig" for random slots without a family.

## 1.6.0

- **Breed badges** in the Pet Journal: each battle pet's breed (e.g. P/S) below its name, in the
  list and on the three loadout slots.
- **Badges on team cards**: the family, the target ("vs. ...", green while targeted) and the
  script's state are coloured badges; "No target" and "No script" are muted ones.
- The **Current Team** section has a header: the team's group icon, its name and its group.
  "changed" and the script's state ("Script ready", ...) are badges too.
- **Level filter** in the journal's Filter menu: level 25, below 25, 20–24, 15–19, 10–14, 1–9
  or 1 (instead of "Level 25 only").
- Statistics: the quality legend is a row of badges, in colours shared with the quality bar.
- Editors show what's missing (e.g. "A team needs a name") below the field instead of in chat.
- Team cards are a bit taller; names and pet icons line up, with the loaded team's check mark
  after its name. Ready scripts are shown in the Dragonkin family's green.
- Lighter grey for hints and muted text in all Lineup windows.
- Fixed: errors from the pet toolbar's cooldowns in combat.
- Fixed: hiding the Lineup window in combat was blocked; the Hide / Show button is disabled in
  combat.
- Fixed: the Sort Groups hint was cut off.

## 1.5.0

- **Statistics tab** in the Lineup window: your pet collection (formerly the Pet Collection
  panel behind the magnifying glass) with a headline and progress bar, the overview and quality
  bar, and bars per **family** or **source** chosen from a dropdown.
- **Hide / Show button** next to the Pet Journal's Find Battle button hides the Lineup window,
  remembered across sessions.
- **Notes button** on team cards with notes, below the gear: pops the notes out.
- Other windows (Character, Spellbook, ...) now open beside the Lineup window instead of over it.
- The Target and Current Team sections have the Pet Journal's pet card background.
- No trailing dots on one-line labels; easier to read "No script" and "Empty slot".

## 1.4.0

- **Pet Collection**: a magnifying glass next to the Pet Journal's "Total Pets" shows how many pets
  you have; click it for details. An overview (collected, level 25 and rare pets, unique and in
  total, duplicates, average battle pet level, pets in your teams, a quality bar) and bars per
  **family** or per **source** for a number of your choice, e.g. percent collected.
- **Delete groups** from a group's gear menu, and optionally all of its teams along with it.
- **Expansion logos** in the group icon picker, right after the pet families.
- The Lineup window's sections (Target, Current Team, team list) and the Leveling Queue and
  Settings tabs are sunk into the window like the Pet Journal's insets; the current pets are cards
  like the teams. The Leveling Queue's sort and options are radio buttons and checkboxes.
- Even spacing on both sides in every Lineup window, and a little room above the first and below
  the last group.
- Clicks on the Lineup window no longer reach the world behind it (e.g. an NPC).
- Shorter, clearer tooltips and texts.

## 1.3.1

- Teams are shown as **rounded cards** with a little space between them; the loaded team has a
  gold outline.

## 1.3.0

- **Breeds** (e.g. P/S), worked out from each pet's stats with Blizzard's own battle pet data, no
  other addon needed. Shown in the pet picker, the Current Team section and team tooltips; at
  low levels, where several breeds can fit, as "P/S or S/S".
- **Imports use breeds**: the breed a team string asks for is preferred (unless your pet of that
  breed has a lower level) and remembered; exports write breeds too.
- **Import preview**: pasting a single team shows what you'll get before importing – missing
  pets, low levels, wrong breeds, abilities a pet can't use yet and script problems, one line per
  slot – or "Ready to import". Bulk imports list one line per team that needs attention.
- **Pet Journal filters**: Blizzard's Filter menu gets **Strong vs.**, **Tough vs.**, **Breed**
  and **Level 25 only**. A button at the end of the family row shows active ones and clears them.
- **Breed filter** in the pet picker as well.
- Windows (team editor, import, export, groups) open in the middle of the screen, and reopen
  where you dragged them.

## 1.2.0

- **Pet picker** in the team editor: click a pet icon to choose a pet without the Pet Journal.
  Search by pet, species or ability name; filter by family, **Strong vs.** and **Tough vs.** an
  enemy family, and level 25. Each pet shows its six abilities (hover for Blizzard's ability
  tooltip); abilities strong against the chosen family are marked. Buttons set a **leveling**
  slot, a **random level 25 pet** (any family or one family) or an **empty** slot.
- **Auto-load** (Settings, off by default): targeting a tamer or wild pet with exactly one team
  loads that team.
- The Lineup window is a little wider; "Current" is now **Current Team**, with health shown as
  ♥ 1441 / 1441 (a skull for dead pets) and "changed" as its own label.
- Dividers in Blizzard's style, also between the pet toolbar's button groups.
- The Settings tab shows the version number, easier to read.
- Lineup is listed under **Pet Battles** in the in-game AddOns list.
- Team editor: more space between the pet icons; the ability numbers only show for slots with a
  specific pet.

## 1.1.1

- **Settings tab** redesigned to match the Teams tab: sections with header lines for Settings,
  Import & Export (Import Rematch Teams and Export All Teams side by side), Overview and Commands.

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
