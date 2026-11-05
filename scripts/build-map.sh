#!/bin/sh
# Rebuilds docs/controller-map.pdf (and a PNG preview) from docs/controller-map.html using Chrome.
set -e
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SRC="file://$PWD/docs/controller-map.html"
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer --print-to-pdf="$PWD/docs/controller-map.pdf" "$SRC" 2>/dev/null
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1123,794 --force-device-scale-factor=2 \
  --screenshot="$PWD/docs/controller-map.png" "$SRC" 2>/dev/null
echo "Готово: docs/controller-map.pdf, docs/controller-map.png"
