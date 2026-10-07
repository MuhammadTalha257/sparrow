// Jarvis mode for the web app (iPhone, Android, Windows, any modern browser).
// Tap the mic once and just talk: Zuffi hears and answers in one step (Gemini Live, native audio),
// in the language you speak, you can interrupt it, and it does things while you talk.
// Needs internet and a Gemini key (Settings → AI). The Mac app has its own native version.
import { store } from './store.js';

const URL_WS = 'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';
const MODELS = ['gemini-3.8-live', 'gemini-3.1-flash-live-preview', 'gemini-2.5-flash-native-audio-preview-12-2025'];

export const liveUsable = () => !window.SparrowHost && store.settings.liveMode !== false && !!store.settings.keys?.gemini
  && navigator.onLine !== false && !!navigator.mediaDevices?.getUserMedia && 'WebSocket' in window;

let S = null;   // the running session

/**
 * opts: { tools: [declarations], run: async (name, args) => result, prompt: async () => string,
 *         firstText, onState(state, info), onLevel(0..1), onLine(who, text), onEnd(reason) }
 */
export async function startLive(opts) {
  if (S) { if (opts.firstText) S.sendText(opts.firstText); return; }
  const s = S = { opts, ws: null, ready: false, attempt: 0, ended: false, mic: null, inCtx: null, outCtx: null, node: null,
    nextAt: 0, sources: new Set(), user: '', agent: '', lastActivity: Date.now(), endAfterTurn: false, pending: 0, timer: null, started: Date.now() };
  const attempts = MODELS.flatMap(m => [[m, true], [m, false]]);
  const pref = localStorage.getItem('sparrow.liveModel'); if (pref) attempts.sort((a, b) => (b[0] === pref) - (a[0] === pref));

  s.send = o => { if (s.ws?.readyState === 1) s.ws.send(JSON.stringify(o)); };
  s.sendText = t => { s.lastActivity = Date.now(); s.ready ? s.send({ realtimeInput: { text: t } }) : (s.firstText = [s.firstText, t].filter(Boolean).join('. ')); };
  s.sendImage = b64 => { s.lastActivity = Date.now(); s.send({ realtimeInput: { video: { data: b64, mimeType: 'image/jpeg' } } }); };
  s.firstText = opts.firstText || '';
  opts.onState?.('connecting');
  // iPhone only lets audio start inside the tap itself: make both audio contexts right now, before any waiting.
  const AC = window.AudioContext || window.webkitAudioContext;
  s.outCtx = new AC(); s.inCtx = new AC();
  s.outCtx.resume?.().catch(() => {}); s.inCtx.resume?.().catch(() => {});

  // The microphone is asked for inside the tap (iPhone needs that), before the network.
  try {
    s.mic = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 } });
  } catch { end('no-mic'); opts.onState?.('error', 'Allow the microphone for Zuffi, then try again.'); return; }
  const prompt = await opts.prompt();

  const connect = () => {
    if (s.ended) return;
    if (s.attempt >= attempts.length) { opts.onState?.('error', 'Live voice isn’t available for this key right now.'); end('no-model'); return; }
    const [model, search] = attempts[s.attempt];
    const ws = s.ws = new WebSocket(`${URL_WS}?key=${encodeURIComponent(store.settings.keys.gemini)}`);
    ws.onopen = () => {
      const gen = { responseModalities: ['AUDIO'], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: store.settings.liveVoice || 'Kore' } } } };
      if (model.includes('3.1-flash-live')) gen.thinkingConfig = { thinkingLevel: 'minimal' };
      const tools = [{ functionDeclarations: opts.tools }]; if (search) tools.push({ googleSearch: {} });
      s.send({ setup: { model: 'models/' + model, generationConfig: gen, systemInstruction: { parts: [{ text: prompt }] }, tools,
        inputAudioTranscription: {}, outputAudioTranscription: {}, contextWindowCompression: { slidingWindow: {} },
        realtimeInputConfig: { automaticActivityDetection: { disabled: false, prefixPaddingMs: 120, silenceDurationMs: 650 } } } });
    };
    ws.onmessage = async e => {
      const text = typeof e.data === 'string' ? e.data : await e.data.text();
      let m; try { m = JSON.parse(text); } catch { return; }
      if (m.setupComplete) { s.ready = true; localStorage.setItem('sparrow.liveModel', model); await startMic(); opts.onState?.('listening');
        if (s.firstText) { s.send({ realtimeInput: { text: s.firstText } }); s.firstText = ''; }
        else s.send({ realtimeInput: { text: '(The user just tapped to talk. Say a very short warm "yes?" in their language and listen.)' } });
        return; }
      if (m.serverContent) content(m.serverContent);
      if (m.toolCall?.functionCalls) tools(m.toolCall.functionCalls);
      if (m.goAway) s.endAfterTurn = true;
    };
    ws.onclose = e => {
      if (s.ended || ws !== s.ws) return;
      if (!s.ready) { s.attempt++; connect(); return; }     // that model isn't available for this key → next one
      end(e.code === 1000 ? 'closed' : 'error ' + e.code);
    };
  };

  const content = c => {
    if (c.interrupted) { stopPlayback(); s.agent = ''; opts.onState?.('listening'); }
    if (c.inputTranscription?.text) { s.user += c.inputTranscription.text; s.lastActivity = Date.now(); opts.onLine?.('me', s.user); goodbye(); }
    if (c.outputTranscription?.text) { s.agent += c.outputTranscription.text; opts.onLine?.('bot', s.agent); }
    for (const p of c.modelTurn?.parts || []) if (p.inlineData?.data) play(p.inlineData.data);
    if (c.turnComplete) {
      opts.onTurn?.(s.user.trim(), s.agent.trim());
      s.user = ''; s.agent = ''; s.lastActivity = Date.now();
    }
  };
  const goodbye = () => {
    const t = s.user.toLowerCase().replace(/[.!?,\s]+$/, '').trim();
    if (t.split(/\s+/).length <= 6 && /(^|\b)(bye|bye bye|goodbye|good night|thank you|thanks|thank u|that'?s all|stop listening|khuda hafiz|allah hafiz|shukriya|shukria|bas|bas karo|ok bye|gracias|merci|obrigad[oa]|adiós|adios|au revoir|tchau)$/.test(t)) s.endAfterTurn = true;
  };
  const tools = calls => {
    s.lastActivity = Date.now();
    for (const fc of calls) {
      s.pending++; opts.onState?.('working', fc.name);
      Promise.resolve(opts.run(fc.name, fc.args || {}, s)).catch(e => ({ ok: false, result: String(e?.message || e) })).then(result => {
        s.pending--; s.lastActivity = Date.now();
        s.send({ toolResponse: { functionResponses: [{ id: fc.id, name: fc.name, response: result }] } });
        if (fc.name === 'end_conversation') s.endAfterTurn = true;
      });
    }
  };

  // ---- audio out: 24 kHz PCM chunks, queued gap-free
  const play = b64 => {
    const ctx = s.outCtx; if (!ctx) return;
    const bin = atob(b64), n = bin.length >> 1, buf = ctx.createBuffer(1, n, 24000), ch = buf.getChannelData(0);
    let peak = 0;
    for (let i = 0; i < n; i++) { let v = bin.charCodeAt(2 * i) | (bin.charCodeAt(2 * i + 1) << 8); if (v >= 32768) v -= 65536; ch[i] = v / 32768; peak = Math.max(peak, Math.abs(ch[i])); }
    const src = ctx.createBufferSource(); src.buffer = buf; src.connect(ctx.destination);
    const at = Math.max(ctx.currentTime + 0.03, s.nextAt); src.start(at); s.nextAt = at + buf.duration;
    s.sources.add(src); src.onended = () => s.sources.delete(src);
    s.lastActivity = Date.now(); opts.onLevel?.(peak * 0.5); opts.onState?.('speaking');
  };
  const stopPlayback = () => { for (const x of s.sources) { try { x.stop(); } catch {} } s.sources.clear(); s.nextAt = s.outCtx?.currentTime || 0; };
  const playing = () => s.outCtx && s.nextAt > s.outCtx.currentTime + 0.05;

  // ---- audio in: mic → 16 kHz 16-bit PCM → Gemini
  const startMic = async () => {
    const ctx = s.inCtx;
    const soon = (pr, ms) => Promise.race([pr, new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), ms))]);
    try { await soon(ctx.resume?.() || Promise.resolve(), 1500); } catch {}
    const srcNode = ctx.createMediaStreamSource(s.mic);
    const rate = ctx.sampleRate;
    const handle = f32 => {
      if (!s.ready || s.ended) return;
      const ratio = rate / 16000, len = Math.floor(f32.length / ratio), out = new Int16Array(len);
      let sum = 0;
      for (let i = 0; i < len; i++) {
        const a = Math.floor(i * ratio), b = Math.min(f32.length, Math.floor((i + 1) * ratio)); let acc = 0;
        for (let j = a; j < b; j++) acc += f32[j];
        const v = Math.max(-1, Math.min(1, acc / Math.max(1, b - a))); out[i] = v < 0 ? v * 0x8000 : v * 0x7fff; sum += v * v;
      }
      if (!playing()) opts.onLevel?.(Math.min(1, Math.sqrt(sum / Math.max(1, len)) * 6));
      const bytes = new Uint8Array(out.buffer); let bin = '';
      for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
      s.send({ realtimeInput: { audio: { data: btoa(bin), mimeType: 'audio/pcm;rate=16000' } } });
    };
    try {
      const code = `class P extends AudioWorkletProcessor{constructor(){super();this.b=[];this.n=0}process(i){const c=i[0]&&i[0][0];if(c){this.b.push(new Float32Array(c));this.n+=c.length;if(this.n>=${Math.round(rate / 10)}){const o=new Float32Array(this.n);let k=0;for(const x of this.b){o.set(x,k);k+=x.length}this.port.postMessage(o,[o.buffer]);this.b=[];this.n=0}}return true}}registerProcessor('sparrow-mic',P)`;
      if (!ctx.audioWorklet) throw new Error('no worklet');
      await soon(ctx.audioWorklet.addModule(URL.createObjectURL(new Blob([code], { type: 'application/javascript' }))), 2500);
      const node = s.node = new AudioWorkletNode(ctx, 'sparrow-mic');
      node.port.onmessage = e => handle(e.data);
      srcNode.connect(node);
    } catch {
      const node = s.node = ctx.createScriptProcessor(4096, 1, 1);
      node.onaudioprocess = e => handle(e.inputBuffer.getChannelData(0));
      srcNode.connect(node); node.connect(ctx.destination);
    }
  };

  // ---- end on "bye", silence, or after the goodbye has been spoken
  s.timer = setInterval(() => {
    if (s.ended) return;
    const quiet = Date.now() - s.lastActivity;
    if (s.endAfterTurn && !playing() && s.pending === 0 && quiet > 800) end('goodbye');
    else if (s.ready && !playing() && s.pending === 0 && quiet > (store.settings.liveIdle || 20) * 1000) end('quiet');
    else if (!s.ready && Date.now() - s.started > 14000) { opts.onState?.('error', 'Couldn’t connect to the live voice. Check the internet and your Gemini key.'); end('timeout'); }
  }, 500);

  function end(why) {
    if (s.ended) return;
    s.ended = true; S = null;
    clearInterval(s.timer);
    try { s.ws?.close(1000); } catch {}
    try { s.node?.disconnect(); } catch {}
    s.mic?.getTracks().forEach(t => t.stop());
    setTimeout(() => { s.inCtx?.close?.(); s.outCtx?.close?.(); }, 300);
    opts.onEnd?.(why);
  }
  s.end = end;
  connect();
}

export const stopLive = why => S?.end(why || 'stopped');
export const liveActive = () => !!S;
export const liveSendImage = b64 => S?.sendImage(b64);

/** One photo from the camera (front by default), as base64 JPEG. */
export async function cameraShot(facing = 'user') {
  const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: facing, width: { ideal: 1280 } } });
  const v = document.createElement('video'); v.playsInline = true; v.muted = true; v.srcObject = stream;
  await v.play(); await new Promise(r => setTimeout(r, 700));          // let the exposure settle
  const k = Math.min(1, 1024 / Math.max(v.videoWidth, v.videoHeight));
  const c = document.createElement('canvas'); c.width = Math.round(v.videoWidth * k); c.height = Math.round(v.videoHeight * k);
  c.getContext('2d').drawImage(v, 0, 0, c.width, c.height);
  stream.getTracks().forEach(t => t.stop());
  return c.toDataURL('image/jpeg', 0.75).split(',')[1];
}
