#!/usr/bin/env bash
# Prova de punta a punta de la wiki de convocatòries del CIDO.
#
# Comprova el COMPORTAMENT, no l'aspecte:
#   1. la sincronització (l'ordre de consola) llegeix el CSV de prova i desa el que hi ha
#   2. el contracte de dades de cada tiddler creat (camps, caption, dates, entitats, cos)
#   3. el que no es pot llegir del CSV es diu i no es desa
#   4. la segona passada no toca cap fitxer (idempotència)
#   5. el que ha escrit la persona (estat, notes) sobreviu a la sincronització
#   6. la ruta HTTP del botó: el resum en JSON, la redirecció i el cas del CSV que falta
#   7. el build estàtic i el render: $:/DefaultTiddlers, cap «Missing tiddler», el tauler,
#      les vistes agrupades i la fitxa de cada convocatòria amb les dades del seu procés
#
# Ús: proves/e2e.sh            (o WIKI=/tmp/tw-branca proves/e2e.sh)
set -uo pipefail

WIKI="${WIKI:-$(cd "$(dirname "$0")/.." && pwd)}"
FAILS=0
ok()  { printf 'PASS  %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; FAILS=$((FAILS+1)); }

TW="${TW:-}"
[ -z "$TW" ] && TW="$(command -v tiddlywiki 2>/dev/null || true)"
[ -z "$TW" ] && [ -x "${HOME}/.npm-global/bin/tiddlywiki" ] && TW="${HOME}/.npm-global/bin/tiddlywiki"
if [ -z "$TW" ] || [ ! -x "$TW" ]; then
	echo "FAIL  no s'ha trobat tiddlywiki (npm i -g tiddlywiki, o passa TW=<ruta>)" >&2
	exit 1
fi
[ -f "${WIKI}/proves/cido_24h_exemple.csv" ] || {
	echo "FAIL  falta proves/cido_24h_exemple.csv" >&2; exit 1; }

TMP="$(mktemp -d /tmp/e2e-cido.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

echo "== còpia temporal de la wiki =="
mkdir -p "${TMP}/wiki"
cp -r "${WIKI}/tiddlywiki.info" "${WIKI}/tiddlers" "${WIKI}/plugins" "${TMP}/wiki/" 2>/dev/null
[ -f "${WIKI}/tags.txt" ] && cp "${WIKI}/tags.txt" "${TMP}/wiki/"
cp "${WIKI}/proves/cido_24h_exemple.csv" "${TMP}/wiki/cido_24h.csv"
rm -f "${TMP}/wiki/tiddlers/Estat de la sincronitzacio.tid" "${TMP}/wiki/tiddlers/\$__StoryList.tid"
ok "còpia a ${TMP}/wiki (la wiki viva no es toca)"

echo "== 1. sincronització amb l'ordre de consola =="
"$TW" "${TMP}/wiki" --cido-sincronitza >"${TMP}/sincro-1.txt" 2>"${TMP}/sincro-1.err"
if grep -q "Convocatòries: 4 · creades: 4 · actualitzades: 0 · sense canvis: 0 · errors: 3" "${TMP}/sincro-1.txt"; then
	ok "4 convocatòries creades del CSV de prova, 3 registres amb error"
else
	bad "el resum de la sincronització no és l'esperat"; sed 's/^/      /' "${TMP}/sincro-1.txt"
fi
if grep -q "El registre 7 té 32 cel·les" "${TMP}/sincro-1.err" && grep -q "El registre 6 té 20 cel·les" "${TMP}/sincro-1.err"; then
	ok "les files que no encaixen amb la capçalera es diuen (error i avís)"
else
	bad "no s'ha dit que hi hagi files que no encaixen"; sed 's/^/      /' "${TMP}/sincro-1.err"
fi

echo "== 2. contracte de dades dels tiddlers creats =="
python3 - "${TMP}/wiki" <<'PY'
import pathlib, re, sys
T = pathlib.Path(sys.argv[1]) / "tiddlers"
fallades = []
def ok(m): print(f"PASS  {m}")
def bad(m):
    print(f"FAIL  {m}"); fallades.append(m)
def camps(f):
    d = {}
    for linia in f.read_text(encoding="utf-8").splitlines():
        if not linia.strip(): break
        if ":" in linia:
            k, v = linia.split(":", 1); d[k.strip()] = v.strip()
    return d
def cos(f):
    t = f.read_text(encoding="utf-8")
    return t.split("\n\n", 1)[1].strip() if "\n\n" in t else ""
def mira(nom, **esperat):
    f = T / f"{nom}.tid"
    if not f.is_file():
        bad(f"no s'ha creat {nom}"); return None
    c = camps(f)
    for k, v in esperat.items():
        if c.get(k, "") != v:
            bad(f"{nom}: {k}={c.get(k,'')!r} i s'esperava {v!r}")
    return c

c1 = mira("20260101O1", title="20260101O1", caption="1 plaça d'Auxiliar administratiu · Ajuntament de Prova",
          data_pub="2026-11-03", termini="2026-12-01", ens="Ajuntament de Prova",
          canal_origen="obertes", font="cido_24h.csv", tags="CIDO convocatòria",
          data_publicacio="Tue, 03 Nov 2026")
if c1:
    ordre = ("canal_origen|data_publicacio|organisme|placa|acces_al_tramit|altres_requisits|expedient|"
             "finalitzacio_de_presentacio_de_sollicituds|grup_de_titulacio_o_assimilat|identificador|"
             "materies|sistema_de_seleccio|tipus_de_personal|titulacio_requerida|web_de_l_ens_convocant|"
             "enllacos_documents|enllacos_butlletins|resum_rss|tots_els_canals|url")
    if c1.get("cidocamps") == ordre:
        ok("20260101O1: els 20 camps amb valor, i en l'ordre de la capçalera")
    else:
        bad(f"20260101O1: cidocamps={c1.get('cidocamps')!r}")
    if cos(T / "20260101O1.tid") == "<<fitxa-cido>>":
        ok("20260101O1: el cos és la crida a la plantilla")
    else:
        bad("20260101O1: el cos no és la crida a la plantilla")
    if "bases.pdf" in c1.get("enllacos_documents", "") and "annex.pdf" in c1.get("enllacos_documents", ""):
        ok("20260101O1: els enllaços de documents s'han desat sencers")
    else:
        bad("20260101O1: els enllaços de documents no hi són")

c2 = mira("20260102O2", title="20260102O2", data_pub="2026-11-02", termini="2026-12-15",
          materies="Obres / Manteniment, Serveis socials")
if c2:
    if 0 < len(c2.get("caption", "")) <= 90 and c2.get("caption", "").endswith("…"):
        ok("20260102O2: caption tallat per paraula sencera i de 90 caràcters o menys")
    else:
        bad(f"20260102O2: caption={c2.get('caption')!r} ({len(c2.get('caption',''))} caràcters)")
    if "expedient" not in c2:
        ok("20260102O2: la columna buida no s'ha escrit com a camp")
    else:
        bad("20260102O2: s'ha escrit un camp buit")

c3 = mira("20260103O3", title="20260103O3", ens="Ajuntament de Tercer",
          acces_al_tramit="https://exemple.test/tr%C3%A0mit?a=1&b=2",
          materies="Neteja d'edificis & manteniment",
          observacions="Primera línia segona línia", placa="1 plaça de Neteja d'edificis")
if c3:
    if "termini" not in c3 and "sistema_de_seleccio" not in c3:
        ok("20260103O3: sense termini ni sistema de selecció, que la font no portava")
    else:
        bad("20260103O3: hi ha camps que la font no portava")
    if "&amp;" not in c3.get("acces_al_tramit", "") and "&#039;" not in c3.get("materies", ""):
        ok("20260103O3: les entitats HTML del col·lector s'han desfet")
    else:
        bad("20260103O3: queden entitats HTML en cru")

c4 = mira("20260107O7", title="20260107O7", caption="1 plaça curta")
if c4:
    if "tots_els_canals" not in c4 and "url" not in c4:
        ok("20260107O7: la fila curta s'ha desat amb els camps del final buits")
    else:
        bad("20260107O7: hi ha camps que no haurien de ser-hi")

if (T / "20260106O6.tid").is_file():
    bad("s'ha desat una fila amb les columnes desplaçades (20260106O6)")
else:
    ok("la fila amb comes sense cometes no s'ha desat")

print()
print(f"RESULTAT: {len(fallades)} fallada(es) al contracte de dades." if fallades else "RESULTAT: contracte de dades verificat.")
sys.exit(1 if fallades else 0)
PY
[ $? -eq 0 ] || FAILS=$((FAILS+1))

echo "== 3. idempotència =="
python3 - "${TMP}/wiki" "$TW" <<'PY'
import hashlib, pathlib, subprocess, sys
wiki = pathlib.Path(sys.argv[1])
def h():
    return {f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in (wiki / "tiddlers").glob("*.tid")}
abans = h()
subprocess.run([sys.argv[2], str(wiki), "--cido-sincronitza"], capture_output=True)
despres = h()
# L'estat de la sincronització porta la marca de temps i canvia sempre: no compta.
salta = lambda k: k.startswith("Estat de la sincronitzacio")
canviats = [k for k in despres if abans.get(k) != despres[k] and not salta(k)]
nous = sorted(k for k in set(despres) - set(abans) if not salta(k))
perduts = sorted(k for k in set(abans) - set(despres) if not salta(k))
if canviats or nous or perduts:
    print(f"FAIL  la segona passada ha tocat fitxers: {canviats}{nous}{perduts}"); sys.exit(1)
print(f"PASS  la segona passada sobre el mateix CSV no toca cap dels {len(abans)} tiddlers")
sys.exit(0)
PY
[ $? -eq 0 ] || FAILS=$((FAILS+1))

echo "== 4. el seguiment de la persona sobreviu =="
python3 - "${TMP}/wiki/tiddlers/20260101O1.tid" <<'PY'
import pathlib, sys
f = pathlib.Path(sys.argv[1])
t = f.read_text(encoding="utf-8")
f.write_text(t.replace("title: 20260101O1", "title: 20260101O1\nestat: interessant\nnotes: pendent de mirar-ho"))
print("PASS  marca escrita (estat + notes) sobre 20260101O1")
PY
"$TW" "${TMP}/wiki" --cido-sincronitza >"${TMP}/sincro-3.txt" 2>&1
if grep -q "estat: interessant" "${TMP}/wiki/tiddlers/20260101O1.tid" && grep -q "notes: pendent de mirar-ho" "${TMP}/wiki/tiddlers/20260101O1.tid"; then
	ok "la sincronització no ha trepitjat el camp estat ni les notes"
else
	bad "la sincronització ha esborrat el seguiment de la persona"
fi

echo "== 5. la ruta HTTP del botó =="
PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
"$TW" "${TMP}/wiki" --listen "host=127.0.0.1" "port=${PORT}" anon-username=anonim "writers=(anon)" \
	>"${TMP}/servidor.log" 2>&1 &
SRV=$!
code=""
for _ in $(seq 1 40); do
	code=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:${PORT}/" 2>/dev/null)
	[ "$code" = "200" ] && break
	sleep 1
done
if [ "${code:-}" != "200" ]; then
	bad "el servidor no respon al port ${PORT}"; tail -3 "${TMP}/servidor.log" | sed 's/^/      /'
else
	ok "servidor en marxa al port ${PORT}"
	curl -s -m 30 "http://127.0.0.1:${PORT}/cido/sincronitza?format=json" >"${TMP}/ruta.json" 2>/dev/null
	if python3 - "${TMP}/ruta.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["entrades"] == 4 and d["creades"] == 0 and d["sense_canvis"] == 4, d
assert d["errors"] == ["El registre 7 té 32 cel·les i la capçalera en té 25: segur que hi ha una coma sense cometes. No s'ha desat.",
                       "El registre 4 no porta «identificador».",
                       "L'identificador «20260101O1» surt més d'una vegada; només se n'ha fet servir la primera."], d["errors"]
print("PASS  la ruta torna el mateix resum que l'ordre de consola")
PY
	then :; else bad "el JSON de la ruta no és l'esperat"; sed 's/^/      /' "${TMP}/ruta.json"; fi
	codi=$(curl -s -o /dev/null -m 30 -D "${TMP}/capcaleres.txt" -w '%{http_code}' "http://127.0.0.1:${PORT}/cido/sincronitza")
	if [ "$codi" = "302" ] && grep -qi '^location: /?v=' "${TMP}/capcaleres.txt"; then
		ok "el botó redirigeix a la wiki amb marca de temps (302 + Location)"
	else
		bad "la redirecció de la ruta no és l'esperada (${codi})"; sed 's/^/      /' "${TMP}/capcaleres.txt"
	fi
	if grep -q "Última sincronització" "${TMP}/wiki/tiddlers/Estat de la sincronitzacio.tid" 2>/dev/null; then
		ok "la ruta ha deixat l'estat de la sincronització a la wiki"
	else
		bad "la ruta no ha escrit l'estat de la sincronització"
	fi
	mv "${TMP}/wiki/cido_24h.csv" "${TMP}/wiki/cido_24h.csv.fora"
	codi=$(curl -s -o "${TMP}/sense-csv.html" -m 30 -w '%{http_code}' "http://127.0.0.1:${PORT}/cido/sincronitza")
	mv "${TMP}/wiki/cido_24h.csv.fora" "${TMP}/wiki/cido_24h.csv"
	if [ "$codi" = "500" ] && grep -q "cido_24h.csv" "${TMP}/sense-csv.html"; then
		ok "sense CSV la ruta respon 500 i diu quin fitxer falta"
	else
		bad "sense CSV la ruta hauria de dir que falta el fitxer (${codi})"
	fi
fi
kill "$SRV" 2>/dev/null
wait "$SRV" 2>/dev/null

echo "== 6. build estàtic segons el tiddlywiki.info del repositori =="
if "$TW" "${TMP}/wiki" --build static >"${TMP}/build.log" 2>&1; then
	ok "build static completat"
else
	bad "el build ha fallat"; tail -5 "${TMP}/build.log" | sed 's/^/      /'; exit 1
fi
# Les quatre convocatòries del CSV de prova s'han de renderitzar expressament: així el
# contracte de la fitxa es comprova sobre les dades que ha creat aquesta mateixa prova i no
# només sobre les que ja eren al repositori.
"$TW" "${TMP}/wiki" --render "[[20260101O1]] [[20260102O2]] [[20260103O3]] [[20260107O7]]" \
	"[encodeuricomponent[]addprefix[static/]addsuffix[.html]]" text/plain \
	"$:/core/templates/static.tiddler.html" >>"${TMP}/build.log" 2>&1 \
	&& ok "pàgines de les quatre convocatòries del CSV de prova" \
	|| bad "no s'han pogut renderitzar les convocatòries del CSV de prova"

python3 - "${TMP}/wiki" <<'PY'
import html, pathlib, re, sys, urllib.parse
wiki = pathlib.Path(sys.argv[1]); static = wiki / "output" / "static"
fallades = []
def ok(m): print(f"PASS  {m}")
def bad(m):
    print(f"FAIL  {m}"); fallades.append(m)
def camps(f):
    d = {}
    for linia in f.read_text(encoding="utf-8").splitlines():
        if not linia.strip(): break
        if ":" in linia:
            k, v = linia.split(":", 1); d[k.strip()] = v.strip()
    return d
def text(raw):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", raw)))
def pagina(t):
    return static / (urllib.parse.quote(t, safe="") + ".html")

info = {f: camps(f) for f in sorted((wiki / "tiddlers").glob("*.tid"))}
titols = {f: c.get("title", "").strip() for f, c in info.items()}
cido = {c.get("title", ""): c for c in info.values() if "CIDO" in c.get("tags", "").split()}

# $:/DefaultTiddlers no pot apuntar enlloc que no hi sigui
cos = (wiki / "tiddlers" / "$__DefaultTiddlers.tid").read_text(encoding="utf-8").split("\n\n", 1)
referits = re.findall(r"\[\[(.+?)\]\]", cos[1] if len(cos) > 1 else "")
existents = set(titols.values())
for r in referits:
    if r in existents: ok(f"«{r}» (a $:/DefaultTiddlers) existeix")
    else: bad(f"«{r}» és a $:/DefaultTiddlers i no existeix")
if not referits: bad("no s'ha pogut llegir cap referència de $:/DefaultTiddlers")

# Cada tiddler de la interfície té pàgina, i cap pàgina diu «Missing tiddler»
sense_pagina, amb_missing, n_pag = [], [], 0
for f, t in titols.items():
    if t.startswith("$:/"): continue
    p = pagina(t)
    if not p.is_file():
        sense_pagina.append(t)
        continue
    n_pag += 1
    if "Missing tiddler" in p.read_text(encoding="utf-8"): amb_missing.append(t)
if sense_pagina: bad(f"{len(sense_pagina)} tiddler(s) sense pàgina (ex. {sense_pagina[:3]})")
else: ok(f"{n_pag} tiddlers, tots amb la seva pàgina")
if amb_missing: bad(f"{len(amb_missing)} pàgina(es) amb «Missing tiddler» (ex. {amb_missing[:3]})")
else: ok("cap pàgina diu «Missing tiddler»")

# El tauler: el compte, el botó de sincronitzar i les vistes
tauler = pagina("Tauler CIDO")
if not tauler.is_file():
    bad("no s'ha generat la pàgina del tauler")
else:
    raw = tauler.read_text(encoding="utf-8")
    declarat = re.search(r"Convocatòries\s+(\d+)", text(raw))
    if not declarat: bad("el tauler no diu quantes convocatòries hi ha")
    elif int(declarat.group(1)) != len(cido): bad(f"el tauler diu {declarat.group(1)} convocatòries i n'hi ha {len(cido)}")
    else: ok(f"el tauler declara {len(cido)} convocatòries, les que hi ha")
    if 'href="/cido/sincronitza"' in raw: ok("el botó de sincronitzar és al tauler, amb l'enllaç de la ruta")
    else: bad("el tauler no porta el botó de sincronitzar")
    vistes = {c["title"] for c in info.values() if "vista" in c.get("tags", "").split()}
    enllacos = set()
    for etiqueta in re.findall(r"<a\b[^>]*tc-tiddlylink-resolves[^>]*>", raw):
        m = re.search(r'href="([^"]+)"', etiqueta)
        # El build estàtic dobla la codificació dels noms (tv-wikilink-template).
        if m: enllacos.add(urllib.parse.unquote(urllib.parse.unquote(m.group(1)))[:-5])
    faltes = sorted(vistes - enllacos)
    if faltes: bad(f"{len(faltes)} vista(es) sense enllaç al tauler (ex. {faltes[:3]})")
    else: ok(f"el tauler enllaça les {len(vistes)} vistes")

# Les vistes agrupades: grups, i la llista sencera dins dels grups
# Cada vista agrupada ha de treure els grups i una fila per cada convocatòria que
# PORTI aquell camp (una convocatòria sense termini, per exemple, no surt a la vista de terminis).
vistes_agrupades = {"Per grup de titulació": "grup_de_titulacio_o_assimilat", "Per matèries": "materies",
                    "Per ens convocant": "ens", "Per termini de presentació": "termini"}
for nom, camp in vistes_agrupades.items():
    p = pagina(nom)
    if not p.is_file():
        bad(f"no s'ha generat la pàgina de la vista «{nom}»"); continue
    raw = p.read_text(encoding="utf-8")
    grups = re.findall(r'<h2 class="cidogrup">(.*?)</h2>', raw, re.S)
    esperades = sum(1 for c in cido.values() if c.get(camp))
    files = raw.count("<tr><td>")
    if not grups: bad(f"la vista «{nom}» no ha tret cap grup")
    elif files != esperades: bad(f"la vista «{nom}» té {files} files i n'esperàvem {esperades} (les que porten «{camp}»)")
    else: ok(f"vista «{nom}»: {len(grups)} grups i les {files} convocatòries que porten el camp")

# Cada fitxa renderitzada porta les dades del SEU procés
mostra = [t for t in cido if pagina(t).is_file()]
if len(mostra) < 12:
    bad(f"només s'han renderitzat {len(mostra)} fitxes; n'esperàvem almenys 12")
malament = []
for t in mostra:
    c = cido[t]; raw = pagina(t).read_text(encoding="utf-8"); pla = html.unescape(raw)
    h1 = re.search(r'<div class="tc-tiddler-body[^"]*">\s*<h1[^>]*>(.*?)</h1>', raw, re.S)
    if not h1: malament.append(f"{t}: sense encapçalament")
    elif html.unescape(re.sub(r"<[^>]+>", "", h1.group(1))).strip() != c.get("caption"):
        malament.append(f"{t}: l'encapçalament no és el caption")
    for camp in ("identificador", "ens"):
        if c.get(camp) and c[camp] not in pla:
            malament.append(f"{t}: no hi surt el camp {camp}")
    if c.get("url") and c["url"] not in pla:
        malament.append(f"{t}: no hi surt l'enllaç del procés")
    if 'data-marca="interessant"' not in raw or 'data-marca="sollicitada"' not in raw:
        malament.append(f"{t}: sense els botons de seguiment")
    if "<textarea" not in raw:
        malament.append(f"{t}: sense el camp de notes")
    if "cidofitxa" not in raw:
        malament.append(f"{t}: sense la taula de tots els camps")
if malament: bad(f"{len(malament)} fitxa(es) incorrectes (ex. {malament[:3]})")
else: ok(f"{len(mostra)} fitxes amb el caption, els camps, els botons i les notes del seu procés")

# El seguiment: la convocatòria marcada a la fase 4 ha de sortir amb les seves dades, no
# només comptada (un filtre `get[estat]` hi posa el VALOR com a títol i deixa la fila buida).
seguiment = pagina("El meu seguiment")
if not seguiment.is_file():
    bad("no s'ha generat la pàgina d'El meu seguiment")
else:
    raw = seguiment.read_text(encoding="utf-8")
    pla = html.unescape(raw)
    caption = cido.get("20260101O1", {}).get("caption", "")
    if "Interessants" not in pla:
        bad("El meu seguiment no té l'apartat d'interessants")
    elif caption not in pla:
        bad("la convocatòria marcada com a interessant no surt amb el seu caption a El meu seguiment")
    elif "sense cap marca" not in pla:
        bad("El meu seguiment no diu quantes convocatòries queden sense marca")
    elif not re.search(rf"Són\s+{len(cido) - 1}\s+convocatòries sense cap marca", text(raw)):
        bad(f"El meu seguiment no diu que en queden {len(cido) - 1} sense marca")
    else:
        ok("El meu seguiment llista la convocatòria marcada amb les seves dades")

# El contracte dels botons de seguiment: els widgets d'acció fan servir $field/$value, i un
# atribut sense $ es desaria com un CAMP (comprovat: `field="estat"` escrivia un camp `field`).
plantilla = (wiki / "tiddlers" / "Fitxa de convocatoria.tid").read_text(encoding="utf-8")
accions = re.findall(r"<\$action-setfield([^/>]*)/>", plantilla)
if len(accions) != 4:
    bad(f"la fitxa hauria de tenir 4 botons de seguiment i en té {len(accions)}")
else:
    dolents = [a for a in accions if "$field=\"estat\"" not in a or "$value=" not in a]
    sense_dollar = [a for a in accions if re.search(r'(?<!\$)\b(field|value)=', a)]
    if dolents: bad(f"{len(dolents)} botó(ns) de seguiment sense $field=\"estat\" o sense $value")
    elif sense_dollar: bad(f"{len(sense_dollar)} botó(ns) amb un atribut sense $, que s'escriuria com un camp: {sense_dollar[0]!r}")
    else: ok("els 4 botons de seguiment fan servir $field i $value")

# El diccionari d'etiquetes ha de cobrir les columnes del CSV
caps = (wiki / "cido_24h.csv").read_text(encoding="utf-8").split("\n")[0].split(",")
dic = info.get(wiki / "tiddlers" / "Camps de les convocatories.tid", {})
faltes = [c for c in caps if c and c not in dic]
if faltes: bad(f"el diccionari de camps no cobreix {faltes}")
else: ok("el diccionari de camps cobreix totes les columnes del CSV")

print()
print(f"RESULTAT: {len(fallades)} fallada(es) al render." if fallades else "RESULTAT: render verificat.")
sys.exit(1 if fallades else 0)
PY
[ $? -eq 0 ] || FAILS=$((FAILS+1))

echo
if [ "$FAILS" -eq 0 ]; then echo "RESULTAT: wiki verificada."; exit 0; fi
echo "RESULTAT: ${FAILS} comprovació(ns) fallada(es)."
exit 1
