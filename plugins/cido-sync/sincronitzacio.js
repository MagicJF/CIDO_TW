/*\
title: $:/plugins/cido-sync/sincronitzacio.js
type: application/javascript
module-type: library

Lògica de la sincronització del feed CIDO: cido_24h.csv → tiddlers.

Un sol lloc per a les dues portes d'entrada: la ruta HTTP (el botó de la wiki) i
l'ordre de consola. Cap de les dues no escriu res pel seu compte: tot passa per
`exports.sincronitza`.

Res no porta marques de temps: dues execucions amb el mateix CSV han de deixar els
fitxers exactament iguals (git status net). L'estat de la darrera execució viu en un
tiddler a part, que no es publica.
\*/
"use strict";

var NOM_CSV = "cido_24h.csv";
var ETIQUETES = ["CIDO", "convocatòria"];
var COS = "<<fitxa-cido>>";
var MAX_CAPTION = 90;
var TITOL_ESTAT = "Estat de la sincronització";
// Camps que no venen del CSV sinó que els calcula aquest mòdul.
var DERIVATS = ["caption", "ens", "data_pub", "termini", "cidocamps", "font"];
// Camps que governa la sincronització a més de les columnes.
var DE_SISTEMA = ["title", "tags", "text"];
var MESOS = {jan: "01", feb: "02", mar: "03", apr: "04", may: "05", jun: "06",
             jul: "07", aug: "08", sep: "09", oct: "10", nov: "11", dec: "12"};

function colapsa(v) {
	// Un valor de camp és una sola línia: sense salts ni espais repetits, i amb les
	// entitats HTML del col·lector desfetes.
	return v === undefined ? "" : desescapaHtml(v.replace(/\s+/g, " ").trim());
}

/* Parser CSV segons RFC 4180: cometes dobles, camps entre cometes amb comes i salts. */
exports.parsejaCsv = function(text) {
	var files = [], fila = [], camp = "", dinsCometes = false, i = 0, c;
	while(i < text.length) {
		c = text.charAt(i);
		if(dinsCometes) {
			if(c === '"') {
				if(text.charAt(i + 1) === '"') { camp += '"'; i += 2; continue; }
				dinsCometes = false; i++; continue;
			}
			camp += c; i++; continue;
		}
		if(c === '"') { dinsCometes = true; i++; continue; }
		if(c === ",") { fila.push(camp); camp = ""; i++; continue; }
		if(c === "\r") { i++; continue; }
		if(c === "\n") { fila.push(camp); files.push(fila); fila = []; camp = ""; i++; continue; }
		camp += c; i++;
	}
	if(camp !== "" || fila.length > 0) { fila.push(camp); files.push(fila); }
	return files;
};

/* "Tue, 03 Nov 2026" → "2026-11-03" (i "" si no encaixa). */
function dataIso(text) {
	var m = /^[A-Za-z]{3},?\s+(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})$/.exec(colapsa(text));
	if(!m || !MESOS[m[2].toLowerCase()]) { return ""; }
	return m[3] + "-" + MESOS[m[2].toLowerCase()] + "-" + ("0" + m[1]).slice(-2);
}

/* "01/12/2026" → "2026-12-01" (i "" si no encaixa: també n'hi ha de "11/2026"). */
function dataTermini(text) {
	var m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(colapsa(text));
	if(!m) { return ""; }
	return m[3] + "-" + ("0" + m[2]).slice(-2) + "-" + ("0" + m[1]).slice(-2);
}

/* L'ens convocant de debò surt al resum del RSS ("Ens: ..."); `organisme` no sempre l'encerta. */
function extrauEns(resum) {
	var m = /Ens:\s*(.+?)\s*$/.exec(colapsa(resum));
	return m ? m[1] : "";
}

function retalla(text, maxim) {
	if(text.length <= maxim) { return text; }
	var tall = text.slice(0, maxim - 1), espai = tall.lastIndexOf(" ");
	return (espai > 40 ? tall.slice(0, espai) : tall).replace(/[,;:·]$/, "") + "…";
}

/*
El col·lector llegeix HTML, així que al CSV hi arriben entitats (`&amp;`, `&#039;`). Sense
desescapar-les, els enllaços no són enllaços i els accents queden escrits en cru.
*/
function desescapaHtml(text) {
	var entitats = {amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " "};
	return text.replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, function(tot, cos) {
		if(cos.charAt(0) === "#") {
			var n = cos.charAt(1).toLowerCase() === "x" ? parseInt(cos.slice(2), 16) : parseInt(cos.slice(1), 10);
			return isNaN(n) ? tot : String.fromCodePoint(n);
		}
		return entitats[cos.toLowerCase()] !== undefined ? entitats[cos.toLowerCase()] : tot;
	});
}

/*
Les files del CSV, amb la capçalera, els registres i el que no s'ha pogut llegir.

Una fila amb més cel·les que la capçalera no es pot interpretar (una coma sense cometes
desplaça les columnes) i no es desa: és millor dir-ho que desar la convocatòria amb els
camps canviats de lloc. Una fila amb menys cel·les sí que es desa, però amb els camps del
final buits i un avís, perquè pot voler dir que la font ha canviat.
*/
exports.llegeixCsv = function(text) {
	var files = exports.parsejaCsv(text), registres = [], avisos = [], errors = [], capsalera = [];
	if(files.length > 0) { capsalera = files[0].map(colapsa); }
	for(var f = 1; f < files.length; f++) {
		var fila = files[f];
		if(fila.length === 1 && colapsa(fila[0]) === "") { continue; }
		if(fila.length > capsalera.length) {
			errors.push("El registre " + f + " té " + fila.length + " cel·les i la capçalera en té " +
				capsalera.length + ": segur que hi ha una coma sense cometes. No s'ha desat.");
			continue;
		}
		if(fila.length < capsalera.length) {
			avisos.push("El registre " + f + " té " + fila.length + " cel·les i la capçalera en té " +
				capsalera.length + ": els camps del final queden buits.");
		}
		var registre = {};
		for(var c = 0; c < capsalera.length; c++) {
			registre[capsalera[c]] = fila[c] === undefined ? "" : fila[c];
		}
		registres.push(registre);
	}
	return {capsalera: capsalera, registres: registres, avisos: avisos, errors: errors};
};

/* El tiddler d'un registre. `existent` és el tiddler que ja hi ha amb aquell títol, si n'hi ha. */
exports.construeixTiddler = function(registre, capsalera, existent) {
	var camps = {}, presents = [];
	capsalera.forEach(function(col) {
		var v = colapsa(registre[col]);
		if(v === "") { return; }
		camps[col] = v;
		presents.push(col);
	});
	if(!camps.identificador) { return null; }
	var ens = extrauEns(camps.resum_rss) || camps.organisme || "";
	var tiddler = {};
	// Els camps que no governa la sincronització es conserven (el seguiment de la
	// persona: `estat`, `notes`, i el que hi hagi posat TiddlyWiki).
	var gestionats = {};
	capsalera.forEach(function(c) { gestionats[c] = true; });
	DERIVATS.concat(DE_SISTEMA).forEach(function(c) { gestionats[c] = true; });
	if(existent) {
		existent.fields["cidocamps"] && existent.fields["cidocamps"].split("|").forEach(function(c) { gestionats[c] = true; });
		for(var k in existent.fields) {
			if(!gestionats[k]) { tiddler[k] = existent.fields[k]; }
		}
	}
	capsalera.forEach(function(c) { if(camps[c] !== undefined) { tiddler[c] = camps[c]; } });
	tiddler.title = camps.identificador;
	tiddler.tags = ETIQUETES.join(" ");
	tiddler.caption = retalla(camps.placa ? camps.placa + (ens ? " · " + ens : "") : ens, MAX_CAPTION);
	tiddler.font = NOM_CSV;
	tiddler.cidocamps = presents.join("|");
	if(ens) { tiddler.ens = ens; }
	var pub = dataIso(camps.data_publicacio);
	if(pub) { tiddler.data_pub = pub; }
	var termini = dataTermini(camps.finalitzacio_de_presentacio_de_sollicituds);
	if(termini) { tiddler.termini = termini; }
	tiddler.text = COS;
	return tiddler;
};

function mateixosCamps(existent, nou, gestionats) {
	for(var k in gestionats) {
		var abans = existent ? existent.getFieldString(k) : "";
		var ara = nou[k] === undefined ? "" : String(nou[k]);
		if(abans !== ara) { return false; }
	}
	return true;
}

function campsGestionats(capsalera, tiddler) {
	var g = {};
	capsalera.forEach(function(c) { g[c] = true; });
	DERIVATS.concat(DE_SISTEMA).forEach(function(c) { g[c] = true; });
	(tiddler.cidocamps || "").split("|").forEach(function(c) { if(c) { g[c] = true; } });
	return g;
}

function campsPerTreure(existent, nou, gestionats) {
	var sobrers = [];
	for(var k in gestionats) {
		if(existent.hasField(k) && nou[k] === undefined) { sobrers.push(k); }
	}
	return sobrers;
}

/*
Sincronitza el CSV amb la wiki. No esborra mai res: actualitza el que canvia i crea el
que falta. Torna un resum amb els comptes i els avisos.
*/
exports.sincronitza = function(wiki, opcions) {
	opcions = opcions || {};
	var fs = require("fs"), path = require("path");
	var base = opcions.wikiPath || $tw.boot.wikiPath;
	var fitxer = opcions.fitxer || path.resolve(base, NOM_CSV);
	var resum = {fitxer: fitxer, files: 0, entrades: 0, creades: 0, actualitzades: 0,
		sense_canvis: 0, avisos: [], errors: [], creades_titols: [], actualitzades_titols: []};
	if(!fs.existsSync(fitxer)) {
		resum.errors.push("No hi ha cap fitxer «" + path.basename(fitxer) + "» a " + base + ".");
		return resum;
	}
	var dades = exports.llegeixCsv(fs.readFileSync(fitxer, "utf8"));
	resum.files = dades.registres.length;
	resum.avisos = dades.avisos.slice(0);
	resum.errors = dades.errors.slice(0);
	var vistos = {};
	dades.registres.forEach(function(registre, index) {
		var titol = colapsa(registre.identificador);
		if(!titol) {
			resum.errors.push("El registre " + (index + 1) + " no porta «identificador».");
			return;
		}
		if(vistos[titol]) {
			resum.errors.push("L'identificador «" + titol + "» surt més d'una vegada; només se n'ha fet servir la primera.");
			return;
		}
		vistos[titol] = true;
		var existent = wiki.getTiddler(titol);
		var nou = exports.construeixTiddler(registre, dades.capsalera, existent);
		if(!nou) {
			resum.errors.push("El registre " + (index + 1) + " no té prou dades per fer-ne un tiddler.");
			return;
		}
		resum.entrades++;
		if(existent && mateixosCamps(existent, nou, campsGestionats(dades.capsalera, nou))) {
			resum.sense_canvis++;
			return;
		}
		// Un camp que mana la sincronització i ja no hi és s'ha de treure de debò:
		// `addTiddler` és un merge i, sense això, el valor vell s'hi quedaria per sempre.
		var sobrers = existent ? campsPerTreure(existent, nou, campsGestionats(dades.capsalera, nou)) : [];
		if(sobrers.length > 0) { wiki.deleteTiddler(titol); }
		wiki.addTiddler(nou);
		if(existent) { resum.actualitzades++; resum.actualitzades_titols.push(titol); }
		else { resum.creades++; resum.creades_titols.push(titol); }
	});
	return resum;
};

/* El text del tiddler d'estat: què ha passat a l'última execució. */
exports.textEstat = function(resum, ara) {
	var linies = [];
	linies.push("Última sincronització: " + ara);
	linies.push("");
	linies.push("* Fitxer: `" + (resum.fitxer || "").split("/").pop() + "`");
	linies.push("* Files del CSV: " + resum.files);
	linies.push("* Convocatòries: " + resum.entrades);
	linies.push("* Creades: " + resum.creades);
	linies.push("* Actualitzades: " + resum.actualitzades);
	linies.push("* Sense canvis: " + resum.sense_canvis);
	if(resum.avisos.length > 0) {
		linies.push("");
		linies.push("!! Avisos");
		resum.avisos.forEach(function(a) { linies.push("* " + a); });
	}
	if(resum.errors.length > 0) {
		linies.push("");
		linies.push("!! Errors");
		resum.errors.forEach(function(e) { linies.push("* " + e); });
	}
	return linies.join("\n");
};

/* Deixa constància de l'execució. Torna el tiddler que ha escrit. */
exports.anotaEstat = function(wiki, resum) {
	var d = new Date();
	var ara = d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2) +
		" " + ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2);
	var tiddler = {title: TITOL_ESTAT, data: ara, files: String(resum.files),
		entrades: String(resum.entrades), creades: String(resum.creades),
		actualitzades: String(resum.actualitzades), sense_canvis: String(resum.sense_canvis),
		errors: String(resum.errors.length), text: exports.textEstat(resum, ara)};
	wiki.addTiddler(tiddler);
	return tiddler;
};

exports.NOM_CSV = NOM_CSV;
exports.TITOL_ESTAT = TITOL_ESTAT;
