# WritPrice - credits and third-party notices

WritPrice is licensed under the GNU General Public License, version 2 only (see `LICENSE`).
World of Warcraft is a trademark of Blizzard Entertainment, Inc. WritPrice is not affiliated with or endorsed by Blizzard Entertainment.

## AtlasLootClassic - GPL v2

- Source: https://github.com/Hoizame/AtlasLootClassic (authors: Lag, Daviesh and contributors), license GPL v2.
- Files used: `AtlasLootClassic/Data/Profession.lua` (crafting spells, reagents, skill levels) and `AtlasLootClassic/Data/Recipe.lua` (recipe items).
- Transformation: converted by `dev/tools/gen_recipes.py` into the name-keyed tables of `Recipes.lua` (crafted item -> reagents, required skill, trainer or recipe item).
- Complete source (including the generator and the test bench): the `WritPrice-<version>-source.zip` file attached to each release on the project page.

## pfQuest - MIT

- Source: https://github.com/shagu/pfQuest
- Files used: `db/enUS/items.lua`, `db/enUS/units.lua` (English item and NPC names) and `db/items.lua` (vendors and drops), to name items and recipe sources in `Recipes.lua`.

```
MIT License

Copyright (c) 2017-2021 Eric Mauser (Shagu)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Community writ guides (factual game data)

The writ list (`Writs.lua`: rank, profession, quantity) and the turn-in hints (`Dests.lua`: NPC, place, coordinates) are factual game information gathered in November 2026 from community guides:

- wow.gg - https://wow.gg/guides/merchants-favor
- bindonforever.com - quest pages (data marked by the site as QuestieDB data, not verified in game)
- conquestcapped.com - https://conquestcapped.com/guides/wow-forever/wow-forever-craftsmans-writs/
- foreverchanges.pro

No text from these sites is reproduced. These are unverified hints: in game, the quest text always wins and replaces them as soon as a writ is accepted. If you own one of these sources and want an entry removed, open an issue on the project page and it will be removed.

## Players' exports

Turn-in places, quantities and Coin Pouch values are also merged from `/writs export` texts sent by players. These texts contain no personal data. Thanks to everyone who contributes.
