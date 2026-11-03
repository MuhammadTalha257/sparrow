# Zuffi characters (Wobnimo)

`wob.js` is a bundle of the Wobnimo engine (MIT, © 2026 Pourya Akhbari — see `../LICENSE-wobnimo.txt`)
with the Boo and Bao characters and Zuffi's own bunny (`zuffibunny.ts`, shaped after Wobnimo's "Hop").

Rebuild: copy Wobnimo's `packages/` next to these files, then
`npx esbuild entry.ts --bundle --format=iife --minify --target=safari16 --alias:@wobnimo/engine=./packages/engine/src/index.ts --outfile=../wob.js`
