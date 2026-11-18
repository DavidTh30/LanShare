"""Embeds webui.html into webui.inc as a Pascal string constant.

Run after editing webui.html (or after tools/makeicon wrote favicon.b64):
    python tools/html2inc.py
"""
import os

here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, '..', 'webui.html')
dst = os.path.join(here, '..', 'webui.inc')
fav = os.path.join(here, '..', 'favicon.b64')

html = open(src, encoding='utf-8').read()
# favicon: base64 PNG written by tools/makeicon (falls back to a 1x1 transparent PNG)
if os.path.exists(fav):
    b64 = open(fav).read().strip()
else:
    b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
html = html.replace('{{FAVICON}}', b64)

out = ['{ Generated from webui.html by tools/html2inc.py - do not edit by hand }',
       'const', '  WebUIHtml: string =']
parts = []
for line in html.split('\n'):
    # split long lines so every Pascal literal stays short
    while True:
        chunk, line = line[:180], line[180:]
        lit = "'" + chunk.replace("'", "''") + "'"
        if line:
            parts.append('    ' + lit)
        else:
            parts.append('    ' + lit + ' + #10')
            break
out.append(' +\n'.join(parts) + ';')
open(dst, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
print('wrote', dst, len(parts), 'literals')
