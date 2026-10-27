"""Zet Nederlandse teksten in een scherm om naar tr('...') zodat ze vertaald kunnen worden.

Gebruik: python3 tools/tr_codemod.py lib/pad/scherm.dart ...
- Text('…') en veelgebruikte benoemde teksten (label:, title:, message:, tooltip:, hintText:, labelText:, actionLabel:)
- haalt 'const' weg vóór constructors (tr() is niet constant); laat const-declaraties en standaardwaarden staan.
Teksten met $-invulling worden overgeslagen (die vertaal je met trf()).
"""
import re
import sys

LIT = r"'((?:[^'\\$\n]|\\.)+)'"
NAMED = r"(label|title|message|tooltip|hintText|labelText|actionLabel|helpText|semanticsLabel)"


def convert(src: str) -> str:
    out = re.sub(r"\bconst Text\(\s*" + LIT, lambda m: "Text(tr('" + m.group(1) + "')", src)
    out = re.sub(r"(?<![A-Za-z_.])Text\(\s*" + LIT, lambda m: "Text(tr('" + m.group(1) + "')", out)
    out = re.sub(NAMED + r"(\s*:\s*)" + LIT, lambda m: m.group(1) + m.group(2) + "tr('" + m.group(3) + "')", out)
    # 'const' weg vóór constructors/collecties, niet bij declaraties (const x =) of standaardwaarden (= const).
    out = re.sub(r"(?<!=\s)(?<!=)\bconst\s+(?=[A-Z\[{<(])", "", out)
    if "tr('" in out and "core/i18n.dart" not in out:
        imports = list(re.finditer(r"^import '.*?;\n", out, re.M))
        rel = "../" * (src_path.count('/') - 1) + "core/i18n.dart" if not src_path.startswith('lib/core/') else "i18n.dart"
        out = out[: imports[-1].end()] + f"import '{rel}';\n" + out[imports[-1].end():]
    return out


for src_path in sys.argv[1:]:
    s = open(src_path, encoding="utf-8").read()
    n = convert(s)
    if n != s:
        open(src_path, "w", encoding="utf-8").write(n)
        print(f"{src_path}: {n.count(chr(116)+'r(' + chr(39)) } teksten")
