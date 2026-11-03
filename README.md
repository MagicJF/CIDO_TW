# CIDO_TW

Instància de TiddlyWiki d'aquest repositori. El contingut és wikitext: un fitxer `.tid` per
tiddler dins `tiddlers/`, que és on viu tot el desenvolupament.

## Estructura

| Carpeta | Què hi ha |
|---|---|
| `tiddlers/` | El contingut de la wiki. Un `.tid` per tiddler. |
| `tools/` | Eines del repositori. Ara, l'importador de dades del CIDO. |
| `proves/` | Proves de punta a punta contra el render real (`--build static`). |
| `evidencia/` | Captures abans/després, comitejades perquè es puguin veure des del PR. |
| `tags.txt` | Vocabulari d'etiquetes. Una etiqueta nova es declara aquí abans de fer-la servir. |

## Convocatòries de personal (CIDO)

Els processos selectius publicats al CIDO (Diputació de Barcelona) entren a la wiki amb un
tiddler per procés: el títol és l'id de CIDO i cada atribut de la font és un camp. La font és
el dataset
[Convocatòries de Personal](https://analisi.transparenciacatalunya.cat/d/a2hm-uzyj) del portal
de dades obertes de la Generalitat de Catalunya.

```bash
python3 tools/cido-import.py --wiki . --dies 7            # importa la finestra
python3 tools/cido-import.py --wiki . --dies 7 --dry-run  # mira-ho sense escriure
python3 tools/cido-import.py --wiki . --dies 7 --purga    # i treu el que ja no hi és
```

L'importador és idempotent: tornar-lo a executar amb les mateixes dades no toca cap fitxer.
No esborra res si no se li demana `--purga`.

Camps de cada tiddler: `title` (id de CIDO), `caption` (títol curt per a la interfície),
`tags` (`CIDO convocatòria`), `resum`, `data_pub`, `data_darrer_anunci`,
`termini_presentacio`, `codi_ens`, `nom_ens`, `latitud`, `longitud`, `enllac` i `font`.

La fitxa que es veu al cos de cada procés surt d'una sola macro, `fitxa-cido`, definida a
[[Fitxa de procés selectiu]] i etiquetada `$:/tags/Macro`; l'índex és
[[Convocatòries de personal (CIDO)]].

## Comprovacions

```bash
python3 ~/.hermes/profiles/jeremy_ruston/tools/tidcheck.py .
WIKI="$PWD" bash proves/e2e.sh
```

`tidcheck.py` valida el wikitext (títol, duplicats, camps, enllaços i macros trencades,
blocs desbalancejats, vocabulari d'etiquetes). `proves/e2e.sh` fa el build estàtic de debò i
comprova que `$:/DefaultTiddlers` no apunti a tiddlers inexistents, que cap pàgina surti amb
«Missing tiddler», que cada procés CIDO dugui els camps que la fitxa fa servir, que l'índex
enllaci tots els processos amb el seu caption, i que cada fitxa renderitzi les dades del seu
propi procés.

## Format d'un tiddler

```
created: 20261103184100000
title: Títol del tiddler
tags: una altra

Cos en wikitext.
```

El nom del fitxer és el títol amb `/` substituït per `_` (`$:/DefaultTiddlers` →
`$__DefaultTiddlers.tid`).
