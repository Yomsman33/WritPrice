"""Merges players' /writs export texts into the built-in data of the next release.

Usage: python3 dev/tools/merge_exports.py <folder with .txt files> [--dry-run]

Each file may hold one or more exports (anything around them is ignored, so a copied forum post works).
For every writ item the most reported value wins:
  - turn-in places  -> Dests.lua  (check = false once at least 2 exports agree)
  - quantities, ranks -> Writs.lua (new writs are added, profession taken from Recipes.lua)
  - Coin Pouch values -> ns.POUCH_DEFAULT in Writs.lua (median per rank, at least 3 samples)
  - item and faction IDs (English clients) -> Ids.lua, used by clients in other languages
A report is printed and written to dev/data/merge_report.md.
"""
import glob, os, re, statistics, sys
from collections import Counter, defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RANKS = ["Journeyman", "Expert", "Artisan"]
PROF_BY_ID = {2: "Blacksmithing", 3: "Leatherworking", 4: "Alchemy", 8: "Tailoring", 9: "Engineering"}


def checksum(body):
    return "%04x" % (sum(body.encode("utf-8")) % 65536)


def read_exports(folder):
    blocks, bad = [], 0
    for path in sorted(glob.glob(os.path.join(folder, "*.txt"))):
        text = open(path, encoding="utf-8", errors="replace").read().replace("\r", "")
        for m in re.finditer(r"(WPX;[^\n]*(?:\n(?!END;)[^\n]*)*)\nEND;([0-9a-fA-F]+)", text):
            body, ck = m.group(1), m.group(2).lower()
            if checksum(body) != ck:
                bad += 1
                continue
            blocks.append((os.path.basename(path), body))
    return blocks, bad


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def unlua(s):
    return (s or "").replace('\\"', '"').replace("\\\\", "\\")


def parse_dest(text, zone):
    m = re.match(r"^(.+?) at (.+?) in (.+)$", text)
    if m:
        return m.group(1), m.group(2), m.group(3)
    return text, "", zone or ""


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    folder, dry = sys.argv[1], "--dry-run" in sys.argv
    blocks, bad = read_exports(folder)
    dests, qtys, ranks = defaultdict(Counter), defaultdict(Counter), defaultdict(Counter)
    pouch, seen_ids = defaultdict(list), set()
    item_ids, faction_ids = defaultdict(Counter), Counter()
    for _, body in blocks:
        per_export = set()
        for line in body.split("\n"):
            f = line.split(";")
            k = f[0]
            if k == "D" and len(f) >= 4 and f[1] and f[2]:
                key = (f[1], f[2], f[3])
                if key not in per_export:  # one vote per export
                    per_export.add(key)
                    dests[f[1]][(f[2], f[3])] += 1
            elif k == "Q" and len(f) >= 3 and f[2].isdigit():
                qtys[f[1]][int(f[2])] += 1
                if len(f) >= 4 and f[3] in RANKS:
                    ranks[f[1]][f[3]] += 1
            elif k == "R" and len(f) >= 3 and f[2] in RANKS:
                ranks[f[1]][f[2]] += 1
            elif k == "I" and len(f) >= 3 and f[1] and f[2].isdigit() and 0 < int(f[2]) < 10000000:
                if ("I", f[1], f[2]) not in per_export:
                    per_export.add(("I", f[1], f[2]))
                    item_ids[f[1]][int(f[2])] += 1
            elif k == "F" and len(f) >= 2 and f[1].isdigit() and int(f[1]) > 0:
                if ("F", f[1]) not in per_export:
                    per_export.add(("F", f[1]))
                    faction_ids[int(f[1])] += 1
            elif k == "P" and len(f) >= 5 and f[1] in RANKS and f[2].isdigit():
                if f[4] not in seen_ids and 1 <= int(f[2]) <= 200000:
                    seen_ids.add(f[4])
                    pouch[f[1]].append(int(f[2]))

    # current data
    writs_src = open(os.path.join(ROOT, "Writs.lua"), encoding="utf-8").read()
    dests_src = open(os.path.join(ROOT, "Dests.lua"), encoding="utf-8").read()
    recipes = open(os.path.join(ROOT, "Recipes.lua"), encoding="utf-8").read()
    entries = []  # (item, rank, prof, qty)
    for m in re.finditer(r'\["(.+?)"\] = \{ rank = "(\w+)", prof = "(\w+)", qty = (\d+) \}', writs_src):
        entries.append([unlua(m.group(1)), m.group(2), m.group(3), int(m.group(4))])
    known = {e[0]: e for e in entries}
    dest_entries = {}
    for m in re.finditer(r'\["(.+?)"\] = \{ npc = "(.*?)",(?: sub = "(.*?)",)? zone = "(.*?)", xy = "(.*?)", check = (true|false)(, obj = true)? \}', dests_src):
        dest_entries[unlua(m.group(1))] = {"npc": unlua(m.group(2)), "sub": unlua(m.group(3)), "zone": unlua(m.group(4)),
                                           "xy": m.group(5), "check": m.group(6) == "true", "obj": bool(m.group(7))}
    # obj may come before check in the file: catch the other order too
    for m in re.finditer(r'\["(.+?)"\] = \{ npc = "(.*?)", obj = true, sub = "(.*?)", zone = "(.*?)", xy = "(.*?)", check = (true|false) \}', dests_src):
        dest_entries[unlua(m.group(1))] = {"npc": unlua(m.group(2)), "sub": unlua(m.group(3)), "zone": unlua(m.group(4)),
                                           "xy": m.group(5), "check": m.group(6) == "true", "obj": True}
    prof_of = {}
    for m in re.finditer(r'\["(.+?)"\] = \{ p = (\d+),', recipes):
        prof_of[m.group(1)] = PROF_BY_ID.get(int(m.group(2)), "Other")

    report = ["# WritPrice - merge report", "", f"Exports read: {len(blocks)} (damaged: {bad})", ""]
    # writs: quantities, ranks, new items
    changes = []
    for item, c in sorted(qtys.items()):
        q, votes = c.most_common(1)[0]
        if item in known and known[item][3] != q:
            changes.append(f"- quantity {item}: {known[item][3]} -> {q} ({votes} vote(s), all: {dict(c)})")
            known[item][3] = q
    for item, c in sorted(ranks.items()):
        r, votes = c.most_common(1)[0]
        if item in known and known[item][1] != r:
            changes.append(f"- rank {item}: {known[item][1]} -> {r} ({votes} vote(s), all: {dict(c)})")
            known[item][1] = r
        elif item not in known:
            q = qtys[item].most_common(1)[0][0] if qtys.get(item) else 1
            e = [item, r, prof_of.get(item, "Other"), q]
            entries.append(e)
            known[item] = e
            changes.append(f"- new writ {item}: {r}, {e[2]}, quantity {q}")
    report += ["## Writs.lua", ""] + (changes or ["- no change"]) + [""]

    # destinations
    dchanges = []
    for item, c in sorted(dests.items()):
        (text, zone), votes = c.most_common(1)[0]
        npc, sub, z = parse_dest(text, zone)
        old = dest_entries.get(item)
        new = {"npc": npc, "sub": sub, "zone": z or (old or {}).get("zone", ""), "check": votes < 2,
               "xy": (old or {}).get("xy", "") if old and old["npc"] == npc else "", "obj": False}
        if len(c) > 1:
            dchanges.append(f"- disagreement on {item}: {dict(c)}")
        if not old or (old["npc"], old["sub"], old["zone"], old["check"]) != (new["npc"], new["sub"], new["zone"], new["check"]):
            dchanges.append(f"- {item}: {old and (old['npc'] + ' / ' + old['zone']) or 'unknown'} -> {npc} / {new['zone']}"
                            f" ({votes} vote(s){', confirmed' if not new['check'] else ''})")
            dest_entries[item] = new
    report += ["## Dests.lua", ""] + (dchanges or ["- no change"]) + [""]

    # pouch defaults
    defaults = {}
    report += ["## Coin Pouch", ""]
    for r in RANKS:
        vals = pouch.get(r, [])
        if len(vals) >= 3:
            defaults[r] = int(statistics.median(vals))
            report.append(f"- {r}: median {defaults[r]} copper from {len(vals)} samples (min {min(vals)}, max {max(vals)})")
        else:
            report.append(f"- {r}: {len(vals)} sample(s), not enough (3 needed)")
    report.append("")

    # write files
    order = {r: i for i, r in enumerate(RANKS)}
    head = writs_src[:writs_src.index("ns.WRIT_LIST = {")]
    out = [head.rstrip("\n"), "ns.WRIT_LIST = {"]
    for r in RANKS:
        out.append(f"  -- {r}")
        for e in entries:
            if e[1] == r:
                out.append(f'  [{lua_str(e[0])}] = {{ rank = "{e[1]}", prof = "{e[2]}", qty = {e[3]} }},')
    out.append("}")
    if defaults:
        out.append("-- Coin Pouch reward per rank (copper): median of the samples merged from player exports")
        out.append("ns.POUCH_DEFAULT = { " + ", ".join(f"{r} = {defaults[r]}" for r in RANKS if r in defaults) + " }")
    else:
        m = re.search(r"ns\.POUCH_DEFAULT = \{.*\}", writs_src)
        if m:
            out.append("-- Coin Pouch reward per rank (copper): median of the samples merged from player exports")
            out.append(m.group(0))
    new_writs = "\n".join(out) + "\n"
    dhead = dests_src[:dests_src.index("ns.WRIT_DEST = {")]
    dout = [dhead.rstrip("\n"), "ns.WRIT_DEST = {"]
    for item in sorted(dest_entries):
        d = dest_entries[item]
        obj = ", obj = true" if d["obj"] else ""
        dout.append(f'  [{lua_str(item)}] = {{ npc = {lua_str(d["npc"])}, sub = {lua_str(d["sub"])}, zone = {lua_str(d["zone"])}, '
                    f'xy = {lua_str(d["xy"])}, check = {"true" if d["check"] else "false"}{obj} }},')
    dout.append("}")
    new_dests = "\n".join(dout) + "\n"

    # IDs for clients in other languages
    ids_path = os.path.join(ROOT, "Ids.lua")
    ids_src = open(ids_path, encoding="utf-8").read()
    extra = {unlua(m.group(1)): int(m.group(2)) for m in re.finditer(r'\["(.+?)"\] = (\d+),', ids_src)}
    m = re.search(r"ns\.FACTION_ID = (\d+)", ids_src)
    faction = int(m.group(1)) if m else None
    ichanges = []
    for name, c in sorted(item_ids.items()):
        item = name[len("Craftsman's Writ: "):] if name.startswith("Craftsman's Writ: ") else None
        if not (name == "Coin Pouch" or (item and item in known) or name in known):
            ichanges.append(f"- ignored {name} (not a known writ, requested item or the Coin Pouch)")
            continue
        iid, votes = c.most_common(1)[0]
        if len(c) > 1:
            ichanges.append(f"- disagreement on {name}: {dict(c)}")
        if extra.get(name) != iid:
            ichanges.append(f"- {name}: {extra.get(name)} -> {iid} ({votes} vote(s))")
            extra[name] = iid
    if faction_ids:
        fid, votes = faction_ids.most_common(1)[0]
        if fid != faction:
            ichanges.append(f"- faction ID: {faction} -> {fid} ({votes} vote(s), all: {dict(faction_ids)})")
            faction = fid
    report += ["## Ids.lua", ""] + (ichanges or ["- no change"]) + [""]
    ihead = ids_src[:ids_src.index("ns.EXTRA_IDS = {")]
    iout = [ihead.rstrip("\n"), "", "ns.EXTRA_IDS = {"]
    for name in sorted(extra):
        iout.append(f"  [{lua_str(name)}] = {extra[name]},")
    iout.append("}")
    iout.append("-- Azeroth Commerce Authority")
    iout.append(f"ns.FACTION_ID = {faction if faction else 'nil'}")
    new_ids = "\n".join(iout) + "\n"

    text = "\n".join(report)
    print(text)
    if not dry:
        open(os.path.join(ROOT, "Writs.lua"), "w", encoding="utf-8").write(new_writs)
        open(os.path.join(ROOT, "Dests.lua"), "w", encoding="utf-8").write(new_dests)
        open(ids_path, "w", encoding="utf-8").write(new_ids)
        os.makedirs(os.path.join(ROOT, "dev", "data"), exist_ok=True)
        open(os.path.join(ROOT, "dev", "data", "merge_report.md"), "w", encoding="utf-8").write(text + "\n")
        print("Writs.lua, Dests.lua and Ids.lua updated. Run the tests, then dev/build_zip.py.")


if __name__ == "__main__":
    main()
