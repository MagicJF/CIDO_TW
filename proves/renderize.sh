#!/usr/bin/env bash
# Rasteritza una pàgina HTML a PNG, mida fixa, sense navegador.
#
# Per què existeix: `captura.sh` depèn de Chromium. Quan Chromium no arrenca (mor abans
# d'escriure el fitxer, sense cap error útil), aquest és el camí que queda. Renderitza el
# build estàtic de TiddlyWiki, que ja porta el contingut a l'HTML: la pàgina és la de debò, el
# que canvia és el motor de rasteritzat. Digues-ho així a l'informe; no ho presentis com una
# captura de navegador.
#
# Ús: renderize.sh <entrada.html> <sortida.png> [amplada] [alçada]
set -euo pipefail

[ $# -ge 2 ] || { echo "ús: renderize.sh <entrada.html> <sortida.png> [amplada] [alçada]" >&2; exit 2; }
[ -f "$1" ] || { echo "no existeix: $1" >&2; exit 2; }

AMPLADA="${3:-1280}"
ALCADA="${4:-900}"

UV="${UV:-$(command -v uv || true)}"
[ -n "$UV" ] || UV="$(ls -d "${HOME}"/.hermes/tools/uv-*/uv 2>/dev/null | head -1)"
[ -n "$UV" ] || { echo "cal uv (o UV=<ruta>) per instal·lar WeasyPrint" >&2; exit 1; }

# El directori de cau i el de HOME poden ser de només lectura: apunta'ls a llocs escribibles.
export UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uvcache}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/fccache}"
export TID_RENDER_MIDA="${AMPLADA}x${ALCADA}"

# WeasyPrint necessita libpangoft2. Si al sistema no hi és, es pot extreure d'un .deb de
# Debian sense root i apuntar-hi aquí:
#   curl -sSo p.deb http://deb.debian.org/debian/pool/main/p/pango1.0/libpangoft2-1.0-0_<v>_amd64.deb
#   mkdir -p /tmp/deblibs && dpkg-deb -x p.deb /tmp/deblibs
[ -d /tmp/deblibs/usr/lib/x86_64-linux-gnu ] && \
  export LD_LIBRARY_PATH="/tmp/deblibs/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec "$UV" run --quiet --with weasyprint --with pymupdf python "$(dirname "$0")/renderize.py" "$1" "$2"
