"""Static checks: every .toc file compiles with real Lua, locale parity, format specifiers,
used keys exist, no hard-coded display strings, no donation text in shipped files."""
import os, re, sys, glob
import lupa.lua51 as lupa  # WoW runs Lua 5.1

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
fail = []
L = lupa.LuaRuntime()
compile_ = L.eval("function(s, n) local f, err = loadstring(s, n) return err end")

toc = [l.strip().replace("\\", "/") for l in open(os.path.join(ROOT, "WritPrice.toc"), encoding="utf-8")
       if l.strip() and not l.startswith("#")]
for f in toc:
    p = os.path.join(ROOT, f)
    if not os.path.exists(p):
        fail.append("missing file in .toc: " + f); continue
    err = compile_(open(p, encoding="utf-8").read(), f)
    if err is not None:
        fail.append("compile: %s" % err)
on_disk = {os.path.relpath(p, ROOT).replace("\\", "/") for p in glob.glob(os.path.join(ROOT, "**", "*.lua"), recursive=True)
           if "/dev/" not in p.replace("\\", "/")}
for orphan in sorted(on_disk - set(toc)):
    fail.append("lua file not in .toc: " + orphan)

# locale tables
def load_locale(code):
    src = open(os.path.join(ROOT, "Locales", code + ".lua"), encoding="utf-8").read()
    rt = lupa.LuaRuntime()
    rt.execute("ns = {LOCALES={}}")
    rt.eval("function(s) local f = assert(loadstring(s)) f(nil, ns) end")(src)
    return {k: v for k, v in rt.eval("ns.LOCALES." + code).items()}
en, fr = load_locale("enUS"), load_locale("frFR")
if set(en) != set(fr):
    fail.append("key mismatch: %s" % sorted(set(en) ^ set(fr)))
spec = re.compile(r"%[-0-9.]*[dsfx%]")
for k in en:
    if k in fr and spec.findall(en[k]) != spec.findall(fr[k]):
        fail.append("format mismatch %s: %r / %r" % (k, en[k], fr[k]))
if not any(ch in "".join(fr.values()) for ch in "éèàçù"):
    fail.append("frFR has no accents")
if "�" in "".join(fr.values()):
    fail.append("frFR has replacement characters")

# keys used in code
code_files = [f for f in toc if not f.startswith("Locales/") and f not in ("Recipes.lua", "Writs.lua", "Dests.lua")]
used = set()
dyn_prefixes = ("IMPORT_", "PROF_", "SCAN_WHY_", "SRC_", "COL_", "LANG_", "HELP_", "TIP_HELP_", "UI_ROWS_", "UI_PENDING_",
                "ROW_FOR_SALE_")
for f in code_files:
    s = open(os.path.join(ROOT, f), encoding="utf-8").read()
    used |= set(re.findall(r"\bL\.([A-Z][A-Z0-9_]+)", s))
    used |= set(re.findall(r'\bL\["([A-Z][A-Za-z0-9_ ]+)"\]', s))
    used |= set(re.findall(r'ns\.F\("([A-Z][A-Z0-9_]+)"', s))
    # keys passed as string arguments to widget helpers (options page)
    used |= set(re.findall(r'"((?:OPT|TIP|COL)_[A-Za-z0-9_]+)"', s))
    for k in re.findall(r'ns\.Plural\([^,]+,\s*"([A-Z][A-Z0-9_]+)"', s):
        used |= {k + "_1", k + "_N"}
for k in sorted(used):
    if k not in en and k != "UNKNOWN_KEY_FOR_TEST" and not k.endswith("_"):
        fail.append("key used but missing: " + k)
unused = sorted(k for k in en if k not in used and not k.startswith(dyn_prefixes) and k not in ("PLURAL_ZERO_ONE",))
if unused:
    print("note: keys never referenced directly:", ", ".join(unused))

# hard-coded display strings
display = re.compile(r'(?:Print|print|AddLine|AddDoubleLine|SetText)\(\s*"([^"]*)"')
allowed = {" ", "?", "WritPrice", "-", ""}
for f in code_files:
    for i, line in enumerate(open(os.path.join(ROOT, f), encoding="utf-8"), 1):
        if line.strip().startswith("--"):
            continue
        for m in display.findall(line):
            if m not in allowed and re.search(r"[A-Za-z]{2,}\s+[A-Za-z]", m):
                fail.append("hard-coded text %s:%d: %r" % (f, i, m))
        for word in ("metier", "quete", "fenetre", "Aucun ", "reputation a"):
            if re.search(r'"[^"]*%s[^"]*"' % word, line) and "ALIAS" not in line and "map" not in line:
                if not line.strip().startswith(("profs", "langue", "echelle", "colonnes", "aide", "apropos")):
                    fail.append("French text outside locales %s:%d" % (f, i))

# no donation text in shipped files
ship = toc + ["LICENSE", "CREDITS.md", "CHANGELOG.md"]
for f in ship:
    p = os.path.join(ROOT, f)
    if os.path.exists(p):
        s = open(p, encoding="utf-8", errors="replace").read().lower()
        for w in ("donat", "ko-fi", "paypal", "patreon", "buymeacoffee", "buy me a coffee"):
            if w in s:
                fail.append("donation word %r in shipped file %s" % (w, f))

if fail:
    print("\n".join("FAIL " + x for x in fail))
    sys.exit(1)
print("check_locales: OK (%d keys, %d files)" % (len(en), len(toc)))
