# Putting Sparrow on lisansystems.com

**Option 1 — a section on your product page (easiest).**
Open `sparrow-section.html`, copy everything, and paste it into your product page as a *Custom HTML* / *Embed* block.
The download buttons always point to the newest version, because GitHub rebuilds them on every update.

**Option 2 — host the iPhone app on your own domain (nicer link).**
Upload these files from the repo to a folder on your site, e.g. `lisansystems.com/sparrow/`:
`index.html, get.html, style.css, app.js, brain.js, store.js, ai.js, i18n.js, prayer.js, memory.js, tools.js, sync.js, sw.js, manifest.webmanifest, icons/, lib/`
Then people open `https://lisansystems.com/sparrow/` in Safari → Share → Add to Home Screen,
and `https://lisansystems.com/sparrow/get.html` is your download page. (It must be served over https.)
