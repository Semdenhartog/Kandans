"""Controleert dat de lokale links en afbeeldingen in site/*.html bestaan. Gebruik: python3 tools/site_links.py [site]
Geeft een waarschuwing per ontbrekend bestand; stopt niet met een fout (de site mag live blijven)."""
import pathlib, re, sys, urllib.parse

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "site")
attr = re.compile(r'(?:href|src)="([^"]+)"')
missing = 0
for page in sorted(root.glob("*.html")):
    for ref in attr.findall(page.read_text(encoding="utf-8")):
        if re.match(r"^(https?:|runwise:|mailto:|tel:|#|data:|javascript:|//)", ref) or "__" in ref or "{" in ref or "'" in ref:
            continue
        path = urllib.parse.unquote(ref.split("#")[0].split("?")[0])
        if not path:
            continue
        target = (root / path.lstrip("/")) if path.startswith("/") else (page.parent / path)
        if target.is_dir():
            target = target / "index.html"
        if not target.exists():
            missing += 1
            print(f"::warning file={page}::ontbrekend bestand: {ref}")
print(f"Linkcontrole klaar: {missing} ontbrekend")
