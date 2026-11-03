#!/usr/bin/env python3
"""Importa els processos selectius del CIDO al tiddlers/ d'aquesta wiki.

Font: dataset «Convocatòries de Personal» del portal de dades obertes de la
Generalitat de Catalunya, que publica les convocatòries del CIDO (Diputació de
Barcelona). Cada registre és un procés selectiu i es converteix en un tiddler:

  * el títol és l'id de CIDO, que surt de l'enllaç cido.diba.cat/oposicions/<id>;
  * els camps que es copien de la font són `resum`, `data_pub`,
    `data_darrer_anunci`, `termini_presentacio` (a la font, `termini_presentaci_`),
    `codi_ens`, `nom_ens`, `latitud` i `longitud`, més `enllac` (l'URL del procés) i
    `font` (l'URL del dataset);
  * el camp `caption` és un resum curt i llegible per a la interfície.

La font també porta `geocoded` (les mateixes coordenades que `latitud`/`longitud`)
i dues regions calculades internes (`:@computed_region_*`): **no s'importen**.

El cos de cada tiddler és una crida a la macro `fitxa-cido`, definida a «Fitxa de
procés selectiu», de manera que la presentació és un sol lloc i no 800 còpies.

Ús:
    python3 tools/cido-import.py --wiki . --dies 7
    python3 tools/cido-import.py --wiki . --dies 7 --dry-run
    python3 tools/cido-import.py --wiki . --dies 7 --purga   # re-sincronitza la finestra

És idempotent: tornar-lo a executar amb les mateixes dades no canvia cap fitxer.
No trepitja cap tiddler que no sigui de la funcionalitat, i no esborra res tret que
se li demani `--purga` (que no es pot combinar amb `--limit` i que, abans de
començar, exigeix que la descàrrega estigui verificada com a completa i torna a
preguntar a la font per cada candidat a esborrar).
"""

from __future__ import annotations

import argparse
import collections
import datetime
import json
import pathlib
import re
import sys
import urllib.parse
import urllib.request

API = "https://analisi.transparenciacatalunya.cat/resource/a2hm-uzyj.json"
FONT = "https://analisi.transparenciacatalunya.cat/d/a2hm-uzyj"
USER_AGENT = "CIDO_TW-importer/1.0 (+https://github.com/MagicJF/CIDO_TW)"
ETIQUETA_FUNC = "CIDO"
ETIQUETES = f"{ETIQUETA_FUNC} convocatòria"
COS = "<<fitxa-cido>>"
MAX_CAPTION = 90
PAGINA = 5000
ENLLAC_PREFIX = "https://cido.diba.cat/oposicions/"
# Els enllaços de la font són exactament aquests; no n'hi ha prou que la URL contingui
# «/oposicions/», perquè un enllaç a un altre lloc acabaria escrit com si fos el procés.
ENLLAC_RE = re.compile(rf"^{re.escape(ENLLAC_PREFIX)}(\d+)$")

# Camps de la font que es copien tal com vénen, en l'ordre en què s'escriuen.
# La clau és el nom del camp al tiddler i el valor, el nom a la font.
CAMPS = (
    ("resum", "resum"),
    ("data_pub", "data_pub"),
    ("data_darrer_anunci", "data_darrer_anunci"),
    ("termini_presentacio", "termini_presentaci_"),
    ("codi_ens", "codi_ens"),
    ("nom_ens", "nom_ens"),
    ("latitud", "latitud"),
    ("longitud", "longitud"),
)
# Camps de data: es queden només els 10 caràcters de YYYY-MM-DD.
SON_DATA = {"data_pub", "data_darrer_anunci", "termini_presentacio"}


def neteja(valor) -> str:
    """Un valor de camp ha de ser una sola línia i sense espais a les puntes."""
    if valor is None:
        return ""
    return re.sub(r"\s+", " ", str(valor)).strip()


def com_data(valor) -> str:
    text = neteja(valor)
    return text[:10] if re.match(r"^\d{4}-\d{2}-\d{2}", text) else ""


def id_i_enllac(registre: dict) -> tuple[str, str]:
    """L'id de CIDO surt de l'enllaç; és la clau estable del procés selectiu."""
    enlla = registre.get("enlla")
    url = neteja(enlla.get("url") if isinstance(enlla, dict) else enlla)
    trobat = ENLLAC_RE.match(url)
    return (trobat.group(1) if trobat else ""), url


def camp(text: str, nom: str) -> str:
    """El valor d'un camp de la capçalera d'un .tid, sense confondre'l amb un camp
    que simplement contingui el text (un `other-tags: CIDO …`, per exemple)."""
    for linia in text.split("\n\n", 1)[0].splitlines():
        if linia.startswith(nom + ":"):
            return linia.split(":", 1)[1].strip()
    return ""


def etiquetes(text: str) -> list[str]:
    """Les etiquetes d'un tiddler, parsejades com ho fa TiddlyWiki: separades per espais,
    i amb claudàtors dobles quan el nom porta espais (`[[El meu tema]]`)."""
    return [a or b for a, b in re.findall(r"\[\[(.*?)\]\]|(\S+)", camp(text, "tags"))]


def es_cido(text: str) -> bool:
    """Si el tiddler és de la funcionalitat, segons el camp `tags` i no una coincidència
    de text a la capçalera."""
    return ETIQUETA_FUNC in etiquetes(text)


def caption(resum: str, nom_ens: str) -> str:
    """Un títol curt i descriptiu; el títol del tiddler és un número i no diu res."""
    if resum and nom_ens:
        text = f"{resum} · {nom_ens}"
    else:
        text = resum or nom_ens
    if len(text) <= MAX_CAPTION:
        return text
    tall = text[:MAX_CAPTION]
    if " " in tall:
        tall = tall.rsplit(" ", 1)[0]
    return tall.rstrip(" .,;·-—") + "…"


def finestra(dies: int) -> str:
    return (datetime.date.today() - datetime.timedelta(days=dies)).isoformat()


def consulta(url: str):
    peticio = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(peticio, timeout=90) as resposta:
        return json.loads(resposta.read().decode("utf-8"))


def descarrega(dies: int, limit: int = 0) -> list[dict]:
    """Els registres publicats dins la finestra, més recents primer."""
    des_de = finestra(dies)
    registres: list[dict] = []
    desplacament = 0
    while True:
        parametres = {
            "$where": f"data_pub > '{des_de}T00:00:00.000'",
            # `:id` és l'identificador únic de fila de Socrata: sense un segon criteri únic,
            # les files empatades a `data_pub` poden canviar de lloc entre pàgines i una
            # descàrrega paginada en deixa o en repeteix.
            "$order": "data_pub DESC,:id DESC",
            "$limit": min(PAGINA, limit - len(registres)) if limit else PAGINA,
            "$offset": desplacament,
        }
        pagina = consulta(f"{API}?{urllib.parse.urlencode(parametres)}")
        registres.extend(pagina)
        if len(pagina) < parametres["$limit"] or (limit and len(registres) >= limit):
            break
        desplacament += parametres["$limit"]
    return registres


def total_finestra(dies: int) -> int | None:
    """Quants registres diu la font que hi ha a la finestra. Serveix per comprovar que una
    descàrrega paginada no n'ha perdut cap abans de deixar que `--purga` esborri res."""
    parametres = {"$select": "count(*) as n", "$where": f"data_pub > '{finestra(dies)}T00:00:00.000'"}
    try:
        return int(consulta(f"{API}?{urllib.parse.urlencode(parametres)}")[0]["n"])
    except Exception as e:                                    # xarxa, format, el que sigui
        print(f"AVIS  no s'ha pogut comptar la finestra a la font: {e}", file=sys.stderr)
        return None


def encara_a_la_finestra(candidats: list[str], dies: int, lot: int = 40) -> set[str]:
    """Dels ids candidats a purgar, quins són de debò dins la finestra segons la font.

    Les pàgines d'una descàrrega paginada no són una foto fixa: si una fila desapareix de la
    font a mig camí, la fila següent salta de pàgina i el recompte final pot quadrar igualment.
    Per no esborrar un procés que és viu, cada candidat es torna a preguntar a la font, en lots.
    Si una consulta falla, l'excepció puja i no es purga res.
    """
    dins: set[str] = set()
    for i in range(0, len(candidats), lot):
        ids = candidats[i:i + lot]
        urls = ",".join(f"'{ENLLAC_PREFIX}{x}'" for x in ids)
        parametres = {
            "$select": "enlla.url",
            "$where": f"data_pub > '{finestra(dies)}T00:00:00.000' AND enlla.url in({urls})",
            "$limit": lot,
        }
        for fila in consulta(f"{API}?{urllib.parse.urlencode(parametres)}"):
            trobat = ENLLAC_RE.match(neteja(fila.get("enlla_url")))
            if trobat:
                dins.add(trobat.group(1))
    return dins


def tiddler(registre: dict, id_cido: str, enllac: str) -> tuple[str | None, str]:
    """El .tid d'un registre, o bé (None, motiu) si no es pot convertir."""
    resum = neteja(registre.get("resum"))
    nom_ens = neteja(registre.get("nom_ens"))
    if not id_cido:
        return None, "enllaç que no és del CIDO"
    if not resum or not nom_ens:
        # La fitxa i l'índex fan servir tots dos camps: mig registre no s'hi pot escriure.
        return None, "sense resum o sense ens"

    camps: list[tuple[str, str]] = [
        ("title", id_cido),
        ("caption", caption(resum, nom_ens)),
        ("tags", ETIQUETES),
    ]
    for nom_tiddler, nom_font in CAMPS:
        valor = neteja(registre.get(nom_font))
        if nom_tiddler in SON_DATA:
            valor = com_data(valor)
        if valor:
            camps.append((nom_tiddler, valor))
    camps.append(("enllac", enllac))
    camps.append(("font", FONT))

    capcalera = "\n".join(f"{nom}: {valor}" for nom, valor in camps)
    return f"{capcalera}\n\n{COS}\n", ""


def main() -> int:
    ap = argparse.ArgumentParser(description="Importa les convocatòries de personal (CIDO) a la wiki.")
    ap.add_argument("--wiki", default=".", help="carpeta de la wiki (per defecte, l'actual)")
    ap.add_argument("--dies", type=int, default=7, help="finestra en dies (per defecte, 7; mínim 1)")
    ap.add_argument("--limit", type=int, default=0, help="nombre màxim de registres (0 = tots)")
    ap.add_argument("--purga", action="store_true",
                    help="esborra els tiddlers CIDO que ja no són dins la finestra demanada "
                         "(no es pot combinar amb --limit)")
    ap.add_argument("--dry-run", action="store_true", help="no escriu res; només informa")
    args = ap.parse_args()

    # Amb --limit, la descàrrega no és la finestra sencera: purgar-hi esborraria processos
    # que sí que hi pertanyen. I amb una finestra de zero dies o negativa, la consulta no
    # torna res i la purga esborraria TOTS els processos.
    if args.purga and args.limit:
        print("Error: --purga i --limit no poden anar junts; la purga esborraria processos "
              "que sí que són dins la finestra.", file=sys.stderr)
        return 2
    if args.dies < 1:
        print("Error: --dies ha de ser 1 o més; una finestra buida faria esborrar-ho tot.",
              file=sys.stderr)
        return 2

    wiki = pathlib.Path(args.wiki).resolve()
    tiddlers = wiki / "tiddlers"
    if not (tiddlers / "$__DefaultTiddlers.tid").is_file() and not list(tiddlers.glob("*.tid")):
        print(f"AVIS  {tiddlers} no sembla la carpeta de tiddlers d'una wiki", file=sys.stderr)
        return 2

    print(f"Font: {API}")
    print(f"Finestra: {args.dies} dia(es) enrere des d'avui ({datetime.date.today().isoformat()})")
    registres = descarrega(args.dies, args.limit)
    print(f"Registres a la font: {len(registres)}")

    # Un id repetit vol dir que la descàrrega paginada ha perdut el fil (o que la font ha
    # canviat a mig camí): val més dir-ho que escriure un tiddler damunt d'un altre.
    comptes = collections.Counter(id_i_enllac(r)[0] for r in registres)
    repetits = [i for i, n in comptes.items() if n > 1 and i]
    if repetits:
        print(f"AVIS  {len(repetits)} id(s) repetit(s) a la descàrrega (ex. {repetits[:3]}); "
              f"es queda la primera aparició, que és la més nova")

    escrits, iguals, descartats, alienes, repetits_al_escriure = 0, 0, [], [], []
    ids_finestra: list[str] = []      # tots els ids descarregats, convertibles o no
    vistos: set[str] = set()
    for registre in registres:
        id_cido, enllac = id_i_enllac(registre)
        if id_cido:
            ids_finestra.append(id_cido)
        contingut, motiu = tiddler(registre, id_cido, enllac)
        if contingut is None:
            descartats.append(motiu)
            continue
        if id_cido in vistos:
            # La descàrrega va de més nova a més vella: el que ja s'ha escrit és el bo.
            repetits_al_escriure.append(id_cido)
            continue
        vistos.add(id_cido)
        desti = tiddlers / f"{id_cido}.tid"
        if desti.is_file():
            text = desti.read_text(encoding="utf-8")
            if not es_cido(text):
                # Un tiddler aliè amb un nom numèric: no es trepitja mai.
                alienes.append(desti.name)
                continue
            if text == contingut:
                iguals += 1
                continue
        if not args.dry_run:
            desti.write_text(contingut, encoding="utf-8")
        escrits += 1

    if args.dry_run:
        print(f"dry-run: escriuria {escrits} tiddlers "
              f"({iguals} ja estaven igual, {len(alienes)} aliens, {len(descartats)} descartats)")
    else:
        print(f"Tiddlers escrits: {escrits} | ja estaven igual: {iguals}")
    if alienes:
        print(f"AVIS  {len(alienes)} fitxer(s) amb nom de procés que no són de la funcionalitat; "
              f"no s'han tocat ({alienes[:3]})")
    if repetits_al_escriure:
        print(f"      {len(repetits_al_escriure)} aparició(ns) vella(es) dels mateixos ids saltades")
    if descartats:
        print(f"Descartats: {len(descartats)} ({descartats[:3]})")

    if args.purga and not args.dry_run:
        # Abans d'esborrar res: la descàrrega ha d'estar sencera i verificada. Una pàgina
        # pot perdre una fila si algú publica durant la descàrrega, i llavors la purga
        # trauria del wiki un procés que sí que és dins la finestra.
        problemes = []
        if len(ids_finestra) != len(registres):
            # Qualsevol fila descarregada que no doni un id deixa el seu procés fora del
            # conjunt que es conserva: purgar amb aquest forat esborraria un procés viu.
            problemes.append(f"{len(registres) - len(ids_finestra)} registre(s) sense id de CIDO "
                             "utilitzable (ha canviat la forma de la font?)")
        if repetits:
            problemes.append(f"{len(repetits)} id(s) repetit(s)")
        total = total_finestra(args.dies)
        if total is None:
            problemes.append("no s'ha pogut comprovar el total de la finestra contra la font")
        elif total != len(registres):
            problemes.append(f"la font diu {total} registres a la finestra i se n'han "
                             f"descarregat {len(registres)}")
        if problemes:
            print("AVIS  no es purga: " + "; ".join(problemes), file=sys.stderr)
        else:
            if total == 0:
                # Una finestra buida és una resposta legítima (un dia sense publicacions),
                # i vol dir que cap procés vell no hi pertany: es diu ben clar.
                print(f"AVIS  la finestra és buida segons la font (0 registres): "
                      f"es treuen tots els processos que hi hagi")
            dins = set(ids_finestra)
            candidats = []
            for fitxer in sorted(tiddlers.glob("*.tid")):
                if fitxer.stem in dins:
                    continue
                if not es_cido(fitxer.read_text(encoding="utf-8")):
                    continue
                candidats.append(fitxer.stem)
            # Segona xarxa: cada candidat es torna a preguntar a la font abans de l'unlink.
            try:
                vius = encara_a_la_finestra(candidats, args.dies) if candidats else set()
            except Exception as e:
                print(f"AVIS  no es purga: no s'han pogut tornar a comprovar els candidats a la "
                      f"font ({e})", file=sys.stderr)
                vius = None
            if vius is not None:
                if vius:
                    print(f"AVIS  {len(vius)} procés(os) que la font encara dona dins la finestra "
                          f"i no han arribat a la descàrrega: no s'esborren ({sorted(vius)[:3]})")
                fora = [i for i in candidats if i not in vius]
                for i in fora:
                    (tiddlers / f"{i}.tid").unlink()
                print(f"Purga: {len(fora)} tiddler(s) que ja no són a la finestra"
                      + (f" ({fora[:5]})" if fora else ""))

    return 0


if __name__ == "__main__":
    sys.exit(main())
