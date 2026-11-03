#!/usr/bin/env python3
"""Importa els processos selectius del CIDO al tiddlers/ d'aquesta wiki.

Font: dataset «Convocatòries de Personal» del portal de dades obertes de la
Generalitat de Catalunya, que publica les convocatòries del CIDO (Diputació de
Barcelona). Cada registre és un procés selectiu i es converteix en un tiddler:

  * el títol és l'id de CIDO, que surt de l'enllaç cido.diba.cat/oposicions/<id>;
  * cada atribut de la font és un camp del tiddler (`resum`, `data_pub`,
    `data_darrer_anunci`, `termini_presentacio`, `codi_ens`, `nom_ens`,
    `latitud`, `longitud`, `enllac`, `font`);
  * el camp `caption` és un resum curt i llegible per a la interfície.

El cos de cada tiddler és una transclusió de «Fitxa de procés selectiu», de
manera que la presentació és una sola plantilla i no 800 còpies.

Ús:
    python3 tools/cido-import.py --wiki . --dies 7
    python3 tools/cido-import.py --wiki . --dies 7 --dry-run
    python3 tools/cido-import.py --wiki . --dies 7 --purga   # re-sincronitza la finestra

És idempotent: tornar-lo a executar amb les mateixes dades no canvia cap fitxer.
No esborra mai res tret que se li demani `--purga`, i aleshores només els
tiddlers amb l'etiqueta CIDO que ja no surten a la finestra demanada.
"""

from __future__ import annotations

import argparse
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
ETIQUETES = "CIDO convocatòria"
COS = "<<fitxa-cido>>"
MAX_CAPTION = 90
PAGINA = 5000

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
    trobat = re.search(r"/oposicions/(\d+)", url)
    return (trobat.group(1) if trobat else ""), url


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


def descarrega(dies: int, limit: int = 0) -> list[dict]:
    """Els registres publicats dins la finestra, més recents primer."""
    des_de = (datetime.date.today() - datetime.timedelta(days=dies)).isoformat()
    registres: list[dict] = []
    desplacament = 0
    while True:
        parametres = {
            "$where": f"data_pub > '{des_de}T00:00:00.000'",
            "$order": "data_pub DESC",
            "$limit": min(PAGINA, limit - len(registres)) if limit else PAGINA,
            "$offset": desplacament,
        }
        url = f"{API}?{urllib.parse.urlencode(parametres)}"
        peticio = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(peticio, timeout=90) as resposta:
            pagina = json.loads(resposta.read().decode("utf-8"))
        registres.extend(pagina)
        if len(pagina) < parametres["$limit"] or (limit and len(registres) >= limit):
            break
        desplacament += parametres["$limit"]
    return registres


def tiddler(registre: dict) -> tuple[str, str] | tuple[None, str]:
    """El .tid d'un registre, o bé (None, motiu) si no es pot convertir."""
    id_cido, enllac = id_i_enllac(registre)
    if not id_cido:
        return None, "sense id de CIDO a l'enllaç"
    resum = neteja(registre.get("resum"))
    nom_ens = neteja(registre.get("nom_ens"))
    if not resum and not nom_ens:
        return None, "sense resum ni ens"

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
    return id_cido, f"{capcalera}\n\n{COS}\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Importa les convocatòries de personal (CIDO) a la wiki.")
    ap.add_argument("--wiki", default=".", help="carpeta de la wiki (per defecte, l'actual)")
    ap.add_argument("--dies", type=int, default=7, help="finestra en dies (per defecte, 7)")
    ap.add_argument("--limit", type=int, default=0, help="nombre màxim de registres (0 = tots)")
    ap.add_argument("--purga", action="store_true",
                    help="esborra els tiddlers CIDO que ja no són dins la finestra demanada")
    ap.add_argument("--dry-run", action="store_true", help="no escriu res; només informa")
    args = ap.parse_args()

    wiki = pathlib.Path(args.wiki).resolve()
    tiddlers = wiki / "tiddlers"
    if not (tiddlers / "$__DefaultTiddlers.tid").is_file() and not list(tiddlers.glob("*.tid")):
        print(f"AVIS  {tiddlers} no sembla la carpeta de tiddlers d'una wiki", file=sys.stderr)
        return 2

    print(f"Font: {API}")
    print(f"Finestra: {args.dies} dia(es) enrere des d'avui ({datetime.date.today().isoformat()})")
    registres = descarrega(args.dies, args.limit)
    print(f"Registres a la font: {len(registres)}")

    escrits, iguals, descartats, titols = 0, 0, [], []
    for registre in registres:
        id_cido, contingut = tiddler(registre)
        if id_cido is None:
            descartats.append(contingut)
            continue
        titols.append(id_cido)
        if args.dry_run:
            continue
        desti = tiddlers / f"{id_cido}.tid"
        if desti.is_file() and desti.read_text(encoding="utf-8") == contingut:
            iguals += 1
            continue
        desti.write_text(contingut, encoding="utf-8")
        escrits += 1

    if args.dry_run:
        print(f"dry-run: escriuria {len(titols)} tiddlers")
    else:
        print(f"Tiddlers escrits: {escrits} | ja estaven igual: {iguals}")
    if descartats:
        print(f"Descartats: {len(descartats)} ({descartats[:3]})")

    if args.purga and not args.dry_run:
        dins = set(titols)
        fora = []
        for fitxer in sorted(tiddlers.glob("*.tid")):
            text = fitxer.read_text(encoding="utf-8")
            capcalera = text.split("\n\n", 1)[0]
            if f"tags: {ETIQUETES}" not in capcalera:
                continue
            if fitxer.stem in dins:
                continue
            fora.append(fitxer)
            fitxer.unlink()
        print(f"Purga: {len(fora)} tiddler(s) que ja no són a la finestra"
              + (f" ({[f.stem for f in fora[:5]]})" if fora else ""))

    return 0


if __name__ == "__main__":
    sys.exit(main())
