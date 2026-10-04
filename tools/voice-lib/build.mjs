// node build.mjs [outDir] → outDir/voice.js + the ONNX Runtime wasm files it needs
import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
const out = process.argv[2] || 'dist';
fs.mkdirSync(out, { recursive: true });
const empty = { name: 'empty', setup(b) { b.onResolve({ filter: /^(fs|fs\/promises|path|url|node:.*)$/ }, a => ({ path: a.path, namespace: 'empty' })); b.onLoad({ filter: /.*/, namespace: 'empty' }, () => ({ contents: 'export default {};' })); } };
await build({ entryPoints: ['entry.js'], bundle: true, format: 'esm', platform: 'browser', target: 'safari15', minify: true,
  outfile: path.join(out, 'voice.js'), plugins: [empty], logLevel: 'warning' });
// Voices come from the app itself, not the internet.
let js = fs.readFileSync(path.join(out, 'voice.js'), 'utf8');
const hf = 'https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/main/voices/';
if (!js.includes(hf)) throw new Error('kokoro voice URL not found — update the patch');
js = js.split('`' + hf + '${').join('`${globalThis.SPARROW_KOKORO_VOICES||"' + hf + '"}${');
fs.writeFileSync(path.join(out, 'voice.js'), js);
const ort = path.dirname(fs.realpathSync('node_modules/onnxruntime-web/package.json')) + '/dist';
for (const f of ['ort-wasm-simd-threaded.jsep.mjs', 'ort-wasm-simd-threaded.jsep.wasm', 'ort-wasm-simd-threaded.mjs', 'ort-wasm-simd-threaded.wasm'])
  if (fs.existsSync(path.join(ort, f))) fs.copyFileSync(path.join(ort, f), path.join(out, f));
console.log(fs.readdirSync(out).map(f => `${f} ${(fs.statSync(path.join(out, f)).size / 1e6).toFixed(1)} MB`).join('\n'));
