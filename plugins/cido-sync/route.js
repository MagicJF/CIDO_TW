/*\
title: $:/plugins/cido-sync/route.js
type: application/javascript
module-type: route

GET /cido/sincronitza

La porta que fa servir el botó de la wiki. És un GET perquè el botó pugui ser un
enllaç de debò (sense JavaScript): el servidor llegeix cido_24h.csv, actualitza o crea
els tiddlers i torna a la wiki amb una marca de temps perquè el navegador no ensenyi
la còpia vella. Amb `?format=json` respon el resum en JSON, que és com ho proven les
proves.
\*/
"use strict";

exports.methods = ["GET"];
exports.path = /^\/cido\/sincronitza$/;
exports.info = {priority: 100};

function escapa(t) {
	return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

exports.handler = function(request, response, state) {
	// La ruta fa la feina del servidor (crea i actualitza tiddlers), però és un GET i
	// TiddlyWiki autoritza els GET contra `readers`. Sense aquesta comprovació, qui només
	// pot llegir podria fer escriure la wiki.
	if(!state.server.isAuthorized("writers", state.authenticatedUsername)) {
		state.sendResponse(403, {"Content-Type": "text/plain; charset=utf-8"},
			"No tens permís d'escriptura en aquesta wiki.\n");
		return;
	}
	var lib = require("$:/plugins/cido-sync/sincronitzacio.js");
	var resum;
	try {
		resum = lib.sincronitza(state.wiki, {wikiPath: state.boot.wikiPath});
	} catch(e) {
		resum = {fitxer: lib.NOM_CSV, files: 0, entrades: 0, creades: 0, actualitzades: 0,
			sense_canvis: 0, avisos: [], errors: ["La sincronització ha petat: " + (e && e.message ? e.message : e)],
			creades_titols: [], actualitzades_titols: []};
	}
	var arrel = (state.pathPrefix || "") + "/";
	// L'estat es deixa sempre que s'hagi llegit el CSV, també quan la resposta és JSON:
	// si no, el tauler ensenyaria la sincronització anterior.
	if(resum.entrades > 0) { lib.anotaEstat(state.wiki, resum); }
	if(state.queryParameters && state.queryParameters.format === "json") {
		state.sendResponse(resum.entrades === 0 ? 500 : 200, {"Content-Type": "application/json; charset=utf-8"},
			JSON.stringify(resum, null, 2) + "\n");
		return;
	}
	if(resum.entrades === 0) {
		state.sendResponse(500, {"Content-Type": "text/html; charset=utf-8"}, paginaError(resum, arrel));
		return;
	}
	state.sendResponse(302, {"Location": arrel + "?v=" + Date.now(), "Content-Type": "text/plain; charset=utf-8"}, "");
};

function paginaError(resum, arrel) {
	var out = [];
	out.push("<!doctype html><html lang=\"ca\"><head><meta charset=\"utf-8\">");
	out.push("<title>No s'ha pogut sincronitzar</title>");
	out.push("<style>body{font-family:system-ui,sans-serif;max-width:44em;margin:3em auto;padding:0 1em;line-height:1.5}" +
		"code{background:#f2f2f2;padding:.1em .3em}h1{font-size:1.4em}li{margin:.2em 0}</style></head><body>");
	out.push("<h1>No s'ha pogut sincronitzar</h1>");
	out.push("<p>Fitxer: <code>" + escapa(resum.fitxer) + "</code></p>");
	out.push("<ul>");
	resum.errors.forEach(function(e) { out.push("<li>" + escapa(e) + "</li>"); });
	out.push("</ul>");
	out.push("<p><a href=\"" + escapa(arrel) + "\">Torna a la wiki</a></p>");
	out.push("</body></html>");
	return out.join("\n");
}
