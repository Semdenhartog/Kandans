#!/usr/bin/env python3
"""Zoekt naar geheime sleutels in de repo. Faalt (exit 1) als er iets verdachts staat.

De publieke Supabase-instellingen (URL en publishable/anon key) mogen wel: die zijn bedoeld
om openbaar te zijn. De service-role key, API-sleutels van betaalde diensten en
privésleutels mogen nooit in de code.
"""
import base64
import json
import pathlib
import re
import subprocess
import sys

PATTERNS = [
    ("Anthropic-sleutel", re.compile(r"sk-ant-[A-Za-z0-9_\-]{20,}")),
    ("OpenAI-sleutel", re.compile(r"sk-(?:proj-)?[A-Za-z0-9]{32,}")),
    ("Supabase secret key", re.compile(r"sb_secret_[A-Za-z0-9_\-]{20,}")),
    ("Stripe/RevenueCat geheime sleutel", re.compile(r"\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}|\bsk_[A-Za-z0-9]{30,}")),
    ("Stripe-webhookgeheim", re.compile(r"\bwhsec_[A-Za-z0-9]{20,}")),
    ("AWS-sleutel", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("Google API-sleutel", re.compile(r"\bAIza[0-9A-Za-z_\-]{35}\b")),
    ("GitHub-token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b")),
    ("Privésleutel", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    ("Mapillary-token", re.compile(r"\bMLY\|[0-9]+\|[0-9a-f]{20,}")),
]
JWT = re.compile(r"eyJ[A-Za-z0-9_\-]{10,}\.(eyJ[A-Za-z0-9_\-]{10,})\.[A-Za-z0-9_\-]{10,}")
SKIP_SUFFIX = (".png", ".jpg", ".jpeg", ".webp", ".ttf", ".otf", ".jks", ".keystore", ".mp3", ".wav", ".ogg", ".gif", ".ico")


def jwt_role(payload_b64: str) -> str | None:
    try:
        pad = "=" * (-len(payload_b64) % 4)
        return json.loads(base64.urlsafe_b64decode(payload_b64 + pad)).get("role")
    except Exception:
        return None


def main() -> int:
    files = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout.split("\n")
    found = []
    for name in files:
        if not name or name.endswith(SKIP_SUFFIX) or name.startswith(".github/scripts/geheimen_scan"):
            continue
        p = pathlib.Path(name)
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except (OSError, IsADirectoryError):
            continue
        for i, line in enumerate(text.splitlines(), 1):
            for label, rx in PATTERNS:
                if rx.search(line):
                    found.append((name, i, label))
            for m in JWT.finditer(line):
                if jwt_role(m.group(1)) == "service_role":
                    found.append((name, i, "Supabase service-role key"))
    for name, line, label in found:
        print(f"::error file={name},line={line}::Mogelijk geheim: {label}. Haal het uit de code en zet het in Supabase of GitHub Secrets.")
    if found:
        print(f"{len(found)} mogelijk(e) geheim(en) gevonden.")
        return 1
    print("Geen geheimen gevonden.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
