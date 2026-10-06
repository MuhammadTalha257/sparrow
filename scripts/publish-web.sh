#!/usr/bin/env bash
# Copies Sparrow's web app (the iPhone / browser version) into the lisansystems website repo,
# where it is served at https://lisansystems.com/sparrow/
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$SRC/../lisansystems}/public/sparrow"
rm -rf "$DEST" && mkdir -p "$DEST"
cd "$SRC"
cp -r index.html *.js *.css manifest.webmanifest lib icons mascots "$DEST/"
rm -f "$DEST/main.js" "$DEST/preload.js" 2>/dev/null || true
cat > "$DEST/.htaccess" <<'HT'
# Sparrow web app (static files, not part of Laravel)
DirectoryIndex index.html
Options -MultiViews -Indexes
<IfModule mod_headers.c>
  # Always get the newest app (the service worker keeps it fast and offline)
  <FilesMatch "^(index\.html|sw\.js|manifest\.webmanifest)$">
    Header set Cache-Control "no-cache"
  </FilesMatch>
  <FilesMatch "\.(js|css)$">
    Header set Cache-Control "no-cache"
  </FilesMatch>
</IfModule>
<IfModule mod_mime.c>
  AddType application/manifest+json .webmanifest
  AddType text/javascript .js .mjs
</IfModule>
HT
echo "Copied to $DEST ($(du -sh "$DEST" | cut -f1))"
