#!/usr/bin/env bash
# Prova de punta a punta d'aquesta wiki.
#
# Comprova el COMPORTAMENT del build real, no l'aspecte:
#   1. el build estàtic es completa
#   2. $:/DefaultTiddlers només apunta a tiddlers que existeixen (si no, la wiki
#      s'obre amb «Missing tiddler» i cap comprovació de fitxers ho veu)
#   3. cada tiddler no-sistema genera la seva pàgina i no diu «Missing tiddler»
#
# S'amplia amb una comprovació per funcionalitat nova. Trenca-la a posta i mira que
# surti vermella abans de dir que passa.
#
# Ús: proves/e2e.sh   (o WIKI=/tmp/tw-branca proves/e2e.sh)
set -uo pipefail

WIKI="${WIKI:-$(cd "$(dirname "$0")/.." && pwd)}"
FAILS=0

ok()  { printf 'PASS  %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; FAILS=$((FAILS+1)); }

TW="${TW:-}"
[ -z "$TW" ] && TW="$(command -v tiddlywiki 2>/dev/null || true)"
if [ -z "$TW" ] && [ -x "${HOME}/.npm-global/bin/tiddlywiki" ]; then
  TW="${HOME}/.npm-global/bin/tiddlywiki"
fi
if [ -z "$TW" ] || [ ! -x "$TW" ]; then
  echo "FAIL  no s'ha trobat tiddlywiki. Instal·la'l (npm i -g tiddlywiki) o passa TW=<ruta>." >&2
  exit 1
fi

TMP="$(mktemp -d /tmp/e2e-cido.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

echo "== build de la wiki =="
mkdir -p "${TMP}/wiki"
cp -r "${WIKI}/tiddlywiki.info" "${WIKI}/tiddlers" "${TMP}/wiki/" || { bad "no s'ha pogut copiar la wiki"; exit 1; }
if "$TW" "${TMP}/wiki" --build static >"${TMP}/build.log" 2>&1; then
  ok "build static completat"
else
  bad "el build ha fallat"; tail -5 "${TMP}/build.log"; exit 1
fi

echo "== \$:/DefaultTiddlers =="
mapfile -t REFERITS < <(python3 - "$WIKI/tiddlers" <<'PY'
import pathlib, re, sys
d = pathlib.Path(sys.argv[1])
default = d / "$__DefaultTiddlers.tid"
if not default.is_file():
    raise SystemExit(0)
parts = default.read_text(encoding="utf-8").split("\n\n", 1)
cos = parts[1] if len(parts) > 1 else ""
# El contingut és un filtre. Els títols amb espais hi van entre [[ ]], i són la forma
# normal; sense claudàtors, cada línia no buida i no comentada és un títol sencer.
# (Partir per espais donaria «Aixo», «no», «existeix» com si fossin tres títols.)
enllacos = re.findall(r"\[\[(.+?)\]\]", cos)
if enllacos:
    for t in enllacos:
        print(t)
else:
    for linia in cos.splitlines():
        linia = linia.strip()
        if linia and not linia.startswith("#"):
            print(linia)
PY
)
EXISTENTS=$(python3 - "$WIKI/tiddlers" <<'PY'
import pathlib, sys
d = pathlib.Path(sys.argv[1])
for f in d.glob("*.tid"):
    for l in f.read_text(encoding="utf-8").splitlines():
        if l.startswith("title:"):
            print(l.split(":", 1)[1].strip()); break
        if not l.strip():
            break
PY
)
n_ref=0
for r in "${REFERITS[@]}"; do
  [ -n "$r" ] || continue
  n_ref=$((n_ref+1))
  if printf '%s\n' "$EXISTENTS" | grep -qxF "$r"; then ok "«${r}» (a \$:/DefaultTiddlers) existeix"
  else bad "«${r}» és a \$:/DefaultTiddlers i no existeix"; fi
done
[ "$n_ref" -gt 0 ] && ok "s'han resolt ${n_ref} referències del filtre" \
                   || bad "no s'ha pogut llegir cap referència de \$:/DefaultTiddlers"

echo "== una pàgina per tiddler, sense «Missing tiddler» =="
mapfile -t TITOLS < <(printf '%s\n' "$EXISTENTS" | grep -v '^\$:/' || true)
n_pag=0
for t in "${TITOLS[@]}"; do
  [ -n "$t" ] || continue
  ENC=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$t")
  PAG="${TMP}/wiki/output/static/${ENC}.html"
  if [ ! -f "$PAG" ]; then bad "sense pàgina generada per «${t}»"; continue; fi
  n_pag=$((n_pag+1))
  if grep -q "Missing tiddler" "$PAG"; then bad "«${t}» conté 'Missing tiddler'"
  else ok "«${t}» renderitzat"; fi
done
[ "$n_pag" -gt 0 ] || bad "no s'ha generat cap pàgina"

echo
if [ "$FAILS" -eq 0 ]; then echo "RESULTAT: wiki verificada."; exit 0; fi
echo "RESULTAT: ${FAILS} fallada(es)."
exit 1
