# Changelog

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
