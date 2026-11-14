# WritPrice

**Find the cheapest Craftsman's Writs for Azeroth Commerce Authority reputation in WoW Forever.**

WritPrice scans the auction house for every Craftsman's Writ and the item each one asks for, then ranks the writs by **cost per reputation point**. It tells you which writs to buy today, what they cost in total, whether you could craft the item yourself, and where to turn each writ in.

## Features

- **Fast full scan**: one request reads every auction in a few seconds (allowed by the server about every 15 minutes), with an automatic fallback to a **targeted scan** (writs, then the requested items and reagents of your filters). One click from the WritPrice window; no automatic buying, ever.
- **Auctionator-friendly**: if Auctionator is installed, prices it scanned today are reused, so most items need no search at all.
- **Ranking by cost per reputation point**: writ price + requested item x quantity, for Journeyman (75 rep), Expert (125) and Artisan (200) writs.
- **Filters**: rank buttons and a profession check list (Alchemy, Blacksmithing, Engineering, Leatherworking, Tailoring, Other).
- **Reputation goal**: type a number, or 0 to aim for the end of your current reputation level; WritPrice shows the cheapest set of writs that reaches it today.
- **Crafting**: crafting cost from the reagent prices, and a Recipe column telling you if you know the recipe, can learn it from a trainer, or need a recipe item (with where it comes from).
- **Quests in progress**: writs you already accepted come first, cost only the missing items, and show "ready" when you have them; pending reputation and your current standing are shown at the bottom.
- **Where to turn in**: NPC, place and coordinates for most writs, replaced by the in-game quest text once you accept a writ.
- **Coin Pouch rewards**: the money from each writ's Coin Pouch is recorded (with the writ and where it was turned in) and its median is deducted from the cost, so you see the **net** cost per point. Samples are shared with other WritPrice users in your guild and group, and everyone's data improves.
- **Writ tooltips**: rank, prices, total and cost per point directly on the writ's tooltip.
- **Settings page** (Options > AddOns > WritPrice) and a **minimap icon** (left-click: window, right-click: settings, drag to move).
- **English and French**, hideable columns, automatic window scale, works next to Auctionator.

## Getting started

1. Open the auction house and click the **WritPrice** button above it (or the minimap icon, or type `/writs`).
2. Pick a rank (and professions), then click **Scan**.
3. Read the ranking. Click an item column to search for the item on the auction house, anywhere else on the row to search for the writ; right-click to set a quantity.

## Commands

| Command | What it does |
|---|---|
| `/writs` | Open or close the window |
| `/writs scan [full\|targeted]`, `/writs stop` | Start or stop a scan (auction house open) |
| `/writs goal <points>` | Reputation goal (0 = next reputation level) |
| `/writs prof <name\|all\|none>` | Toggle a profession in the filter |
| `/writs set <qty>` | Quantity of the last hovered writ (0 = default) |
| `/writs craft` | Include reagents in the scan or not |
| `/writs cols`, `/writs scale <50-150>`, `/writs reset` | Window layout |
| `/writs lang <en\|fr\|auto>` | Language |
| `/writs options`, `/writs minimap` | Settings page, show or hide the minimap icon |
| `/writs pouch` | Coin Pouch values per rank and latest samples |
| `/writs export`, `/writs import` | Share what your addon learned (turn-in places, quantities, pouches) |
| `/writs about`, `/writs help` | Version, credits, help |

## Help improve the data

Type `/writs export`, press Ctrl+C and paste the text in a comment on the project page (or a GitHub issue). It only contains what your addon learned in game: where writs are turned in, requested quantities, ranks and your Coin Pouch values; no character, realm or money information. Each release merges these exports, so the turn-in list and pouch values get better for everyone. `/writs import` lets you use a friend's export right away.

## Known limits

- **For now WritPrice needs the game client in English.** WoW Forever also exists in other languages (French, German…), but writs, items, Coin Pouches and quest texts are recognized by their English names, so the auction house scan finds nothing on another client. Support for other game languages is planned for the next version. The addon's own interface is available in English and French.
- Recipes come from Classic data (AtlasLootClassic, pfQuest): WoW Forever may differ for some of them.
- Turn-in places and the writ list come from community guides and are not verified: the quest text in game always wins.
- Prices are kept per realm and faction. Classic Era is not supported.

## Credits and license

GPL-2.0-only. Recipe data derived from AtlasLootClassic (GPL v2) and pfQuest (MIT); writ hints from community guides. See `CREDITS.md`.

---

## Français

**Trouve les Craftsman's Writs les moins chers pour la réputation de l'Azeroth Commerce Authority dans WoW Forever.**

WritPrice scanne l'hôtel des ventes pour tous les Craftsman's Writs et l'objet que chacun demande, puis classe les writs par **coût par point de réputation**. Il indique quels writs acheter aujourd'hui, leur coût total, si tu peux fabriquer l'objet toi-même et où rendre chaque writ.

- Scan complet rapide de l'hôtel des ventes (quelques secondes, autorisé environ toutes les 15 min), sinon scan ciblé ; aucun achat automatique.
- Compatible Auctionator : ses prix du jour sont repris, la plupart des objets n'ont plus besoin d'être recherchés.
- Classement par coût par point (writ + objet x quantité), filtres par rang et par métier.
- Objectif de réputation réglable (0 = fin du palier actuel) et plan « les writs les moins chers ».
- Coût de fabrication et colonne Recette (connue / maître / patron, avec sa source).
- Writs déjà acceptés en tête de liste, prêts à rendre, réputation en attente.
- PNJ, lieu et coordonnées de rendu, remplacés par le texte de la quête dès qu'elle est acceptée.
- Page de réglages (Options > AddOns > WritPrice) et icône sur la minicarte (clic gauche : fenêtre, clic droit : réglages).
- Bourses de récompense enregistrées à chaque rendu (writ, PNJ, zone), médiane déduite du coût, partage avec la guilde et le groupe.
- Interface en anglais ou en français : `/writs lang fr`.

**Important : pour l'instant, le jeu lui-même doit être en anglais.** Les writs, les objets, les bourses et les textes de quête sont reconnus par leur nom anglais : avec le jeu en français, le scan de l'hôtel des ventes ne trouve rien. La prise en charge du jeu en français est prévue pour la prochaine version.

Aide à améliorer les données : tape `/writs export`, copie (Ctrl+C) et colle le texte en commentaire sur la page du projet. Il ne contient que ce que l'addon a appris en jeu (lieux de rendu, quantités, rangs, bourses), rien de personnel.

Démarrage : ouvre l'hôtel des ventes, clique sur le bouton **WritPrice**, choisis un rang puis clique sur **Scan**. Aide : `/writs help`.
