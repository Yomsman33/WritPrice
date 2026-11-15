# Changelog

## Unreleased

- Game clients in other languages than English (beta): items and writs are matched by item ID and shown in the game's language, the auction house is searched with the translated names, writ names are learned from a full scan, and the quest log, writ tooltips and known recipes are read in the game's language.
- `/writs export` on an English client now includes writ, Coin Pouch and faction IDs (merged into the next release for other languages); `/writs import` accepts them.
- `/writs debug api` shows the game language, how many names are translated and the writ faction found.
- Built-in IDs of 148 writs (from a player export), so other game languages find them without a full scan first.
- Horde: Durotar Supply and Logistics is recognized like the Azeroth Commerce Authority (standing, reputation goal).
- Fixed: writ quests only say "the location marked on your map"; 0.1.0 took that for a turn-in place (shown, exported and shared). It is now ignored and cleaned up.
- Documentation: the README wrongly said WoW Forever is English-only.

## 0.1.0 - 2026-11-14

First public beta, for WoW Forever (client 1.60.1). Not yet widely tested in game: please report problems on the project page.

- Auction house scan of Craftsman's Writs, their requested items and recipe reagents: fast full scan (one request, read in slices, allowed by the server about every 15 minutes) with automatic fallback to a targeted scan. Works on the modern and legacy auction house, next to Auctionator.
- Auctionator support (optional): prices it scanned today are reused, its recent prices fill the gaps (marked "A").
- `/writs` window: writs ranked by cost per reputation point, rank and profession filters, reputation goal (number or next reputation level) and "cheapest writs" plan, hideable columns, automatic window scale, legend.
- Crafting cost, recipe status (known / trainer / recipe item and where to get it) and the character's profession levels.
- Writ quests in progress, ready to turn in, pending reputation and current Azeroth Commerce Authority standing.
- Turn-in NPC and zone (built-in hints, in-game quest text, data shared by other players).
- Coin Pouch rewards recorded at each turn-in (with the writ and turn-in place); their median is deducted from the cost (net cost per point).
- Sharing with other WritPrice users in the guild and group (can be turned off); `/writs export` and `/writs import` to share what the addon learned.
- Settings page (Options > AddOns > WritPrice), minimap icon, addon compartment entry, optional LibDataBroker launcher.
- English and French (`/writs lang`).
