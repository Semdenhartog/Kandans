#!/usr/bin/env bash
# Codekaart (graphify) gebruiken in een Claude-sessie, zonder hele bestanden te lezen.
#
#   tools/graaf.sh                 kaart ophalen (branch "graaf") en graphify klaarzetten
#   tools/graaf.sh explain X       bestand of symbool X: wat het definieert, importeert en wie het gebruikt
#   tools/graaf.sh path A B        kortste verband tussen A en B
#   tools/graaf.sh query "vraag"   zoektocht door de kaart (grof; liever explain met een precieze naam)
#
# De kaart wordt na elke push naar main gebouwd door .github/workflows/graaf.yml.
# graphify zelf komt als broncode van GitHub (vaste versie), omdat PyPI in sessies
# vaak geblokkeerd is. Opvragen heeft alleen networkx/numpy/pyyaml nodig.
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
GFY_VERSIE="v0.9.97"
GFY_DIR="${GRAAF_BRON:-/tmp/graphify-$GFY_VERSIE}"
UIT="$ROOT/graphify-out"

if [ ! -d "$GFY_DIR/graphify" ]; then
  git clone -q --depth 1 --branch "$GFY_VERSIE" https://github.com/Graphify-Labs/graphify "$GFY_DIR" >/dev/null 2>&1 \
    || { echo "Kon graphify niet ophalen van GitHub." >&2; exit 1; }
fi
python3 -c "import networkx, numpy, yaml" 2>/dev/null \
  || pip install -q --break-system-packages networkx numpy pyyaml >/dev/null 2>&1 || true

if [ ! -f "$UIT/graph.json" ] || [ "${1:-}" = "" ] || [ "${1:-}" = "ophalen" ]; then
  git -C "$ROOT" fetch -q --depth 1 origin graaf 2>/dev/null \
    || { echo "Branch 'graaf' bestaat nog niet; draai de workflow 'Codekaart (graphify)'." >&2; exit 1; }
  mkdir -p "$UIT"
  git -C "$ROOT" show FETCH_HEAD:graph.json > "$UIT/graph.json"
  git -C "$ROOT" show FETCH_HEAD:GRAPH_REPORT.md > "$UIT/GRAPH_REPORT.md"
  KAART=$(git -C "$ROOT" show FETCH_HEAD:COMMIT)
  echo "$KAART" > "$UIT/COMMIT"
  NU=$(git -C "$ROOT" rev-parse HEAD)
  echo "Codekaart opgehaald (gemaakt van ${KAART:0:8}, jouw checkout ${NU:0:8})."
  if ! git -C "$ROOT" diff --quiet "$KAART" HEAD -- lib supabase test test_screens tools 2>/dev/null; then
    echo "Let op: code is daarna veranderd; controleer gewijzigde bestanden zelf."
  fi
  [ "${1:-}" = "" ] || [ "${1:-}" = "ophalen" ] && exit 0
fi

cd "$ROOT"
PYTHONPATH="$GFY_DIR${PYTHONPATH:+:$PYTHONPATH}" exec python3 -m graphify "$@"
