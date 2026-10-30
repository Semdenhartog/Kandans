"""Zet in de Supabase Auth-mails (onderwerpen, teksten, afzendernaam) "RunWise" om naar "Kadans".

Draait in .github/workflows/mailtemplates.yml met het GitHub-geheim SUPABASE_ACCESS_TOKEN.
Raakt alleen woorden met een hoofdletter (RunWise/Runwise/RUNWISE); kleine letters zoals
de deeplink runwise:// blijven staan. Mag vaker draaien: zonder treffers verandert er niets.
"""
import json
import os
import re
import sys
import urllib.request

REF = os.environ.get("PROJECT_REF", "jdswennyfczpqblfkrxt")
TOKEN = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
URL = f"https://api.supabase.com/v1/projects/{REF}/config/auth"
VELDEN = ("mailer_subjects_", "mailer_templates_", "smtp_sender_name", "mailer_notifications_")

PATRONEN = [
    (re.compile(r"\bRUNWISE\b"), "KADANS"),
    (re.compile(r"\bRun[Ww]ise\b"), "Kadans"),
]


def vervang(tekst: str) -> str:
    for patroon, nieuw in PATRONEN:
        tekst = patroon.sub(nieuw, tekst)
    return tekst


def verzoek(methode: str, data: dict | None = None) -> dict:
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(URL, data=body, method=methode, headers={
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json",
        "User-Agent": "kadans-mailtemplates",
    })
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read() or b"{}")


def main() -> int:
    if not TOKEN:
        print("::error::GitHub-geheim SUPABASE_ACCESS_TOKEN ontbreekt.")
        return 1
    config = verzoek("GET")
    wijzigingen = {}
    for sleutel, waarde in config.items():
        if not isinstance(waarde, str) or not sleutel.startswith(VELDEN):
            continue
        nieuw = vervang(waarde)
        if nieuw != waarde:
            wijzigingen[sleutel] = nieuw
            print(f"- {sleutel}: {len(PATRONEN[1][0].findall(waarde)) + len(PATRONEN[0][0].findall(waarde))}x vervangen")
    if not wijzigingen:
        print("Niets meer te doen: geen 'RunWise' gevonden in de mails.")
        return 0
    verzoek("PATCH", wijzigingen)
    # Nog een keer ophalen en controleren.
    rest = [k for k, v in verzoek("GET").items()
            if isinstance(v, str) and k.startswith(VELDEN) and vervang(v) != v]
    if rest:
        print(f"::error::Nog steeds 'RunWise' in: {', '.join(rest)}")
        return 1
    print(f"Klaar: {len(wijzigingen)} velden bijgewerkt naar Kadans.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
