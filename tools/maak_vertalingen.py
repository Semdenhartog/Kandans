"""Maakt lib/core/i18n_strings.dart uit tools/vertalingen.py en meldt teksten in tr() zonder vertaling.

Gebruik: python3 tools/maak_vertalingen.py
"""
import glob
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from vertalingen import T  # noqa: E402

pat = re.compile(r"\btr\(((?:\s*'(?:[^'\\\n]|\\.)*')+)\s*\)")
used = []
for f in sorted(glob.glob(str(ROOT / "lib/**/*.dart"), recursive=True)):
    for m in pat.finditer(Path(f).read_text(encoding="utf-8")):
        t = "".join(re.findall(r"'((?:[^'\\\n]|\\.)*)'", m.group(1)))
        if "$" not in t and t not in used:
            used.append(t)


def esc(s: str) -> str:
    # Sleutels/teksten staan in vertalingen.py al met \\n; alleen ' en $ hoeven nog een escape.
    return s.replace("\\'", "'").replace("'", "\\'").replace("$", "\\$")


missing = [u for u in used if u.replace("\\'", "'") not in T]
lines = [
    "// GEMAAKT DOOR tools/maak_vertalingen.py uit tools/vertalingen.py — niet met de hand aanpassen.",
    "",
    "/// Nederlandse tekst → [Engels, Duits, Frans, Spaans].",
    "const kTranslations = <String, List<String>>{",
]
for k, v in T.items():
    lines.append(f"  '{esc(k)}': ['{esc(v[0])}', '{esc(v[1])}', '{esc(v[2])}', '{esc(v[3])}'],")
lines += ["};", ""]
(ROOT / "lib/core/i18n_strings.dart").write_text("\n".join(lines), encoding="utf-8")
print(f"{len(T)} vertalingen geschreven; {len(used)} teksten in tr(); ontbrekend: {len(missing)}")
for m in missing:
    print("  ONTBREEKT:", m)
