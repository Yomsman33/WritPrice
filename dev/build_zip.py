"""Builds WritPrice-<version>.zip with a single WritPrice/ folder (files listed in the .toc + LICENSE, CREDITS, CHANGELOG).
Usage: python3 dev/build_zip.py [output directory]"""
import os, re, sys, zipfile
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
toc = open(os.path.join(ROOT, "WritPrice.toc"), encoding="utf-8").read()
version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
files = ["WritPrice.toc", "LICENSE", "CREDITS.md", "CHANGELOG.md"]
files += [l.strip().replace("\\", "/") for l in toc.splitlines() if l.strip() and not l.startswith("#")]
out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(ROOT)
out = os.path.join(out_dir, "WritPrice-%s.zip" % version)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(os.path.join(ROOT, f), "WritPrice/" + f)
print(out, len(files), "files")
