// Loads the bundled web app in a real browser, speaks a few lines with every built-in voice,
// saves them as WAV files (so people can listen) and reports how fast each one was.
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(process.argv[2] || '../../mac/Resources/web');
const out = path.resolve(process.argv[3] || 'samples');
fs.mkdirSync(out, { recursive: true });
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.onnx': 'application/octet-stream', '.bin': 'application/octet-stream' };
const server = http.createServer((req, res) => {
  const f = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!f.startsWith(root) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' });
  if (req.method === 'HEAD') return res.end();
  fs.createReadStream(f).pipe(res);
}).listen(8765);
fs.writeFileSync(path.join(root, 'voicetest.html'), '<!doctype html><meta charset="utf-8"><script type="module">import * as nv from "./neuralvoice.js"; window.nv = nv; window.ready = true;</script>');

const lines = [
  ['english-heart', 'en', 'Hi Talha! You have a meeting with Ali in five minutes. Shall I open Zoom for you?', 'af_heart'],
  ['english-emma', 'en', 'Good morning. It is sunny and nineteen degrees in London. You have three tasks today.', 'bf_emma'],
  ['english-george', 'en', 'Done. I saved the number in your contacts and opened Spotify.', 'bm_george'],
  ['urdu', 'ur', 'السلام علیکم طلحہ! پانچ منٹ میں آپ کی علی کے ساتھ میٹنگ ہے۔'],
  ['roman-urdu', 'ur', 'Talha, aap ki meeting paanch minute mein hai. Main Spotify khol rahi hoon.'],
  ['hindi', 'hi', 'नमस्ते तलहा! पाँच मिनट में आपकी अली के साथ मीटिंग है।'],
  ['punjabi', 'pa', 'ਸਤ ਸ੍ਰੀ ਅਕਾਲ! ਪੰਜ ਮਿੰਟ ਵਿੱਚ ਤੁਹਾਡੀ ਮੀਟਿੰਗ ਹੈ।'],
];
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', m => { console.log('  page:', m.text()); if (m.type() === 'error') console.log('::warning::page: ' + m.text().slice(0, 300)); });
page.on('pageerror', e => console.log('::error::page error: ' + e.message.slice(0, 300)));
await page.goto('http://localhost:8765/voicetest.html');
await page.waitForFunction('window.ready === true', null, { timeout: 30000 });
let failed = 0;
const report = [];
for (const [name, lang, text, voice] of lines) {
  const t0 = Date.now();
  try {
    const r = await page.evaluate(async ([text, lang, voice]) => {
      const r = await window.nv.renderWav(text, { lang, voice });
      let s = ''; for (const b of r.wav) s += String.fromCharCode(b);
      return { b64: btoa(s), model: r.model, seconds: r.seconds };
    }, [text, lang, voice]);
    const ms = Date.now() - t0;
    fs.writeFileSync(path.join(out, `sparrow-voice-${name}.wav`), Buffer.from(r.b64, 'base64'));
    const line = `${name}: ${r.model}, ${r.seconds.toFixed(1)}s of audio in ${(ms / 1000).toFixed(1)}s`;
    console.log('::notice::✓ ' + line); report.push('✓ ' + line);
    if (r.seconds < 1) { failed++; console.log('::error::' + name + ' too short'); }
  } catch (e) { failed++; console.log('::error::✗ ' + name + ': ' + String(e.message).slice(0, 400)); report.push(`✗ ${name}: ${e.message}`); }
}
fs.writeFileSync(path.join(out, 'report.txt'), report.join('\n') + '\n');
fs.unlinkSync(path.join(root, 'voicetest.html'));
await browser.close(); server.close();
process.exit(failed ? 1 : 0);
