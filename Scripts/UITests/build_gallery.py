#!/usr/bin/env python3
"""Build a local screenshot comparison gallery from exported audit evidence."""
import argparse
from html import escape
from pathlib import Path
from urllib.parse import quote

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('audit_directory', type=Path)
args = parser.parse_args()
root = args.audit_directory
cards = []
for device in ('iphone', 'ipad'):
    cards.append(f'<h2>{"iPhone" if device == "iphone" else "iPad"}</h2>')
    before = root / 'before' / device
    after = root / 'after' / device
    for path in sorted(after.glob('*.png')):
        name = path.stem
        title = escape(name.replace('-', ' '))
        previous = before / path.name
        def figure(image, caption):
            href = quote(image.relative_to(root).as_posix())
            return f'<figure><figcaption>{escape(caption)}</figcaption><a href="{href}"><img loading="lazy" src="{href}" alt="{title} — {escape(caption)}"></a></figure>'
        if previous.exists():
            cards.append(f'<section><h3>{title}</h3><div class="pair">{figure(previous,"Before")}{figure(path,"After")}</div></section>')
        else:
            cards.append(f'<section class="additional"><h3>{title}</h3>{figure(path,"Additional automated coverage")}</section>')
page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>WatermelonFin — sign-in audit</title><style>
:root{color-scheme:dark light;font:16px/1.5 system-ui}body{max-width:1200px;margin:auto;padding:24px}h1{font-size:2rem}h2{margin-top:48px;border-bottom:2px solid #ed3258}h3{font-size:1.1rem}section{margin:32px 0;padding:16px;border:1px solid #8886;border-radius:12px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:24px}figure{margin:0;text-align:center}figcaption{padding:8px;font-weight:600}img{max-width:100%;max-height:750px;object-fit:contain;border-radius:8px}.additional img{max-height:600px}a{color:inherit}p{max-width:75ch}@media(max-width:650px){.pair{grid-template-columns:1fr}body{padding:12px}}@media print{section{break-inside:avoid}img{max-height:480px}}
</style><h1>WatermelonFin sign-in audit</h1>
<p>Matched baseline and updated screens, followed by additional automated coverage. Select any image to inspect its original resolution. All accounts and server names shown are test fixtures.</p>
<p><a href="README.md">Findings, test results, and limitations</a> · <a href="review.md">Independent review</a></p>
'''+ '\n'.join(cards) + '</html>\n'
(root / 'index.html').write_text(page)
print(root / 'index.html')
