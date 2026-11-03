# CIDO_TW

Instància de TiddlyWiki d'aquest repositori. El contingut és wikitext: un fitxer `.tid` per
tiddler dins `tiddlers/`, que és on viu tot el desenvolupament.

## Estructura

| Carpeta | Què hi ha |
|---|---|
| `tiddlers/` | El contingut de la wiki. Un `.tid` per tiddler. |
| `proves/` | Proves de punta a punta contra el render real (`--build static`). |
| `evidencia/` | Captures abans/després, comitejades perquè es puguin veure des del PR. |
| `tags.txt` | Vocabulari d'etiquetes. Una etiqueta nova es declara aquí abans de fer-la servir. |

## Comprovacions

```bash
python3 ~/.hermes/profiles/jeremy_ruston/tools/tidcheck.py .
WIKI="$PWD" bash proves/e2e.sh
```

`tidcheck.py` valida el wikitext (títol, duplicats, camps, enllaços i macros trencades,
blocs desbalancejats, vocabulari d'etiquetes). `proves/e2e.sh` fa el build estàtic de debò i
assegura que `$:/DefaultTiddlers` no apunti a tiddlers inexistents i que cap pàgina surti amb
«Missing tiddler».

## Format d'un tiddler

```
created: 20261103184100000
title: Títol del tiddler
tags: una altra

Cos en wikitext.
```

El nom del fitxer és el títol amb `/` substituït per `_` (`$:/DefaultTiddlers` →
`$__DefaultTiddlers.tid`).
