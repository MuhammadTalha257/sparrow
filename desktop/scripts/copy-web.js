// Copies the shared Sparrow web app (repo root) into windows/www so the
// Windows app and the phone app are always the same code.
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..', '..');
const out = path.resolve(__dirname, '..', 'www');
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });

const copy = (from, to) => {
  const st = fs.statSync(from);
  if (st.isDirectory()) {
    fs.mkdirSync(to, { recursive: true });
    for (const f of fs.readdirSync(from)) copy(path.join(from, f), path.join(to, f));
  } else fs.copyFileSync(from, to);
};

for (const f of fs.readdirSync(root)) {
  if (/\.(html|js|css|webmanifest)$/.test(f) && f !== 'sw.js' && f !== 'get.html') copy(path.join(root, f), path.join(out, f));
}
for (const d of ['lib', 'icons']) copy(path.join(root, d), path.join(out, d));
copy(path.join(__dirname, '..', 'desktop.js'), path.join(out, 'desktop.js'));
// Offline speech recogniser (runs in the app, no internet)
const vosk = path.resolve(__dirname, '..', 'node_modules', 'vosk-browser', 'dist', 'vosk.js');
if (fs.existsSync(vosk)) copy(vosk, path.join(out, 'lib', 'vosk.js'));
fs.mkdirSync(path.resolve(__dirname, '..', 'build'), { recursive: true });
copy(path.join(root, 'icons', 'icon-512.png'), path.resolve(__dirname, '..', 'build', 'icon.png'));
console.log('web app copied to', out);
