/*\
title: $:/plugins/cido-sync/command.js
type: application/javascript
module-type: command

--cido-sincronitza

La mateixa sincronització, sense servidor: per a un cron, per a la consola i per a les
proves. Ús: tiddlywiki <wiki> --cido-sincronitza
\*/
"use strict";

exports.info = {name: "cido-sincronitza", synchronous: true};

var Command = function(params, commander) {
	this.params = params;
	this.commander = commander;
};

Command.prototype.execute = function() {
	var lib = require("$:/plugins/cido-sync/sincronitzacio.js");
	var resum = lib.sincronitza(this.commander.wiki, {wikiPath: $tw.boot.wikiPath});
	lib.anotaEstat(this.commander.wiki, resum);
	this.commander.streams.output.write("Convocatòries: " + resum.entrades + " · creades: " + resum.creades +
		" · actualitzades: " + resum.actualitzades + " · sense canvis: " + resum.sense_canvis +
		" · errors: " + resum.errors.length + "\n");
	resum.errors.forEach(function(e) { this.commander.streams.error.write("ERROR " + e + "\n"); }.bind(this));
	resum.avisos.forEach(function(a) { this.commander.streams.error.write("AVIS " + a + "\n"); }.bind(this));
	return resum.errors.length > 0 && resum.entrades === 0 ? "La sincronització no ha pogut llegir el CSV" : null;
};

exports.Command = Command;
