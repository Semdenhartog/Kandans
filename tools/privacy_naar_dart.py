"""Zet site/privacy.html om naar lib/features/profile/privacy_text.dart.

Zo staat de privacyverklaring ook in de app (werkt zonder internet en zonder website).
Draait vanzelf in de cloudbuild; lokaal: python3 tools/privacy_naar_dart.py
"""
import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "site" / "privacy.html"
OUT = ROOT / "lib" / "features" / "profile" / "privacy_text.dart"


def clean(fragment: str) -> str:
    """Tekst zonder tags; **vet** blijft als markering voor de app."""
    s = re.sub(r"<(strong|b)>(.*?)</\1>", r"**\2**", fragment, flags=re.S)
    s = re.sub(r"<br\s*/?>", "\n", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    return re.sub(r"[ \t\r\n]+", " ", s).strip()


def dart(s: str) -> str:
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def main() -> int:
    page = SRC.read_text(encoding="utf-8")
    body = re.search(r"<main>(.*)</main>", page, re.S).group(1)
    blocks: list[str] = []
    pos = 0
    pattern = re.compile(r"<(h1|h2|p|li|tr)([^>]*)>(.*?)</\1>", re.S)
    for m in pattern.finditer(body):
        tag, attrs, inner = m.group(1), m.group(2), m.group(3)
        if tag == "h1":
            continue
        if tag == "h2":
            blocks.append(f"PrivacyBlock.heading({dart(clean(inner))})")
        elif tag == "p":
            kind = "meta" if 'class="meta"' in attrs else "paragraph"
            blocks.append(f"PrivacyBlock.{kind}({dart(clean(inner))})")
        elif tag == "li":
            blocks.append(f"PrivacyBlock.bullet({dart(clean(inner))})")
        elif tag == "tr":
            cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", inner, re.S)
            if len(cells) == 2 and "<th" not in inner:
                blocks.append(f"PrivacyBlock.row({dart(clean(cells[0]))}, {dart(clean(cells[1]))})")
        pos = m.end()
    if len(blocks) < 10:
        print("Te weinig blokken gevonden in privacy.html", file=sys.stderr)
        return 1
    out = [
        "// GEMAAKT DOOR tools/privacy_naar_dart.py uit site/privacy.html — niet met de hand aanpassen.",
        "// ignore_for_file: lines_longer_than_80_chars",
        "",
        "/// Eén stukje van de privacyverklaring.",
        "class PrivacyBlock {",
        "  const PrivacyBlock.heading(this.text) : kind = 'h', detail = null;",
        "  const PrivacyBlock.paragraph(this.text) : kind = 'p', detail = null;",
        "  const PrivacyBlock.meta(this.text) : kind = 'meta', detail = null;",
        "  const PrivacyBlock.bullet(this.text) : kind = 'li', detail = null;",
        "  const PrivacyBlock.row(this.text, String this.detail) : kind = 'row';",
        "  final String kind;",
        "  final String text;",
        "  final String? detail;",
        "}",
        "",
        "const privacyBlocks = <PrivacyBlock>[",
        *[f"  {b}," for b in blocks],
        "];",
        "",
    ]
    OUT.write_text("\n".join(out), encoding="utf-8")
    print(f"{len(blocks)} blokken naar {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
