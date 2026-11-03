"""HTML -> PNG a mida fixa, amb WeasyPrint + PyMuPDF. Vegeu renderize.sh."""
import os
import sys

import pymupdf
import weasyprint

src, out = sys.argv[1], sys.argv[2]
amplada, alcada = (os.environ.get("TID_RENDER_MIDA", "1280x900").split("x") + ["900"])[:2]

html = open(src, encoding="utf-8").read()
# El viewport és part de la prova: el «abans» i el «després» han de coincidir-hi.
css = f"<style>@page{{size:{amplada}px {alcada}px;margin:0}} html,body{{margin:0}}</style>"
html = html.replace("</head>", css + "</head>", 1)

# base_url apunta al fitxer perquè el CSS i els enllaços relatius del build es resolguin.
pdf = weasyprint.HTML(string=html, base_url=src).write_pdf()
page = pymupdf.open("pdf", pdf)[0]
pix = page.get_pixmap(dpi=96)
pix.save(out)
print(f"PASS  {out} ({pix.width}x{pix.height})")
