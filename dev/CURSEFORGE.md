# Publishing WritPrice on CurseForge - checklist (author)

## Before uploading
1. Test in game (see "In-game test list" below), English then `/writs lang fr`.
2. Source availability (GPL): attach `WritPrice-<version>-source.zip` to each release as an
   "additional file" (Files tab > click the uploaded file > "Upload Additional Files").
   A public repository (GitHub or similar) is optional; if you create one, add `## X-Website: <url>` to the .toc.
3. Fill in the placeholders, then rebuild the zip:
   - `WritPrice.toc`: add `## ` in front of `X-Curse-Project-ID` once the project exists.
   - Donations (optional, later): set "Donation method" in the CurseForge project settings; never inside the addon.
4. Run the checks (Lua 5.1, like the game: `pip install lupa`) and build the zip:
   ```
   python3 dev/tools/build_locales.py
   python3 dev/tools/gen_recipes.py <dir with alc/ and pfq/ checkouts> Recipes.lua   # only to refresh recipe data
   python3 dev/tests/check_locales.py
   python3 dev/tests/run_tests.py --locale enUS
   python3 dev/tests/run_tests.py --locale frFR
   python3 dev/tests/run_tests.py --locale enUS --legacy-options
   python3 dev/build_zip.py
   ```

## Creating the project (CurseForge author dashboard)
- Game: World of Warcraft, class: Addons, name: WritPrice.
- Logo: original PNG, at least 400x400 (no Blizzard artwork).
- Summary (English): "Ranks Craftsman's Writs by cost per reputation point from a targeted auction house scan."
- Categories: main "Auction & Economy"; others "Professions", "Quests & Leveling", "Tooltip" (check the exact labels in the form).
- License: GNU General Public License version 2 (GPLv2).
- Description: paste `README.md` (it renders as Markdown). Keep the donation line short and at the bottom.
- Links: Issues (optional). Source: the source zip attached to each file.
- Project settings > "Donation method": add your provider (the in-game add-on must never ask for donations - Blizzard UI Add-On Development Policy).
- Optional: join the CurseForge rewards program (author dashboard).

## Uploading a file
- Upload `WritPrice-<version>.zip`, release type "Release".
- Game version flavor: **Forever**, version **1.60.1** only (not Classic Era, not Retail).
- Changelog: paste the latest section of `CHANGELOG.md`.

## In-game test list
- English client, then `/writs lang fr`: accents readable, nothing cut off.
- First launch with the saved variables deleted: one welcome line, only once.
- Empty window, full scan, stop during a scan, closing the auction house during a scan.
- Next to Auctionator; clicking a row while on an Auctionator tab.
- Columns and Professions menus, clicking outside to close, Escape.
- UI scale at minimum and maximum; `/writs scale 80`; `/writs reset`.
- Writ tooltip in bags and at the auction house.
- Accept a writ, get the item (ready), turn it in (turned in).
- Goal and quantity popups.
- Addon compartment entry and the icon in the addon list.
- Options > AddOns > WritPrice: every setting applies at once; Okay / Cancel / Defaults cause no error; no "action blocked" after combat (`/console taintLog 1`).
- Minimap icon: rendering, drag all around, position kept after /reload, lock, hide / `/writs minimap`; with a square-minimap addon.
- No Lua error (BugSack) and no "action blocked" message after combat.
- `/writs debug api`.

## Merging player exports (before each release)
1. Save each export posted by players (comments, issues, Discord) as a `.txt` file in `dev/data/exports/` (one or several exports per file; surrounding text is ignored).
2. `python3 dev/tools/merge_exports.py dev/data/exports --dry-run` to read the report, then without `--dry-run` to update `Writs.lua` and `Dests.lua` (report in `dev/data/merge_report.md`).
3. Check disagreements listed in the report, run the tests, update `CHANGELOG.md`, build the zip.
4. Credit contributors in `CREDITS.md` if they wish (exports contain no names).
