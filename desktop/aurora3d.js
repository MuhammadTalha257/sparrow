// Aurora in 3D for Windows — the same bunny as the Mac app (SparrowSprite.swift → Aurora3DRig), rebuilt with three.js:
// the same furry shapes, sizes and colours, the same feelings (smile, happy, laugh, love, wink, thinking, surprised,
// cross, sad, sleepy, listening), the same poses (sit, hop, hold, happy, cross, listen, wave), lip-sync, springy ears,
// real-rabbit habits and floating mood effects. Keep the numbers in step with the Swift version.
import * as THREE from './lib/three.module.min.js';

const SHELLS = 20;               // fur layers (Mac: 26). A little lighter so it stays smooth on every Windows PC.
const rgb = (r, g, b) => new THREE.Color(r / 255, g / 255, b / 255);
const lerpC = (a, b, f) => a.clone().lerp(b, f);

const GEO = { sphere: new THREE.SphereGeometry(1, 36, 24), small: new THREE.SphereGeometry(1, 20, 14) };

function furMaterial(color, h, len, density) {
  const m = new THREE.MeshLambertMaterial({ color });
  m.onBeforeCompile = sh => {
    sh.uniforms.shellH = { value: h }; sh.uniforms.furLen = { value: len }; sh.uniforms.furDensity = { value: density };
    sh.vertexShader = 'uniform float shellH; uniform float furLen; varying vec2 vFurUv;\n' + sh.vertexShader
      .replace('#include <begin_vertex>', `#include <begin_vertex>
        vFurUv = uv;
        // hair grows out and droops a little under its own weight (soft, fluffy, not spiky)
        transformed += objectNormal * (furLen * shellH) + vec3(0.0, -1.0, 0.0) * (furLen * shellH * shellH * 0.45);`);
    sh.fragmentShader = 'uniform float shellH; uniform float furDensity; varying vec2 vFurUv;\n' + sh.fragmentShader
      .replace('#include <color_fragment>', `#include <color_fragment>
        vec2 uvc = vFurUv * furDensity * vec2(2.0, 1.0);
        vec2 cell = floor(uvc); vec2 inCell = fract(uvc) - 0.5;
        float r = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
        float strand = length(inCell) * 2.0;     // each hair tapers to a point
        if (shellH > 0.0 && (r < pow(shellH, 0.6) * 0.92 || strand > (1.0 - shellH) * 1.15 + 0.18)) discard;
        float ao = mix(0.80, 1.0, shellH);
        float sheen = pow(shellH, 3.0) * 0.55;
        diffuseColor.rgb = mix(diffuseColor.rgb * ao, vec3(1.0, 0.995, 0.99), sheen);`);
  };
  m.customProgramCacheKey = () => 'fur';
  return m;
}

export class Aurora3D {
  /** framing: 'full' (the pet), 'face' (head with ears), 'closeFace' (the notch tab) */
  constructor(canvas, { framing = 'full', color = '#F7F5F3' } = {}) {
    this.canvas = canvas; this.framing = framing;
    this.pose = 'sit'; this.faceLeft = false; this.mood = 'smile';
    this.targetYaw = 0; this.targetPitch = 0;
    this.talking = false; this.talkText = ''; this.talkStart = 0;
    this.pokeAt = -1e9; this.pokeEar = false;
    const r = this.renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true, powerPreference: 'low-power' });
    r.setClearColor(0x000000, 0); r.outputColorSpace = THREE.SRGBColorSpace;
    r.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
    this.scene = new THREE.Scene();
    this.cam = new THREE.PerspectiveCamera(28, 1, 0.1, 40);
    this._state();
    this._build(new THREE.Color(color));
    this.resize();
    this._last = 0; this._raf = 0;
    const loop = ts => { this._raf = requestAnimationFrame(loop); this._frame(ts / 1000); };
    this._raf = requestAnimationFrame(loop);
    this._ro = new ResizeObserver(() => this.resize()); this._ro.observe(canvas);
  }
  setPose(p) { this.pose = p || 'sit'; }
  setMood(m) { this.mood = m || 'smile'; }
  setFaceLeft(l) { this.faceLeft = !!l; }
  /** dx, dy: the mouse from her centre, in screen pixels (y down) */
  look(dx, dy) { const near = Math.hypot(dx, dy) < 30; this.targetYaw = near ? 0 : Math.max(-0.7, Math.min(0.7, dx / 380)); this.targetPitch = near ? 0 : Math.max(-0.3, Math.min(0.3, dy / 420)); }
  talk(on, text = '', startedAtMs = performance.now()) { this.talking = !!on; if (on) { this.talkText = text; this.talkStart = startedAtMs / 1000; } }
  poke(ear = false) { this.pokeEar = ear; this.pokeAt = performance.now() / 1000; }
  resize() {
    const w = this.canvas.clientWidth || this.canvas.width, h = this.canvas.clientHeight || this.canvas.height;
    if (!w || !h) return;
    this.renderer.setSize(w, h, false); this.cam.aspect = w / h; this.cam.updateProjectionMatrix();
  }
  dispose() { cancelAnimationFrame(this._raf); this._ro.disconnect(); this.renderer.dispose(); }

  _state() {
    Object.assign(this, { t: 0, phase: 0, stand: 0.62, hopAmt: 0, turn: 0, yaw: 0, pitch: 0, cheer: 0, crossAmt: 0, holdAmt: 0, listen: 0, waveAmt: 0,
      nextBlink: 2, talkOpen: 0, talkAmt: 0, idleKind: 0, idleStart: -100, nextIdle: 5, groom: 0, lookAround: 0, earFlop: 0, sniff: 0,
      happyE: 0, crossE: 0, sadE: 0, surpriseE: 0, sleepE: 0, winkE: 0, thinkE: 0, laughE: 0, loveE: 0, listenE: 0, listenAmt: 0,
      earSpring: [0, 0], earVel: [0, 0], earSpringX: [0, 0], earVelX: [0, 0], lastYaw: 0, lastPitch: 0, bounce: 0,
      surpriseKick: 0, lastExpr: 'smile', exprAt: 0, lookX: 0, lookY: 0, nextFx: 0 });
  }

  // ---------- building (same layout as the Mac) ----------
  _node(parent, p = [0, 0, 0]) { const n = new THREE.Group(); n.position.set(...p); parent.add(n); return n; }
  _fur(parent, rx, ry, rz, color, len = 0.07, density = 40, p = [0, 0, 0]) {
    const g = this._node(parent, p); g.scale.set(rx, ry, rz);
    const avg = (rx + ry + rz) / 3;
    for (let i = 0; i <= SHELLS; i++) g.add(new THREE.Mesh(GEO.sphere, furMaterial(color, i / SHELLS, len / avg, density * 2.4)));
    return g;
  }
  _flat(c, o = 1) { return new THREE.MeshBasicMaterial({ color: c, transparent: true, opacity: o, depthTest: false, depthWrite: false }); }
  _faceBit(parent, geo, mat, p, s = [1, 1, 1], order = 100) {
    mat.depthTest = false; mat.depthWrite = false; mat.transparent = true;
    const m = new THREE.Mesh(geo, mat); m.position.set(...p); m.scale.set(...s); m.renderOrder = order;
    m.userData.base = mat.opacity; parent.add(m); return m;
  }
  _setOpacity(node, o) {
    node.traverse(c => { if (c.material) { c.material.opacity = (c.userData.base ?? 1) * o; c.visible = o > 0.003; } });
  }
  _capsule(r, h) { return new THREE.CapsuleGeometry(r, Math.max(0.0001, h - 2 * r), 4, 10); }
  _arc(r, w, spread) {
    const s = new THREE.Shape(), a0 = Math.PI / 2 - spread, a1 = Math.PI / 2 + spread;
    s.absarc(0, 0, r + w, a0, a1, false); s.absarc(0, 0, r, a1, a0, true);
    return new THREE.ShapeGeometry(s, 24);
  }
  _glyphTex(g, color, bold) {
    const c = document.createElement('canvas'); c.width = c.height = 96; const x = c.getContext('2d');
    x.font = `${bold ? 900 : 400} 72px "Segoe UI Emoji","Segoe UI",sans-serif`; x.fillStyle = color; x.textAlign = 'center'; x.textBaseline = 'middle';
    x.fillText(g, 48, 52); const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
  }
  _confettiTex() {
    const c = document.createElement('canvas'); c.width = c.height = 64; const x = c.getContext('2d');
    ['#FF2D78', '#FFD60A', '#40C8E0', '#BF5AF2'].forEach((col, i) => { x.fillStyle = col; x.beginPath(); x.roundRect(8 + i * 12, 64 - (14 + (i % 2) * 22) - 18, 9, 18, 3); x.fill(); });
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
  }
  _heartTex() {
    const c = document.createElement('canvas'); c.width = c.height = 128; const x = c.getContext('2d');
    x.translate(0, 128); x.scale(1, -1);
    x.beginPath(); x.moveTo(64, 16); x.bezierCurveTo(10, 56, 8, 98, 38, 106); x.bezierCurveTo(54, 110, 62, 98, 64, 88);
    x.bezierCurveTo(66, 98, 74, 110, 90, 106); x.bezierCurveTo(120, 98, 118, 56, 64, 16); x.closePath();
    x.fillStyle = 'rgb(255,128,161)'; x.fill(); x.fillStyle = 'rgba(255,255,255,.55)'; x.beginPath(); x.ellipse(42, 86, 9, 6, 0, 0, 7); x.fill();
    const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
  }

  _build(base) {
    const S = this.scene;
    const P = Math.PI;
    S.add(new THREE.AmbientLight(rgb(255, 248, 240), 0.52 * P));
    const key = new THREE.DirectionalLight(0xffffff, 0.76 * P); key.position.set(3, 6, 4); key.target.position.set(0, 0.8, 0); S.add(key, key.target);
    const back = new THREE.DirectionalLight(rgb(207, 224, 255), 0.38 * P); back.position.set(-4, 3, -4); back.target.position.set(0, 0.8, 0); S.add(back, back.target);
    // soft ground shadow
    const sc = document.createElement('canvas'); sc.width = sc.height = 128; const sx = sc.getContext('2d');
    const gr = sx.createRadialGradient(64, 64, 0, 64, 64, 62); gr.addColorStop(0, 'rgba(0,0,0,.4)'); gr.addColorStop(1, 'rgba(0,0,0,0)'); sx.fillStyle = gr; sx.fillRect(0, 0, 128, 128);
    const st = new THREE.CanvasTexture(sc);
    const shadow = new THREE.Mesh(new THREE.PlaneGeometry(1.9, 1.3), new THREE.MeshBasicMaterial({ map: st, transparent: true, depthWrite: false }));
    shadow.rotation.x = -P / 2; shadow.position.y = 0.003; S.add(shadow); this.shadow = shadow;

    const cream = base, cream2 = lerpC(base, new THREE.Color(0, 0, 0), 0.08), bib = lerpC(base, new THREE.Color(1, 1, 1), 0.55);
    const pink = rgb(244, 179, 189), white = new THREE.Color(1, 1, 1);
    this.bodyParts = []; this.thighs = []; this.feet = []; this.arms = []; this.ears = []; this.eyes = []; this.brows = [];
    this.sockets = []; this.lids = []; this.lashes = []; this.cheeks = []; this.blushes = []; this.tears = []; this.eyeRims = []; this.whiskers = [];
    const root = this.root = this._node(S);
    const stance = this.stance = this._node(root, [0, 0.06, -0.42]);
    const hips = this.hips = this._node(stance, [0, 0.5, 0.42]);
    this.bodyParts.push(this._fur(hips, 0.56, 0.52, 0.58, cream, 0.15, 62, [0, 0.08, -0.02]));
    this.bodyParts.push(this._fur(hips, 0.16, 0.16, 0.14, white, 0.08, 20, [0, 0.24, -0.62]));
    for (const s of [-1, 1]) {
      const th = this._node(hips, [0.36 * s, -0.02, -0.08]); this.thighs.push(th); this.bodyParts.push(th);
      this._fur(th, 0.2, 0.3, 0.34, cream, 0.06, 40, [0, -0.08, 0.02]);
      const ft = this._node(th, [0, -0.42, -0.06]); this.feet.push(ft);
      this._fur(ft, 0.12, 0.07, 0.3, cream2, 0.04, 30, [0, 0, 0.17]);
      const pad = new THREE.Mesh(GEO.small, new THREE.MeshStandardMaterial({ color: pink, roughness: 0.6 })); pad.scale.set(0.06, 0.02, 0.07); pad.position.set(0, -0.06, 0.34); ft.add(pad);
    }
    const chest = this.chest = this._node(hips, [0, 0.12, 0.42]);
    this.bodyParts.push(this._fur(chest, 0.42, 0.46, 0.42, cream, 0.15, 62));
    this.bodyParts.push(this._fur(chest, 0.3, 0.32, 0.2, bib, 0.13, 40, [0, -0.08, 0.3]));
    for (const s of [-1, 1]) {
      const a = this._node(chest, [0.2 * s, -0.12, 0.24]); this.arms.push(a); this.bodyParts.push(a);
      this._fur(a, 0.085, 0.24, 0.09, cream, 0.035, 25, [0, -0.2, 0]);
      this._fur(a, 0.08, 0.06, 0.1, cream2, 0.03, 20, [0, -0.44, 0.03]);
    }
    const neck = this.neck = this._node(chest, [0, 0.36, 0.22]);
    const head = this.head = this._node(neck, [0, 0.22, 0.06]); head.scale.setScalar(1.24);
    this._fur(head, 0.35, 0.33, 0.37, cream, 0.11, 70);
    for (const s of [-1, 1]) this.cheeks.push(this._fur(head, 0.19, 0.15, 0.16, bib, 0.09, 40, [0.15 * s, -0.12, 0.2]));
    this._fur(head, 0.13, 0.1, 0.1, bib, 0.04, 40, [0, -0.11, 0.3]);
    this._fur(head, 0.12, 0.08, 0.1, white, 0.08, 36, [0, 0.29, 0.14]);
    for (const s of [-1, 1]) {
      const e = this._node(head, [0.12 * s, 0.26, -0.06]); e.rotation.z = -0.1 * s; this.ears.push(e);
      this._fur(e, 0.11, 0.4, 0.05, cream, 0.06, 40, [0, 0.4, 0]);
      const inner = new THREE.Mesh(GEO.small, new THREE.MeshLambertMaterial({ color: rgb(240, 175, 164), emissive: rgb(122, 58, 50) }));
      inner.scale.set(0.066, 0.33, 0.022); inner.position.set(0, 0.39, 0.04); e.add(inner);
    }
    // listening paw behind her ear (face close-ups)
    const lp = this.listenPaw = this._node(head, [0.33, 0.17, 0.03]); lp.rotation.set(0.2, -0.5, -0.55);
    this._fur(lp, 0.075, 0.1, 0.055, cream, 0.035, 26);
    const lpad = new THREE.Mesh(GEO.small, new THREE.MeshStandardMaterial({ color: pink, roughness: 0.6 })); lpad.scale.set(0.035, 0.04, 0.012); lpad.position.set(-0.02, 0, 0.05); lp.add(lpad);
    lp.scale.setScalar(0.001); lp.visible = false;
    // face, drawn on top of the fur
    const ink = rgb(42, 27, 24);
    for (const s of [-1, 1]) {
      const so = this._node(head, [0.19 * s, 0.035, 0.36]); so.rotation.y = 0.5 * s; this.sockets.push(so);
      const rim = this._faceBit(so, GEO.small, this._flat(rgb(226, 154, 152)), [0, 0, -0.01], [0.102, 0.112, 0.03], 98); this.eyeRims.push(rim);
      const eyeM = new THREE.MeshPhysicalMaterial({ color: rgb(18, 11, 10), roughness: 0.04, clearcoat: 1, clearcoatRoughness: 0.02 });
      const e = this._faceBit(so, GEO.small, eyeM, [0, 0, 0], [0.092, 0.104, 0.035], 99);
      this._faceBit(e, GEO.small, this._flat(new THREE.Color(107 / 255, 64 / 255, 54 / 255), 0.75), [0, -0.5, 0.7], [0.5, 0.26, 0.1], 100);
      this._faceBit(e, GEO.small, this._flat(white), [0.3 * s, 0.38, 0.9], [0.3, 0.26, 0.2], 101);
      this._faceBit(e, GEO.small, this._flat(white), [-0.32 * s, -0.42, 0.9], [0.12, 0.11, 0.1], 101);
      this._faceBit(e, GEO.small, this._flat(white, 0.9), [-0.05 * s, 0.5, 0.92], [0.06, 0.06, 0.06], 101);
      this.eyes.push(e);
      const lid = this._faceBit(so, this._arc(0.055, 0.016, 1.05), this._flat(ink), [0, -0.035, 0.02], [1, 1, 1], 102); this.lids.push(lid);
      const lg = [];
      [[0, 0.75], [1, 0.35]].forEach(([k, ang]) => {
        const l = this._faceBit(so, this._capsule(0.0055, 0.041), this._flat(ink), [0.072 * s, 0.07 - k * 0.022, 0.01]); l.rotation.z = -ang * s; lg.push(l);
      });
      this.lashes.push(lg);
      this.blushes.push(this._faceBit(head, GEO.small, this._flat(rgb(247, 161, 176)), [0.225 * s, -0.115, 0.37], [0.068, 0.04, 0.02], 97));
      this.tears.push(this._faceBit(head, GEO.small, this._flat(rgb(142, 200, 242)), [0.2 * s, -0.08, 0.41], [0.018, 0.028, 0.012], 103));
      const brow = this._faceBit(head, this._capsule(0.012, 0.124), this._flat(rgb(169, 139, 131)), [0.16 * s, 0.155, 0.4]); brow.rotation.z = Math.PI / 2; this.brows.push(brow);
    }
    const nose = this.nose = this._faceBit(head, GEO.small, new THREE.MeshStandardMaterial({ color: rgb(235, 160, 168), roughness: 0.35 }), [0, -0.06, 0.45], [0.032, 0.022, 0.02], 101);
    this._faceBit(nose, GEO.small, this._flat(white, 0.7), [-0.25, 0.35, 0.8], [0.3, 0.22, 0.2], 102);
    this.philtrum = this._faceBit(head, this._capsule(0.005, 0.04), this._flat(rgb(176, 124, 115)), [0, -0.088, 0.44]);
    const wm = new THREE.MeshBasicMaterial({ color: new THREE.Color(0.93, 0.93, 0.93), transparent: true, opacity: 0.8 });
    for (const s of [-1, 1]) for (let k = 0; k < 3; k++) {
      const w = new THREE.Mesh(new THREE.CylinderGeometry(0.0035, 0.0035, 0.42, 5), wm);
      w.position.set(0.07 * s + 0.2 * s, -0.09 - 0.012 * k, 0.38); w.rotation.set(0, 0.35 * s, Math.PI / 2 + (k - 1) * 0.16 * s); head.add(w); this.whiskers.push(w);
    }
    for (const s of [-1, 1]) {
      const m = this._faceBit(head, this._capsule(0.0055, 0.056), this._flat(rgb(155, 111, 102)), [0.022 * s, -0.112, 0.425]); m.rotation.z = Math.PI / 2 - 0.45 * s;
      if (s < 0) this.mouthL = m; else this.mouthR = m;
    }
    this.mouthO = this._faceBit(head, GEO.small, this._flat(rgb(184, 66, 79)), [0, -0.125, 0.425], [0.03, 0.025, 0.01]);
    this.tongue = this._faceBit(head, GEO.small, this._flat(rgb(244, 140, 156)), [0, -0.138, 0.43], [0.018, 0.011, 0.01], 101);
    // floating hearts and mood effects (sprites always face the camera)
    const heartM = new THREE.SpriteMaterial({ map: this._heartTex(), depthTest: false, depthWrite: false, transparent: true });
    this.hearts = [0, 1, 2].map(() => { const h = new THREE.Sprite(heartM.clone()); h.renderOrder = 110; h.scale.setScalar(0.16); S.add(h); return h; });
    this.fxTex = [this._glyphTex('✦', 'rgb(255,217,102)'), this._glyphTex('z', 'rgb(158,168,255)', true), this._glyphTex('?', 'rgb(184,156,255)', true),
      this._glyphTex('💢', 'red'), this._confettiTex(), this._glyphTex('♪', 'rgb(255,143,179)', true)];
    this.fx = Array.from({ length: 8 }, (_, i) => { const n = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.fxTex[0], depthTest: false, depthWrite: false, transparent: true, opacity: 0 }));
      n.renderOrder = 111; S.add(n); return { n, kind: 0, born: -100, seed: i * 0.37 }; });
    if (this.framing !== 'full') { this.bodyParts.forEach(b => (b.visible = false)); this.shadow.visible = false; }
  }

  // ---------- moving (every frame) ----------
  _frame(now) {
    const dt = this._last === 0 ? 1 / 60 : Math.min(0.05, now - this._last); this._last = now; this.t += dt;
    const t = this.t, E = (k, to, rate = 5) => { this[k] += (to - this[k]) * (1 - Math.exp(-dt * rate)); };
    const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
    const p = this.framing !== 'full' ? 'sit' : this.pose, left = this.faceLeft, ex = this.mood;
    const talkOn = this.talking;

    if (ex !== this.lastExpr) { this.lastExpr = ex; this.exprAt = t; if (ex === 'surprised') this.surpriseKick = 1; }
    const since = t - this.exprAt;
    E('happyE', ex === 'happy' ? 1 : 0, 7); E('laughE', ex === 'laugh' ? 1 : 0, 9); E('loveE', ex === 'love' ? 1 : 0, 6);
    E('crossE', ex === 'cross' ? 1 : 0, 8); E('sadE', ex === 'sad' ? 1 : 0, 5); E('surpriseE', ex === 'surprised' ? 1 : 0, 10);
    E('sleepE', ex === 'sleepy' ? 1 : 0, 3.5); E('winkE', ex === 'wink' ? 1 : 0, 10); E('thinkE', ex === 'thinking' || ex === 'busy' ? 1 : 0, 6);
    E('listenE', ex === 'listening' ? 1 : 0, 6);
    this.surpriseKick = Math.max(0, this.surpriseKick - dt * 2.2);
    const { happyE, laughE, loveE, crossE, sadE, surpriseE, sleepE, winkE, thinkE, listenE } = this;
    const joy = Math.max(happyE, laughE, loveE);

    const hopping = p === 'hop';
    E('hopAmt', hopping ? 1 : 0, 6); E('holdAmt', p === 'hold' ? 1 : 0, 4); E('cheer', p === 'happy' ? 1 : 0, 6);
    E('crossAmt', p === 'cross' ? 1 : 0, 6); E('listen', p === 'listen' ? 1 : 0, 4); E('waveAmt', p === 'wave' ? 1 : 0, 7);
    const wantStand = hopping ? 0 : p === 'hold' ? 1 : p === 'happy' ? 0.85 : p === 'wave' ? 0.78 : 0.62 + 0.1 * surpriseE + 0.08 * listenE;
    E('stand', wantStand, 3.5);
    E('turn', hopping ? (left ? -Math.PI / 2 : Math.PI / 2) : 0, 6);
    this.root.rotation.y = this.turn;
    const { hopAmt, holdAmt, cheer, crossAmt, stand, waveAmt } = this;

    this.phase += dt * 2.2 * hopAmt;
    const pp = this.phase % 1, ph = pp * Math.PI * 2;
    const air = (pp < 0.55 ? Math.sin(Math.PI * pp / 0.55) : 0) * hopAmt;
    const landSquash = (pp >= 0.55 && pp < 0.78 ? Math.sin(Math.PI * (pp - 0.55) / 0.23) : 0) * hopAmt;
    this.hips.scale.set(1, 1 - 0.08 * air - 0.1 * landSquash, 1 + 0.15 * air + 0.05 * landSquash);
    const kick = Math.sin(ph) * hopAmt;
    const still = p === 'sit' && !hopping;
    const bp = (since % 2.6) / 0.62, binky = still && happyE > 0.5 && bp < 1;
    const bAir = binky ? Math.sin(Math.PI * bp) * happyE : 0, bTwist = binky ? Math.sin(Math.PI * 2 * bp) * happyE : 0;
    const gig = laughE * Math.abs(Math.sin(t * 17));
    const jolt = this.surpriseKick > 0 ? Math.sin((1 - this.surpriseKick) * Math.PI) * 0.5 : 0;
    const yp = (since % 5) / 1.4, yawn = sleepE > 0.5 && yp < 1 ? Math.sin(Math.PI * yp) * sleepE : 0;
    const nod = sleepE * (1 - yawn) * (0.5 + 0.5 * Math.sin(t * 1.3));
    const pk = now - this.pokeAt, poke = pk < 0.9 ? 1 - pk / 0.9 : 0, earPoke = this.pokeEar ? poke : poke * 0.4;
    const STAND = 1.12, jump = cheer * Math.max(0, Math.sin(t * 9)) * 0.22;
    this.stance.rotation.x = -STAND * stand - 0.18 * kick;
    this.stance.rotation.y = 0.55 * bTwist;
    this.stance.rotation.z = 0.12 * bTwist;
    this.stance.position.y = 0.06 + 0.16 * air + jump + 0.32 * bAir + 0.025 * gig + 0.18 * jolt + 0.12 * poke * Math.abs(Math.sin(pk * 12));
    this.thighs.forEach(th => (th.rotation.x = 0.95 * kick - 0.6 * bAir));
    const stomp = Math.max(crossAmt, crossE) * Math.max(0, Math.sin(t * 9.5)) * 0.35;
    this.feet.forEach((f, i) => (f.rotation.x = STAND * stand - 0.9 * kick - (i === 1 ? stomp : 0) + 0.7 * bAir));
    const slow = Math.max(sadE, sleepE), br = 1 + (0.018 + 0.03 * sadE + 0.02 * sleepE) * Math.sin(t * (2.4 - 1.0 * slow));
    this.chest.scale.setScalar(br);

    const calm = still && !talkOn && ex === 'smile';
    if (calm && t > this.nextIdle) { this.idleKind = (this.idleKind + 1 + Math.floor(t * 7) % 3) % 4; this.idleStart = t; this.nextIdle = t + 7 + Math.floor(t * 13) % 6; }
    const ie = t - this.idleStart, win = dur => (ie < 0 || ie > dur) ? 0 : Math.min(1, Math.min(ie / 0.45, (dur - ie) / 0.45));
    E('groom', calm && this.idleKind === 0 ? win(3.4) : 0, 7); E('lookAround', calm && this.idleKind === 1 ? win(3.6) : 0, 5);
    E('earFlop', calm && this.idleKind === 2 ? win(3.0) : 0, 6); E('sniff', calm && this.idleKind === 3 ? win(2.4) : 0, 8);
    const { groom, lookAround, earFlop, sniff } = this;
    if (talkOn) {
      const s2 = now - this.talkStart, txt = this.talkText;
      const inText = txt && s2 >= 0 && s2 < txt.length / 14.5;
      const babble = 0.18 + 0.5 * Math.abs(Math.sin(t * 12.5)) * (0.55 + 0.45 * Math.sin(t * 3.3 + 1));
      E('talkOpen', inText ? Aurora3D.mouthOpen(txt, s2) : babble, 28);
    } else E('talkOpen', 0, 18);
    E('talkAmt', talkOn ? 1 : 0, 6);
    const { talkOpen, talkAmt } = this;
    const tw = (sniff > 0.1 || Math.sin(t * 0.7) > 0.93) ? 0.3 * Math.max(0, Math.sin(t * 22)) : 0;
    this.nose.scale.set(0.032, 0.022 * (1 + tw), 0.02);

    const swing = -1.0 * Math.sin(ph + Math.PI + 0.6) * hopAmt;
    const sitArms = 0.9 * (1 - hopAmt) * (1 - holdAmt) * (1 - cheer), holdArms = -0.16 * holdAmt, cheerArms = (-2.04 + 0.25 * Math.sin(t * 12)) * cheer;
    const feel = still ? 1 : 0;
    E('listenAmt', Math.max(this.listen, listenE) > 0.5 ? 1 : 0, 9);
    this.arms.forEach((a, i) => {
      const s = i === 0 ? -1 : 1;
      let x = swing + sitArms + holdArms + cheerArms, z = -0.15 * s * sitArms / 0.9 + 0.35 * s * cheer;
      x += groom * (-1.75 - sitArms + 0.22 * Math.sin(t * 13 + i)); z += -0.35 * s * groom;
      x += talkAmt * (-0.45 - 0.5 * Math.max(0, Math.sin(t * 3.4 + i * 1.7)));
      x += feel * laughE * (-1.55 - sitArms + 0.12 * Math.sin(t * 17 + i)); z += feel * laughE * -0.38 * s;
      x += feel * loveE * (-0.75 - sitArms * 0.4); z += feel * loveE * -0.42 * s;
      x += feel * crossE * (-1.05 - sitArms * 0.5); z += feel * crossE * -0.75 * s;
      x += feel * surpriseE * (-0.9 + 0.2 * jolt); z += feel * surpriseE * 0.55 * s;
      x += bAir * -1.6; z += bAir * 0.4 * s;
      if (i === 1) { x += feel * thinkE * (-1.85 - sitArms * 0.6); z += feel * thinkE * -0.42; }
      if (i === 1) { x += feel * this.listenAmt * (-2.5 - sitArms * 0.6); z += feel * this.listenAmt * 0.75; }
      x += feel * yawn * (-2.3 - sitArms * 0.5); z += feel * yawn * 0.35 * s;
      x += feel * sadE * 0.25;
      if (i === 1 && waveAmt > 0.01) { x = x * (1 - waveAmt) + -2.4 * waveAmt; z = z * (1 - waveAmt) + (0.45 + 0.4 * Math.sin(t * 9)) * waveAmt; }
      a.rotation.x = x; a.rotation.z = z;
    });

    E('yaw', hopping ? 0 : this.targetYaw, 5); E('pitch', hopping ? 0 : this.targetPitch, 5);
    const { yaw, pitch } = this;
    this.neck.rotation.x = STAND * stand * 0.85 + 0.08 * Math.sin(ph + 1) * hopAmt + pitch + 0.32 * groom + 0.06 * talkAmt * Math.sin(t * 5.2) - 0.1 * sniff
      + 0.12 * sadE + 0.28 * nod - 0.18 * yawn - 0.1 * laughE - 0.05 * gig + 0.08 * listenE - 0.1 * surpriseE;
    this.head.rotation.set(
      0.05 * sadE - 0.1 * thinkE + 0.1 * groom * Math.sin(t * 6) - 0.06 * surpriseE - 0.05 * Math.sin(t * 17) * laughE,
      yaw + Math.max(crossAmt, crossE) * 0.11 * Math.sin(t * 13) + 0.85 * lookAround * Math.sin(ie * 1.7) - 0.15 * thinkE,
      0.2 * Math.max(this.listen, listenE, thinkE) + 0.03 * Math.sin(t * 0.9) + 0.05 * talkAmt * Math.sin(t * 2.3) + 0.16 * loveE * Math.sin(t * 2.2) + 0.12 * winkE - 0.08 * sadE);
    this.cheeks.forEach(c => { const k = 1 + 0.14 * crossE; c.scale.set(0.19 * k, 0.15 * k, 0.16 * k); });
    {
      const show = this.framing !== 'full' ? this.listenAmt : 0, lp = this.listenPaw;
      lp.visible = show >= 0.02; const k = Math.max(0.001, show * (1 + 0.04 * Math.sin(t * 5))); lp.scale.setScalar(k); lp.rotation.z = -0.55 + 0.08 * Math.sin(t * 2.2);
    }

    this.ears.forEach((e, i) => {
      const s = i === 0 ? -1 : 1, twitch = Math.sin(t * 0.9 + i * 2) > 0.97 ? 0.25 : 0, fl = Math.max(crossAmt, crossE);
      let rx = -0.25 * kick + 0.04 * Math.sin(t * 3 + i) - 0.15 * stand - 0.75 * fl - 0.45 * sadE - 0.55 * sleepE + 0.28 * surpriseE + 0.22 * listenE
        - 0.5 * groom - (i === 0 ? 0.35 * earFlop : 0) + 0.06 * talkAmt * Math.sin(t * 5.2 + i)
        - 0.55 * air + 0.25 * landSquash - 0.9 * bAir + (i === 0 ? -0.45 * thinkE : 0) + 0.1 * laughE * Math.sin(t * 17 + i);
      let rz = -0.12 * s - twitch * s + 0.25 * s * fl - 0.08 * s * Math.max(cheer, happyE) - 0.75 * s * sadE - 0.35 * s * sleepE
        - 0.1 * s * surpriseE - 0.08 * s * listenE + (i === 1 ? 1.0 * s * earFlop : 0) + 0.08 * s * loveE * Math.sin(t * 2.2);
      const ry = 0.35 * s * lookAround * Math.sin(ie * 1.7 + i) - 0.35 * s * Math.max(this.listen, listenE);
      if (earPoke > 0) { rz += 0.45 * s * earPoke * Math.sin(pk * 34 + i); rx -= 0.5 * earPoke; }
      const dYaw = (yaw - this.lastYaw) / Math.max(dt, 0.001), dPitch = (pitch - this.lastPitch) / Math.max(dt, 0.001), K = 90, damp = 7;
      this.earVel[i] += (-K * this.earSpring[i] - damp * this.earVel[i] - 0.9 * dYaw - 2.2 * air * s) * dt;
      this.earSpring[i] = clamp(this.earSpring[i] + this.earVel[i] * dt, -0.6, 0.6);
      this.earVelX[i] += (-K * this.earSpringX[i] - damp * this.earVelX[i] + 0.7 * dPitch + 1.6 * landSquash) * dt;
      this.earSpringX[i] = clamp(this.earSpringX[i] + this.earVelX[i] * dt, -0.5, 0.5);
      rz += this.earSpring[i] * s * 0.8 + this.earSpring[i] * 0.4; rx += this.earSpringX[i];
      e.rotation.set(rx, ry, rz);
    });
    this.lastYaw = yaw; this.lastPitch = pitch;

    if (t > this.nextBlink + 0.16) this.nextBlink = t + 2.5 + (Math.sin(t * 3.7) + 1) * 1.5;
    const blink = (t > this.nextBlink && t < this.nextBlink + 0.16) ? 0.1 : 1;
    E('lookX', 0.012 * thinkE + 0.006 * Math.sin(t * 0.37) * (1 - thinkE), 4);
    E('lookY', 0.012 * thinkE - 0.012 * sadE - 0.008 * loveE, 4);
    const chatty = talkAmt * (ex === 'smile' ? 1 : 0.4);
    const lift = chatty * Math.max(0, Math.sin(t * 2.6)) * Math.max(0, Math.sin(t * 1.1 + 0.5));
    const squint = Math.max(happyE, cheer, 0.22 * chatty);
    const eyeOpen = [];
    this.eyes.forEach((e, i) => {
      const s = i === 0 ? -1 : 1;
      let y = 0.104 * blink * (1 - 0.42 * squint) * (1 - 0.35 * loveE) * (1 - 0.3 * Math.max(crossAmt, crossE))
        * (1 - 0.9 * sleepE * (0.5 + 0.5 * Math.max(nod, yawn * 2))) * (1 + 0.22 * surpriseE) * (1 - 0.15 * sadE) * (1 - laughE);
      if (i === 1) y *= 1 - 0.92 * winkE;
      y = Math.max(0.004, y);
      e.scale.y += (y - e.scale.y) * Math.min(1, dt * 22);
      const w = 0.092 * (1 + 0.12 * surpriseE); e.scale.x = w;
      this.sockets[i].position.set(0.19 * s + this.lookX, 0.035 + this.lookY, 0.36);
      this.eyeRims[i].scale.set(w * (0.102 / 0.092), e.scale.y * (0.112 / 0.104), 0.03);
      const closed = Math.max(laughE, i === 1 ? winkE : 0);
      this.lashes[i].forEach((l, k) => (l.position.y = closed > 0.5 ? 0.02 - k * 0.01 : e.scale.y * 0.72 - k * 0.022 * (e.scale.y / 0.104)));
      eyeOpen.push(e.scale.y);
    });
    const browOn = Math.max(crossAmt, crossE, sadE, thinkE * 0.8, surpriseE * 0.85, 0.7 * lift);
    this.brows.forEach((b, i) => {
      const s = i === 0 ? -1 : 1, tilt = 0.5 * Math.max(crossAmt, crossE) - 0.45 * sadE + (i === 1 ? -0.3 * thinkE : 0);
      b.rotation.z = Math.PI / 2 + tilt * s;
      b.position.y = 0.155 + 0.05 * surpriseE + (i === 1 ? 0.03 * thinkE : 0) - 0.015 * crossE + 0.03 * lift;
    });
    this.tears.forEach((tr, i) => { const c = ((t + i * 0.8) % 1.8) / 1.8; tr.position.y = -0.07 - 0.13 * c; });
    const blushK = 1 + 0.25 * loveE; this.blushes.forEach(b => b.scale.set(0.068 * blushK, 0.04 * blushK, 0.02));

    const laughOpen = laughE * (0.55 + 0.35 * Math.abs(Math.sin(t * 17)));
    const mOpen = Math.max(laughOpen, surpriseE * 0.55, yawn * 1.4, Math.min(1, talkOpen * talkAmt));
    const smileTilt = (0.45 + 0.2 * joy + 0.15 * winkE + 0.12 * chatty) * (1 - sadE * 2) * (1 - crossE * 0.6);
    this.mouthL.rotation.z = Math.PI / 2 - smileTilt; this.mouthR.rotation.z = Math.PI / 2 + smileTilt;
    const round = surpriseE + yawn, mBig = this.framing === 'closeFace' ? 1.7 : 1;
    this.mouthO.scale.set((0.026 + 0.012 * mOpen + 0.012 * laughE - 0.006 * round) * mBig, (0.008 + 0.034 * mOpen) * mBig, 0.01);
    this.tongue.position.y = -0.125 - 0.02 * mOpen;

    E('bounce', talkAmt * (0.5 + 0.5 * talkOpen), 14);
    const sq = 0.035 * this.bounce * Math.sin(t * 11);
    this.head.scale.set(1.24 * (1 - sq * 0.5), 1.24 * (1 + sq), 1.24 * (1 - sq * 0.5));
    if (calm) { this.stance.rotation.z += 0.035 * Math.sin(t * 0.55); this.stance.position.x = 0.03 * Math.sin(t * 0.55); } else this.stance.position.x *= 0.9;

    this.scene.updateMatrixWorld(true);
    const hp = new THREE.Vector3(); this.head.getWorldPosition(hp);
    // mood effects
    const want = sleepE > 0.5 ? 1 : thinkE > 0.5 ? 2 : Math.max(crossE, crossAmt) > 0.5 ? 3 : (laughE > 0.4 || cheer > 0.5) ? 4
      : happyE > 0.5 ? 0 : (talkAmt > 0.6 && Math.sin(t * 0.3) > 0.6) ? 5 : null;
    if (want !== null && t > this.nextFx) {
      const slot = this.fx.reduce((a, b) => (b.born < a.born ? b : a));
      slot.kind = want; slot.born = t; slot.seed = Math.random(); slot.n.material.map = this.fxTex[want]; slot.n.material.needsUpdate = true;
      this.nextFx = t + (want === 4 ? 0.18 : want === 1 ? 0.9 : want === 2 ? 1.4 : want === 3 ? 1.1 : want === 5 ? 0.8 : 0.45);
    }
    for (const f of this.fx) {
      const life = f.kind === 4 ? 1.4 : 1.8, a = (t - f.born) / life;
      if (a < 0 || a >= 1) { f.n.material.opacity = 0; f.n.visible = false; continue; }
      f.n.visible = true;
      const sd = f.seed, side = sd < 0.5 ? -1 : 1;
      let x = hp.x + side * (0.28 + 0.2 * sd), y = hp.y + 0.3 + 0.7 * a, z = hp.z + 0.3;
      if (f.kind === 1) { x = hp.x + 0.3 + 0.25 * a + 0.05 * Math.sin(a * 9); y = hp.y + 0.35 + 0.55 * a; }
      else if (f.kind === 2) { x = hp.x + 0.34; y = hp.y + 0.5 + 0.12 * a; }
      else if (f.kind === 3) { x = hp.x + 0.32 * side; y = hp.y + 0.45 + 0.08 * Math.sin(a * 20); }
      else if (f.kind === 4) { x = hp.x + (sd - 0.5) * 1.6 * a; y = hp.y + 0.6 + 0.5 * Math.sin(Math.PI * a) - 0.6 * a * a; z = hp.z + 0.2 + 0.3 * sd; }
      else x += 0.06 * Math.sin(t * 4 + sd * 6);
      f.n.position.set(x, y, z);
      const grow = f.kind === 3 ? 0.9 + 0.25 * Math.sin(a * 20) : 0.6 + 0.6 * Math.min(1, a * 3);
      f.n.scale.setScalar(0.14 * grow);
      f.n.material.rotation = f.kind === 4 ? a * 8 * (sd - 0.5) : 0;
      f.n.material.opacity = Math.sin(Math.PI * a) * (f.kind === 2 ? 1 : 0.95);
    }
    this.hearts.forEach((h, i) => {
      const c = (t * 0.55 + i / 3) % 1;
      h.position.set(hp.x + (i - 1) * 0.32 + 0.05 * Math.sin(t * 3 + i), hp.y + 0.35 + 0.65 * c, hp.z + 0.3);
      h.material.opacity = loveE * Math.sin(Math.PI * c); h.visible = h.material.opacity > 0.01; h.scale.setScalar(0.16 * (0.7 + 0.5 * c));
    });

    // camera first (the face parts fade by where it is)
    if (this.framing === 'closeFace') { this.cam.position.set(hp.x, hp.y, hp.z + 3.05); this.cam.lookAt(hp.x, hp.y - 0.07, hp.z); }
    else if (this.framing === 'face') { this.cam.position.set(hp.x, hp.y + 0.46, hp.z + 3.95); this.cam.lookAt(hp.x, hp.y + 0.42, hp.z); }
    else { this.cam.position.set(0, 1.15 + 0.2 * stand, 6.2); this.cam.lookAt(0, 0.95 + 0.25 * stand, 0); }
    this.cam.updateMatrixWorld();
    const camP = this.cam.position, wp = new THREE.Vector3(), dir = new THREE.Vector3();
    const vis = f => { f.getWorldPosition(wp); f.getWorldDirection(dir); const to = camP.clone().sub(wp); const d = dir.dot(to) / Math.max(0.0001, to.length()); return clamp((d - 0.1) / 0.25); };
    const show = (f, want) => f && this._setOpacity(f, vis(f) * want);
    this.eyes.forEach((e, i) => {
      show(e, 1); show(this.eyeRims[i], clamp(eyeOpen[i] / 0.03));
      const closed = Math.max(laughE, i === 1 ? winkE : 0);
      show(this.lids[i], closed);
      this.lashes[i].forEach(l => show(l, clamp(eyeOpen[i] / 0.05) * (1 - closed) + closed));
    });
    this.brows.forEach(b => show(b, browOn));
    this.tears.forEach((tr, i) => { const c = ((t + i * 0.8) % 1.8) / 1.8; show(tr, sadE * Math.sin(Math.PI * c)); });
    this.blushes.forEach(b => show(b, 0.28 + 0.3 * joy + 0.35 * loveE + 0.25 * crossE + 0.15 * winkE));
    show(this.nose, 1); show(this.philtrum, 1);
    const lineOn = 1 - Math.min(1, mOpen * 2);
    show(this.mouthL, lineOn); show(this.mouthR, lineOn); show(this.mouthO, Math.min(1, mOpen * 2));
    show(this.tongue, Math.min(1, mOpen * 2) * Math.max(laughE, yawn, talkAmt * 0.6));

    this.renderer.render(this.scene, this.cam);
  }

  /** How open the mouth is for the letter being said right now (vowels open, m/b/p closed). */
  static mouthOpen(text, since) {
    const chars = text.toLowerCase(), x = since * 14.5, i = Math.floor(x);
    if (since < 0 || i >= chars.length) return 0.25 + 0.25 * Math.abs(Math.sin(since * 11));
    const v = c => 'a'.includes(c) ? 1 : c === 'o' ? 0.85 : 'eiy'.includes(c) ? 0.6 : 'uw'.includes(c) ? 0.5 : 'mbp'.includes(c) ? 0 : ' ,.!?'.includes(c) ? 0.05 : 0.35;
    const f = x - i, n = i + 1 < chars.length ? v(chars[i + 1]) : 0;
    return v(chars[i]) * (1 - f) + n * f;
  }
}
