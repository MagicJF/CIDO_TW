#!/usr/bin/env bash
# Prova de punta a punta d'aquesta wiki.
#
# Comprova el COMPORTAMENT del build real, no l'aspecte:
#   1. el build estàtic es completa
#   2. $:/DefaultTiddlers només apunta a tiddlers que existeixen (si no, la wiki
#      s'obre amb «Missing tiddler» i cap comprovació de fitxers ho veu)
#   3. cada tiddler no-sistema genera la seva pàgina i no diu «Missing tiddler»
#   4. les dades importades del CIDO compleixen el contracte: cada procés selectiu
#      (tiddler amb l'etiqueta CIDO) duu els camps que la funcionalitat fa servir i
#      l'enllaç concorda amb el títol
#   5. l'índex llista TOTS els processos, com a enllaços de debò i amb el caption
#      com a text, i el compte que declara és el que hi ha
#   6. cada fitxa renderitza les dades del SEU procés, cel·la a cel·la (no el text
#      sencer de la pàgina, que ja porta el caption amb el resum i l'ens)
#
# Trenca qualsevol de les sis i ha de sortir vermella. Un vermell per mecanisme.
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

# Totes les comprovacions sobre el build, en un sol procés: una build estàtica de
# 800 tiddlers costa dos minuts i no es pot repetir per cada comprovació.
python3 - "$WIKI" "${TMP}/wiki/output/static" <<'PY'
import html, pathlib, re, sys, urllib.parse

wiki, static = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
fallades = []

def ok(m):  print(f"PASS  {m}")
def bad(m):
    print(f"FAIL  {m}")
    fallades.append(m)

def camps(fitxer):
    """Els camps de capçalera d'un .tid (sense el cos)."""
    d = {}
    for linia in fitxer.read_text(encoding="utf-8").splitlines():
        if not linia.strip():
            break
        if ":" in linia:
            k, v = linia.split(":", 1)
            d[k.strip()] = v.strip()
    return d

def text(html_raw):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", html_raw)))

def pagina(titol):
    return static / (urllib.parse.quote(titol, safe="") + ".html")

tiddlers = sorted((wiki / "tiddlers").glob("*.tid"))
info = {f: camps(f) for f in tiddlers}
titols = {f: c.get("title", "").strip() for f, c in info.items()}

# --- 2. $:/DefaultTiddlers no pot apuntar enlloc que no hi sigui -----------------
default = wiki / "tiddlers" / "$__DefaultTiddlers.tid"
cos = default.read_text(encoding="utf-8").split("\n\n", 1)
referits = re.findall(r"\[\[(.+?)\]\]", cos[1] if len(cos) > 1 else "")
existents = set(titols.values())
for r in referits:
    if r in existents:
        ok(f"«{r}» (a $:/DefaultTiddlers) existeix")
    else:
        bad(f"«{r}» és a $:/DefaultTiddlers i no existeix")
if referits:
    ok(f"s'han resolt {len(referits)} referències del filtre de $:/DefaultTiddlers")
else:
    bad("no s'ha pogut llegir cap referència de $:/DefaultTiddlers")

# --- 3. una pàgina per tiddler, sense «Missing tiddler» --------------------------
n_pag = 0
sense_pagina, amb_missing = [], []
for f, t in titols.items():
    if t.startswith("$:/"):
        continue
    p = pagina(t)
    if not p.is_file():
        sense_pagina.append(t); continue
    n_pag += 1
    if "Missing tiddler" in p.read_text(encoding="utf-8"):
        amb_missing.append(t)
if sense_pagina:
    bad(f"{len(sense_pagina)} tiddler(s) sense pàgina generada (ex. {sense_pagina[:3]})")
else:
    ok(f"{n_pag} tiddlers amb la seva pàgina")
if amb_missing:
    bad(f"{len(amb_missing)} pàgina(es) amb 'Missing tiddler' (ex. {amb_missing[:3]})")
else:
    ok("cap pàgina diu 'Missing tiddler'")

# --- 4. invariants de les dades importades --------------------------------------
CAMPS = ("caption", "resum", "nom_ens", "data_pub", "enllac", "font")
cido = {c.get("title", ""): c for c in info.values() if "CIDO" in c.get("tags", "").split()}
if not cido:
    bad("no hi ha cap tiddler amb l'etiqueta CIDO")
problemes = {"sense_camps": [], "enllac": [], "data": [], "caption": []}
for t, c in cido.items():
    manquen = [k for k in CAMPS if not c.get(k)]
    if manquen:
        problemes["sense_camps"].append(f"{t}:{','.join(manquen)}")
    if not c.get("enllac", "").endswith(f"/oposicions/{t}"):
        problemes["enllac"].append(f"{t}->{c.get('enllac','')}")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", c.get("data_pub", "")):
        problemes["data"].append(f"{t}:{c.get('data_pub','')}")
    if not 0 < len(c.get("caption", "")) <= 91:
        problemes["caption"].append(f"{t}:{len(c.get('caption',''))}")
missatges = {
    "sense_camps": "tiddler(s) CIDO sense els camps que la fitxa i l'índex fan servir",
    "enllac": "tiddler(s) CIDO amb un enllaç que no concorda amb el títol",
    "data": "tiddler(s) CIDO amb data_pub que no és YYYY-MM-DD",
    "caption": "tiddler(s) CIDO sense caption o amb un caption massa llarg",
}
for clau, llista in problemes.items():
    if llista:
        bad(f"{len(llista)} {missatges[clau]} (ex. {llista[:3]})")
if not any(problemes.values()):
    ok(f"{len(cido)} processos CIDO amb tots els camps i l'enllaç concordant amb el títol")

# --- 5. l'índex llista tots els processos, amb enllaç de debò -------------------
index = pagina("Convocatòries de personal (CIDO)")
if not index.is_file():
    bad("no s'ha generat la pàgina de l'índex")
else:
    raw = index.read_text(encoding="utf-8")
    declarat = re.search(r"Són (\d+) processos", text(raw))
    if not declarat:
        bad("l'índex no declara quants processos hi ha")
    elif int(declarat.group(1)) != len(cido):
        bad(f"l'índex declara {declarat.group(1)} processos i n'hi ha {len(cido)}")
    else:
        ok(f"l'índex declara {declarat.group(1)} processos, els que hi ha")

    # Enllaços resolts: href cap a la pàgina del tiddler i text = caption.
    enllacos = {}
    for href, cos_enllac in re.findall(
            r'<a class="tc-tiddlylink tc-tiddlylink-resolves" href="([^"]+)"[^>]*>(.*?)</a>', raw, re.S):
        enllacos[urllib.parse.unquote(href)[:-5]] = html.unescape(re.sub(r"<[^>]+>", "", cos_enllac)).strip()
    faltes = []
    for t, c in cido.items():
        if enllacos.get(t) != c.get("caption"):
            faltes.append(f"{t} ({'sense enllaç' if t not in enllacos else 'text ' + repr(enllacos.get(t))[:40]})")
    if faltes:
        bad(f"{len(faltes)} procés(os) sense enllaç a l'índex o amb el text equivocat (ex. {faltes[:3]})")
    else:
        ok(f"{len(cido)} processos llistats a l'índex com a enllaços amb el seu caption")
    if "Missing tiddler" in raw:
        bad("l'índex conté 'Missing tiddler'")
    else:
        ok("l'índex no conté 'Missing tiddler'")

# --- 6. cada fitxa renderitza les dades del seu procés --------------------------
# Cel·la a cel·la, i no buscant el valor «en algun lloc de la pàgina»: l'encapçalament del
# cos ja porta el caption, que conté el resum i l'ens, així que una taula buida passaria
# verda si només es mira el text de tota la pàgina.
def cela(raw, etiqueta):
    m = re.search(r"<tr[^>]*>\s*<td>%s</td>\s*<td>(.*?)</td>\s*</tr>" % re.escape(etiqueta), raw, re.S)
    return m.group(1) if m else None

malament = []
for t, c in cido.items():
    p = pagina(t)
    if not p.is_file():
        malament.append(f"{t}: sense pàgina"); continue
    raw = p.read_text(encoding="utf-8")
    problemes = []
    for etiqueta, esperat in (("Resum", c["resum"]), ("Ens", c["nom_ens"]),
                              ("Publicació", c["data_pub"])):
        valor = cela(raw, etiqueta)
        if valor is None:
            problemes.append(f"sense la fila «{etiqueta}»")
        elif html.unescape(re.sub(r"<[^>]+>", "", valor)).strip() != esperat:
            problemes.append(f"«{etiqueta}» amb un altre valor")
    enllac = cela(raw, "Enllaç")
    if enllac is None:
        problemes.append("sense la fila «Enllaç»")
    elif f'href="{c["enllac"]}"' not in enllac:
        problemes.append("«Enllaç» sense l'enllaç del procés")
    h1 = re.search(r'<div class="tc-tiddler-body[^"]*">\s*<h1[^>]*>(.*?)</h1>', raw, re.S)
    if not h1:
        problemes.append("sense encapçalament al cos")
    elif html.unescape(re.sub(r"<[^>]+>", "", h1.group(1))).strip() != c["caption"]:
        problemes.append("encapçalament que no és el caption del procés")
    if problemes:
        malament.append(f"{t}: {', '.join(problemes)}")
if malament:
    bad(f"{len(malament)} fitxa(es) sense les dades del seu procés (ex. {malament[:3]})")
else:
    ok(f"{len(cido)} fitxes amb el resum, l'ens, la publicació, l'enllaç i el caption del seu procés")

print()
print(f"RESULTAT: {len(fallades)} fallada(es)." if fallades else "RESULTAT: funcionalitat verificada.")
sys.exit(1 if fallades else 0)
PY
[ $? -eq 0 ] || FAILS=$((FAILS+1))

echo
if [ "$FAILS" -eq 0 ]; then echo "RESULTAT: wiki verificada."; exit 0; fi
echo "RESULTAT: ${FAILS} comprovació(ns) fallada(es)."
exit 1
