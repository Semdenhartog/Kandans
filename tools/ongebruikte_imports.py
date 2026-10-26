"""Snelle controle (zonder Flutter): meldt imports waarvan geen enkel bekend symbool gebruikt wordt.

Alleen voor een paar veelgebruikte pakketten/bestanden; de echte controle doet `flutter analyze` in de cloudbuild.
Gebruik: python3 tools/ongebruikte_imports.py lib/pad/bestand.dart ...
"""
import re
import sys

KNOWN = {
    "core/config.dart": r"\bAppConfig\b",
    "package:url_launcher/url_launcher.dart": r"\b(launchUrl|LaunchMode|canLaunchUrl)\b",
    "package:flutter/gestures.dart": r"\b(TapGestureRecognizer|GestureRecognizer)\b",
    "package:share_plus/share_plus.dart": r"\b(SharePlus|ShareParams|XFile)\b",
    "package:go_router/go_router.dart": r"\b(context\.(go|push|pop)|GoRouter|GoRoute)\b",
    "package:flutter/services.dart": r"\b(HapticFeedback|Clipboard|ClipboardData|SystemChrome|rootBundle|SystemNavigator|TextInputFormatter|FilteringTextInputFormatter|PlatformException|MethodChannel)\b",
    "package:shared_preferences/shared_preferences.dart": r"\bSharedPreferences\b",
}

bad = 0
for path in sys.argv[1:]:
    src = open(path, encoding="utf-8").read()
    body = "\n".join(l for l in src.splitlines() if not l.startswith("import "))
    for imp, pat in KNOWN.items():
        if re.search(r"^import '.*" + re.escape(imp) + "'", src, re.M) and not re.search(pat, body):
            print(f"{path}: ongebruikt? {imp}")
            bad += 1
sys.exit(1 if bad else 0)
