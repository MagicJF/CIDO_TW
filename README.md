# CIDO_TW

Instància de TiddlyWiki d'aquest repositori. El contingut és wikitext: un fitxer `.tid` per
tiddler dins `tiddlers/`, que és on viu tot el desenvolupament.

La wiki és un **visor de convocatòries de personal del CIDO**: cada convocatòria és un tiddler,
es pot cercar, filtrar, agrupar i seguir, i un botó torna a llegir el CSV del dia i actualitza
el que calgui.

## Estructura

| Carpeta | Què hi ha |
|---|---|
| `tiddlers/` | El contingut de la wiki: la interfície i una convocatòria per tiddler. |
| `plugins/cido-sync/` | El connector que llegeix el CSV i desa els tiddlers. |
| `proves/` | Prova de punta a punta i el CSV d'exemple. |
| `evidencia/` | Captures abans/després, comitejades perquè es puguin veure des del PR. |
| `tags.txt` | Vocabulari d'etiquetes. Una etiqueta nova es declara aquí abans de fer-la servir. |

## El feed de convocatòries

La font és `cido_24h.csv`, a l'arrel de la wiki: una fila per convocatòria i una columna per
dada, amb `identificador` com a clau. El genera el col·lector del CIDO (canals RSS i fitxes
dels processos) cada 24 hores; el fitxer i el col·lector viuen fora del repositori, perquè el
que es publica són els tiddlers.

La sincronització converteix cada fila en un tiddler:

* el **títol** és l'`identificador` (el número de referència de la font);
* el **caption** és la placa i l'ens, curt, perquè les llistes diguin què és cada cosa;
* **cada columna del CSV és un camp** amb el mateix nom que a la font, i el tiddler apunta a
  `cidocamps` quins camps porta, en l'ordre de la capçalera (així la fitxa s'adapta tota sola
  si el col·lector afegeix una columna);
* hi ha cinc camps calculats: `ens` (del resum del canal, perquè la columna `organisme` no
  sempre l'encerta), `data_pub` i `termini` (les dates en AAAA-MM-DD, per poder-les ordenar),
  `caption` i `font`;
* el cos és `<<fitxa-cido>>`, la plantilla de [[Fitxa de convocatòria]].

El diccionari de camps i etiquetes és a [[Camps de les convocatòries]].

### Com es sincronitza

Amb el botó de la wiki (el tauler i [[Com sincronitzar-ho]]) o sense navegador:

```bash
tiddlywiki . --cido-sincronitza                       # ordre de consola
curl -s 'http://127.0.0.1:<port>/cido/sincronitza?format=json'   # la ruta, en JSON
```

El botó és un enllaç a `GET /cido/sincronitza`, una ruta del servidor de TiddlyWiki que
defineix el connector: fa la feina al servidor, desa els tiddlers, deixa el resum a
[[Estat de la sincronització]] i torna a la wiki amb una marca de temps perquè el navegador no
ensenyi la còpia vella. Si el CSV no hi és, respon amb el motiu i no toca res.

L'ordre de consola i la ruta comparteixen la mateixa lògica (`plugins/cido-sync/sincronitzacio.js`),
així que no hi ha dues maneres de fer el mateix que es puguin separar.

La sincronització **no esborra mai res** (si una convocatòria desapareix del CSV, es queda a la
wiki: fa d'arxiu) i **no hi posa marques de temps**, de manera que dues passades amb el mateix
CSV deixen els fitxers exactament iguals. Els camps que escriu la persona (`estat`, `notes`) no
es toquen mai. Una fila que no es pot interpretar (una coma sense cometes desplaça les columnes)
no es desa i es diu; una fila curta es desa amb els camps del final buits i també es diu.

## Navegar les convocatòries

* **[[Tauler CIDO]]** — què hi ha, quantes n'hi ha per dia, les vistes i les darreres publicades.
* **[[Convocatòries CIDO]]** — el llistat sencer amb cerca per placa, matèries, ens, expedient…
* **Vistes agrupades** — per grup de titulació, matèries, sistema de selecció, tipus de personal,
  canal, ens, data de publicació, termini i titulació requerida. Surten d'una sola macro
  (`vista-agrupada`, a [[Vistes agrupades]]): cada grup porta el compte i la llista.
* **[[El meu seguiment]]** — les marcades com a interessants, sol·licitades o descartades.
  La marca és un camp `estat` que s'escriu amb els botons de la fitxa, i les notes, un camp
  `notes` amb un quadre de text. Per això la wiki s'ha de servir amb escriptura permesa.

## Comprovacions

```bash
python3 ~/.hermes/profiles/jeremy_ruston/tools/tidcheck.py .
WIKI="$PWD" bash proves/e2e.sh
```

`tidcheck.py` valida el wikitext (títol, duplicats, camps, enllaços i macros trencades, blocs
desbalancejats, vocabulari d'etiquetes).

`proves/e2e.sh` treballa sobre una còpia temporal i comprova el comportament, no l'aspecte:

1. la sincronització amb `proves/cido_24h_exemple.csv` crea les convocatòries esperades;
2. el contracte de dades de cada tiddler (camps, ordre de `cidocamps`, caption, dates, entitats
   HTML desfetes, cos);
3. el que no es pot llegir del CSV es diu i no es desa;
4. la segona passada no toca cap fitxer (idempotència);
5. el que ha escrit la persona sobreviu a la sincronització;
6. la ruta HTTP del botó: el resum en JSON, la redirecció i el cas del CSV que falta;
7. el build estàtic i el render: `$:/DefaultTiddlers`, cap «Missing tiddler», el tauler amb el
   compte i les vistes enllaçades, cada vista agrupada amb els grups i les files que toquen, i
   **cada fitxa amb el caption, els camps, els botons i les notes del seu propi procés**.

Trencar qualsevol d'aquestes coses ha de fer sortir la prova vermella: si una comprovació no sap
dir «no», no és cap prova.

## Format d'un tiddler

```
title: Títol del tiddler
tags: una altra

Cos en wikitext.
```

El nom del fitxer és el títol amb `/` substituït per `_` i els accents caiguts
(`$:/DefaultTiddlers` → `$__DefaultTiddlers.tid`, `Convocatòries CIDO` →
`Convocatories CIDO.tid`).
