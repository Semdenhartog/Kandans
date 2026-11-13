#!/usr/bin/env python3
"""Zet supabase/coach_kennis/*.txt om naar SQL (upsert op sleutel).

Gebruik:  python3 tools/coach_kennis_naar_sql.py            -> SQL naar stdout
          python3 tools/coach_kennis_naar_sql.py --tel      -> alleen tellen + controleren

Onderwerpen die Sem in de beheerpagina heeft aangepast (bron = 'sem') worden niet overschreven.
Voorbeeldvragen van gebruikers/Sem bij een onderwerp blijven staan.
"""
import glob, os, re, sys

MAP = os.path.join(os.path.dirname(__file__), "..", "supabase", "coach_kennis")
ACTIES = {"week", "laatste", "maand", "vandaag", "kleding", "tempo", "wedstrijd"}
SOORTEN = {"antwoord", "buiten", "arts"}


def lees():
    items, fout = [], []
    for pad in sorted(glob.glob(os.path.join(MAP, "*.txt"))):
        cur = None
        regels = open(pad, encoding="utf-8").read().split("\n")
        for nr, r in enumerate(regels, 1):
            waar = f"{os.path.basename(pad)}:{nr}"
            if r.startswith("##"):
                continue
            if r.startswith("# ") and "|" in r:
                delen = [d.strip() for d in r[2:].split("|")]
                if len(delen) < 4:
                    fout.append(f"{waar}: kop heeft te weinig delen")
                    continue
                cur = {"sleutel": delen[0], "onderwerp": delen[1], "categorie": delen[2],
                       "trefwoorden": [t.strip() for t in delen[3].split(",") if t.strip()],
                       "actie": None, "soort": "antwoord", "veel": [], "verwacht": [], "antwoord": [], "waar": waar}
                for extra in delen[4:]:
                    k, _, v = extra.partition("=")
                    cur[k.strip()] = v.strip()
                items.append(cur)
                continue
            if r.startswith("# +"):
                naam = r[3:].strip()
                cur = next((i for i in items if i["sleutel"] == naam), None)
                if cur is None:
                    fout.append(f"{waar}: onbekende sleutel {naam}")
                continue
            if r.startswith("#"):
                continue
            if cur is None:
                continue
            if r.startswith("? "):
                cur["veel"].append(r[2:].strip())
            elif r.startswith("! "):
                cur["verwacht"].append(r[2:].strip())
            elif r.startswith("= "):
                if cur["antwoord"]:
                    fout.append(f"{waar}: tweede antwoord voor {cur['sleutel']}")
                cur["antwoord"] = [r[2:]]
            elif r.startswith("| "):
                for extra in r[2:].split("|"):
                    k, _, v = extra.partition("=")
                    cur[k.strip()] = v.strip()
            elif cur["antwoord"] and r.strip():
                cur["antwoord"].append(r)
            elif cur["antwoord"] and not r.strip():
                cur["antwoord"].append("")
    sleutels = set()
    for it in items:
        it["antwoord"] = "\n".join(it["antwoord"]).strip()
        if it["sleutel"] in sleutels:
            fout.append(f"{it['waar']}: dubbele sleutel {it['sleutel']}")
        sleutels.add(it["sleutel"])
        if it["actie"] and it["actie"] not in ACTIES:
            fout.append(f"{it['waar']}: onbekende actie {it['actie']}")
        if it["soort"] not in SOORTEN:
            fout.append(f"{it['waar']}: onbekende soort {it['soort']}")
        if not it["actie"] and not it["antwoord"]:
            fout.append(f"{it['waar']}: geen antwoord")
        if not it["veel"] and not it["verwacht"]:
            fout.append(f"{it['waar']}: geen vragen")
    # De vervolgvraag van de coach zoekt een onderwerp terug op naam: die moet dus uniek zijn.
    namen = [it["onderwerp"].strip().lower() for it in items]
    for n in sorted({n for n in namen if namen.count(n) > 1}):
        fout.append(f"dubbel onderwerp: {n}")
    kruis(items, sleutels, fout)
    alle = [v.lower() for it in items for v in it["veel"] + it["verwacht"]]
    dubbel = {v for v in alle if alle.count(v) > 1}
    for d in sorted(dubbel):
        fout.append(f"dubbele vraag: {d}")
    return items, fout


STOP = {"voor", "naar", "met", "van", "het", "een", "bij", "mijn", "tijdens", "lopen", "hardlopen", "kadans", "wat", "hoe", "als", "over"}


def woorden(it):
    tekst = " ".join([it["onderwerp"]] + it["trefwoorden"]).lower()
    return {w[:6] for w in re.findall(r"[a-zà-ÿ0-9]{4,}", tekst) if w not in STOP}


def kruis(items, sleutels, fout):
    """Kruisverwijzingen: 'zie=a,b' uit het bestand, anders de 3 best passende onderwerpen (zelfde categorie, gedeelde woorden).

    Onderwerpen in de categorie 'buiten' (niet over hardlopen) verwijzen nergens naar en worden niet aangeraden."""
    w = {it["sleutel"]: woorden(it) for it in items}
    for it in items:
        opgegeven = [z.strip() for z in str(it.get("zie") or "").split(",") if z.strip()]
        for z in opgegeven:
            if z not in sleutels:
                fout.append(f"{it['waar']}: zie verwijst naar onbekende sleutel {z}")
            if z == it["sleutel"]:
                fout.append(f"{it['waar']}: zie verwijst naar zichzelf")
        if it["categorie"] == "buiten":
            it["zie"] = []
            continue
        if not opgegeven:
            scores = []
            for o in items:
                if o is it or o["categorie"] == "buiten":
                    continue
                score = 2 * len(w[it["sleutel"]] & w[o["sleutel"]]) + (1 if o["categorie"] == it["categorie"] else 0)
                if score >= 1:
                    scores.append((-score, o["sleutel"]))
            opgegeven = [k for _, k in sorted(scores)[:3]]
        it["zie"] = opgegeven[:3]


def q(s):
    return "'" + s.replace("'", "''") + "'"


def arr(xs):
    return "array[" + ",".join(q(x) for x in xs) + "]::text[]" if xs else "'{}'::text[]"


def sql(items):
    out = ["begin;"]
    for it in items:
        out.append(
            "with k as (insert into public.coach_kennis (sleutel, onderwerp, categorie, antwoord, actie, soort, trefwoorden, zie, bron)\n"
            f"  values ({q(it['sleutel'])}, {q(it['onderwerp'])}, {q(it['categorie'])}, {q(it['antwoord'])}, "
            f"{q(it['actie']) if it['actie'] else 'null'}, {q(it['soort'])}, {arr(it['trefwoorden'])}, {arr(it['zie'])}, 'kadans')\n"
            "  on conflict (sleutel) do update set onderwerp = excluded.onderwerp, categorie = excluded.categorie,\n"
            "    antwoord = excluded.antwoord, actie = excluded.actie, soort = excluded.soort, trefwoorden = excluded.trefwoorden,\n"
            "    zie = excluded.zie\n"
            "  where public.coach_kennis.bron = 'kadans'\n"
            "  returning id),\n"
            "d as (delete from public.coach_vragen where kennis_id in (select id from k) and herkomst in ('veelgesteld', 'verwacht'))\n"
            "insert into public.coach_vragen (kennis_id, vraag, herkomst)\n"
            "  select k.id, v.vraag, v.herkomst from k, (values "
            + ", ".join([f"({q(v)}, 'veelgesteld')" for v in it["veel"]] + [f"({q(v)}, 'verwacht')" for v in it["verwacht"]])
            + ") as v(vraag, herkomst);"
        )
    keys = ",".join(q(it["sleutel"]) for it in items)
    out.append(f"update public.coach_kennis set actief = false where bron = 'kadans' and sleutel is not null and sleutel not in ({keys});")
    out.append("commit;")
    return "\n".join(out)


if __name__ == "__main__":
    items, fout = lees()
    if "--tel" in sys.argv:
        veel = sum(len(i["veel"]) for i in items)
        verw = sum(len(i["verwacht"]) for i in items)
        print(f"onderwerpen: {len(items)}  veelgesteld: {veel}  verwacht: {verw}  totaal: {veel + verw}")
        cats = {}
        for i in items:
            cats[i["categorie"]] = cats.get(i["categorie"], 0) + len(i["veel"]) + len(i["verwacht"])
        print(f"kruisverwijzingen: {sum(len(i['zie']) for i in items)} (onderwerpen zonder: {sum(1 for i in items if not i['zie'])})")
        print("per categorie:", ", ".join(f"{k} {v}" for k, v in sorted(cats.items(), key=lambda x: -x[1])))
    for f in fout:
        print("FOUT:", f, file=sys.stderr)
    if fout:
        sys.exit(1)
    if "--tel" not in sys.argv:
        print(sql(items))
