// Sparrow for Mac and Windows — one friendly panel that drops down from the top of
// the screen, a tiny bar that stays there, and a menu-bar / tray icon. It keeps running
// in the background so reminders, the morning briefing and the check-in always happen.
const { app, BrowserWindow, Tray, Menu, ipcMain, shell, screen, globalShortcut, protocol, net, nativeImage,
  session, clipboard, dialog, systemPreferences } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { spawn, execFile } = require('child_process');
const { pathToFileURL } = require('url');

const isWin = process.platform === 'win32';
const isMac = process.platform === 'darwin';
const WWW = path.join(__dirname, 'www');
const MODEL = app.isPackaged ? path.join(process.resourcesPath, 'model') : path.join(__dirname, 'model');
const dataFile = n => path.join(app.getPath('userData'), n);

let panel = null, tray = null, quitting = false;
let settings = { login: true, pill: true, firstRun: true, clipboard: true, watch: [] };

function loadSettings() { try { settings = Object.assign(settings, JSON.parse(fs.readFileSync(dataFile('sparrow-settings.json'), 'utf8'))); } catch {} }
function saveSettings() { try { fs.writeFileSync(dataFile('sparrow-settings.json'), JSON.stringify(settings)); } catch {} }

if (!app.requestSingleInstanceLock()) app.quit();
app.on('second-instance', () => showPanel());
app.setAppUserModelId('app.sparrowai.sparrow');

protocol.registerSchemesAsPrivileged([{ scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true, corsEnabled: true } }]);
function serveApp() {
  protocol.handle('app', req => {
    const u = new URL(req.url);
    let p = decodeURIComponent(u.pathname), base = WWW;
    if (p.startsWith('/model/')) { base = MODEL; p = p.slice('/model'.length); }
    const file = path.normalize(path.join(base, p === '/' ? '/index.html' : p));
    if (!file.startsWith(base)) return new Response('no', { status: 403 });
    return net.fetch(pathToFileURL(file).toString());
  });
}

const run = (cmd, args, opts = {}) => new Promise(res => execFile(cmd, args, { windowsHide: true, maxBuffer: 16e6, timeout: opts.timeout || 15000 }, (err, out) => res(err ? '' : String(out))));
const osa = script => run('osascript', ['-e', script]);
const ps = script => run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { timeout: 20000 });
const detached = (cmd, args) => { try { spawn(cmd, args, { detached: true, windowsHide: true, stdio: 'ignore' }).unref(); } catch {} };

// ---------- windows ----------
// The Sparrow island: one see-through window across the top of the screen. Only the island itself
// catches the mouse; everything else clicks straight through to your apps.
let expanded = false;
function islandBounds() {
  const d = screen.getPrimaryDisplay(), b = d.bounds, wa = d.workArea;
  const W = 560, top = isMac ? b.y : wa.y;
  const H = Math.min(880, wa.y + wa.height - top - 8);
  return { width: W, height: H, x: Math.round(b.x + (b.width - W) / 2), y: top };
}
function createPanel() {
  panel = new BrowserWindow({
    ...islandBounds(), show: false, frame: false, transparent: true, backgroundColor: '#00000000', resizable: false, movable: false,
    minimizable: false, maximizable: false, hasShadow: false, alwaysOnTop: true, skipTaskbar: true, fullscreenable: false,
    roundedCorners: false, enableLargerThanScreen: true, title: 'Sparrow', icon: path.join(WWW, 'icons', 'icon-512.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false,
      backgroundThrottling: false, autoplayPolicy: 'no-user-gesture-required', spellcheck: false,
    },
  });
  panel.setAlwaysOnTop(true, 'screen-saver');
  panel.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  panel.setIgnoreMouseEvents(true, { forward: true });
  panel.loadURL('app://sparrow/index.html');
  panel.once('ready-to-show', () => panel.showInactive());
  panel.on('close', e => { if (!quitting) e.preventDefault(); });
  panel.on('blur', () => { if (expanded) toPanel('island', 'collapse'); });
  panel.webContents.setWindowOpenHandler(({ url }) => { shell.openExternal(url); return { action: 'deny' }; });
  panel.webContents.on('will-navigate', (e, url) => { if (!url.startsWith('app://')) { e.preventDefault(); shell.openExternal(url); } });
}
function focusIsland() { panel.setIgnoreMouseEvents(false); if (isMac) app.focus({ steal: true }); panel.focus(); }
function showPanel() { if (!panel) return; expanded = true; focusIsland(); toPanel('island', 'expand'); }
function togglePanel() { expanded ? toPanel('island', 'collapse') : showPanel(); }
const toPanel = (ch, v) => panel && panel.webContents.send(ch, v);
ipcMain.on('island-state', (_e, st) => { expanded = st === 'expanded'; if (expanded) focusIsland(); });
ipcMain.on('mouse-inside', (_e, inside) => panel && panel.setIgnoreMouseEvents(!inside, { forward: true }));

// ---------- tray / menu bar ----------
function createTray() {
  let img = nativeImage.createFromPath(path.join(WWW, 'icons', 'icon-192.png')).resize({ width: isMac ? 18 : 16, height: isMac ? 18 : 16 });
  tray = new Tray(img);
  tray.setToolTip('Sparrow');
  const menu = () => Menu.buildFromTemplate([
    { label: 'Open Sparrow', accelerator: 'CommandOrControl+Shift+Space', click: showPanel },
    { label: 'Talk to Sparrow', click: () => { showPanel(); toPanel('command', 'listen'); } },
    { type: 'separator' },
    { label: 'Show the island when closed', type: 'checkbox', checked: settings.pill, click: i => setSetting('pill', i.checked) },
    { label: isMac ? 'Open at login' : 'Start with Windows', type: 'checkbox', checked: settings.login, click: i => setSetting('login', i.checked) },
    { type: 'separator' },
    { label: 'Quit Sparrow', click: () => { quitting = true; app.quit(); } },
  ]);
  tray.setContextMenu(menu());
  if (!isMac) tray.on('click', togglePanel);
  tray.refresh = () => tray.setContextMenu(menu());
}
function setSetting(k, v) {
  settings[k] = v; saveSettings();
  if (k === 'login') app.setLoginItemSettings({ openAtLogin: v, openAsHidden: true, args: ['--hidden'] });
  if (k === 'pill') toPanel('island', v ? 'show-cap' : 'hide-cap');
  if (k === 'clipboard') v ? startClipboard() : stopClipboard();
  tray && tray.refresh && tray.refresh();
}

// ---------- opening apps ----------
const norm = s => String(s).toLowerCase().replace(/[^a-z0-9 ]/g, '').replace(/\s+/g, ' ').trim();
const FOLDERS = { downloads: 'downloads', documents: 'documents', desktop: 'desktop', pictures: 'pictures', photos: 'pictures', music: 'music', videos: 'videos', movies: 'videos', home: 'home' };
const WIN_KNOWN = {
  chrome: 'chrome', 'google chrome': 'chrome', edge: 'msedge', 'microsoft edge': 'msedge', firefox: 'firefox',
  notepad: 'notepad', calculator: 'calc', calc: 'calc', paint: 'mspaint', 'task manager': 'taskmgr',
  explorer: 'explorer', 'file explorer': 'explorer', files: 'explorer', cmd: 'cmd', 'command prompt': 'cmd', terminal: 'wt',
  powershell: 'powershell', 'control panel': 'control', word: 'winword', excel: 'excel', powerpoint: 'powerpnt', outlook: 'outlook',
  'vs code': 'code', vscode: 'code', 'visual studio code': 'code', cursor: 'cursor',
  settings: 'ms-settings:', 'wifi settings': 'ms-settings:network-wifi', bluetooth: 'ms-settings:bluetooth',
  spotify: 'spotify:', whatsapp: 'whatsapp:', teams: 'msteams:', camera: 'microsoft.windows.camera:', store: 'ms-windows-store:',
  photos: 'ms-photos:', clock: 'ms-clock:', mail: 'outlookmail:', calendar: 'outlookcal:', maps: 'bingmaps:', 'snipping tool': 'ms-screenclip:',
};
const MAC_ALIAS = { chrome: 'Google Chrome', 'vs code': 'Visual Studio Code', vscode: 'Visual Studio Code', code: 'Visual Studio Code',
  settings: 'System Settings', 'system preferences': 'System Settings', terminal: 'Terminal', files: 'Finder', finder: 'Finder',
  word: 'Microsoft Word', excel: 'Microsoft Excel', powerpoint: 'Microsoft PowerPoint', outlook: 'Microsoft Outlook', teams: 'Microsoft Teams',
  calculator: 'Calculator', notes: 'Notes', mail: 'Mail', calendar: 'Calendar', music: 'Music', photos: 'Photos', safari: 'Safari', cursor: 'Cursor' };
let apps = [];   // [{ name, id }] — id = Windows AppID or Mac .app path

function loadApps() {
  if (isWin) {
    ps('Get-StartApps | ConvertTo-Json -Compress').then(out => {
      try { apps = [].concat(JSON.parse(out)).map(a => ({ name: String(a.Name), id: String(a.AppID) })); } catch {}
    });
  } else if (isMac) {
    run('mdfind', ["kMDItemContentType == 'com.apple.application-bundle'"]).then(out => {
      apps = out.split('\n').filter(p => p.endsWith('.app') && !p.includes('/Library/') || p.startsWith('/System/Applications/'))
        .filter(Boolean).map(p => ({ name: path.basename(p, '.app'), id: p }));
    });
  }
}
function findApp(name) {
  return apps.find(a => norm(a.name) === name) || apps.find(a => norm(a.name).startsWith(name)) || (name.length > 3 && apps.find(a => norm(a.name).includes(name)));
}
function openApp(raw) {
  const name = norm(String(raw).replace(/^(the|my)\s+/i, '').replace(/\s+(app|application|program)$/i, ''));
  if (!name) return false;
  const folder = FOLDERS[name] || FOLDERS[name.replace(/ folder$/, '')];
  if (folder) { shell.openPath(app.getPath(folder)); return true; }
  if (isMac) {
    const hit = findApp(norm(MAC_ALIAS[name] || name));
    if (hit) { detached('open', [hit.id]); return true; }
    return false;
  }
  if (isWin) {
    const hit = findApp(name);
    if (hit) { detached('explorer.exe', [`shell:AppsFolder\\${hit.id}`]); return true; }
    const k = WIN_KNOWN[name];
    if (k) { k.includes(':') ? shell.openExternal(k) : detached('cmd.exe', ['/c', 'start', '""', k]); return true; }
  }
  return false;
}

// ---------- media, volume, lock ----------
const VK = { playpause: 179, next: 176, prev: 177, volup: 175, voldown: 174, mute: 173 };
async function media(cmd) {
  if (isMac) {
    if (cmd === 'lock') return detached('pmset', ['displaysleepnow']);
    if (cmd.startsWith('vol:')) return osa(`set volume output volume ${+cmd.slice(4)}`);
    if (cmd === 'volup') return osa('set volume output volume ((output volume of (get volume settings)) + 12)');
    if (cmd === 'voldown') return osa('set volume output volume ((output volume of (get volume settings)) - 12)');
    if (cmd === 'mute') return osa('set volume output muted (not (output muted of (get volume settings)))');
    const verb = { playpause: 'playpause', next: 'next track', prev: 'previous track' }[cmd];
    if (!verb) return;
    return osa(`if application "Spotify" is running then
  tell application "Spotify" to ${verb}
else
  tell application "Music" to ${verb}
end if`);
  }
  if (!isWin) return;
  if (cmd === 'lock') return detached('rundll32.exe', ['user32.dll,LockWorkStation']);
  if (cmd.startsWith('vol:')) {
    const n = Math.round(+cmd.slice(4) / 2);
    return ps(`$w=New-Object -ComObject WScript.Shell; 1..50|%{$w.SendKeys([char]174)}; 1..${n}|%{$w.SendKeys([char]175)}`);
  }
  const code = VK[cmd]; if (!code) return;
  const times = cmd === 'volup' || cmd === 'voldown' ? 5 : 1;
  return ps(`$w=New-Object -ComObject WScript.Shell; 1..${times}|%{$w.SendKeys([char]${code})}`);
}

// Play a song: Apple Music plays straight from your library; Spotify/YouTube open the search.
async function playSong(q, where) {
  const esc = s => s.replace(/["\\]/g, '');
  if (where === 'music' && isMac) {
    const r = await osa(`tell application "Music"
  set hits to (every track of library playlist 1 whose name contains "${esc(q)}" or artist contains "${esc(q)}")
  if (count of hits) > 0 then
    play item 1 of hits
    return "ok"
  end if
end tell
return "none"`);
    if (r.trim() === 'ok') return 'playing';
  }
  if (where === 'youtube') { shell.openExternal('https://www.youtube.com/results?search_query=' + encodeURIComponent(q)); return 'search'; }
  shell.openExternal('spotify:search:' + encodeURIComponent(q));
  return 'search';
}

// ---------- files ----------
const HOME_DIRS = () => ['desktop', 'documents', 'downloads'].map(k => app.getPath(k));
function walk(dir, q, out, depth = 0) {
  if (depth > 4 || out.length >= 40) return;
  let list = [];
  try { list = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const d of list) {
    if (d.name.startsWith('.') || d.name === 'node_modules') continue;
    const p = path.join(dir, d.name);
    if (d.isDirectory()) walk(p, q, out, depth + 1);
    else if (norm(d.name).includes(q)) out.push(p);
    if (out.length >= 40) return;
  }
}
async function findFiles(query) {
  const q = norm(query);
  if (!q) return [];
  let paths = [];
  if (isMac) {
    const home = os.homedir();
    const byName = await run('mdfind', ['-onlyin', home, '-name', query]);
    const byText = await run('mdfind', ['-onlyin', home, query]);
    paths = [...byName.split('\n'), ...byText.split('\n')].filter(p => p && !p.includes('/Library/') && !/\/\./.test(p));
  } else if (isWin) {
    const s = query.replace(/'/g, "''").replace(/"/g, '');
    const out = await ps(`$c=New-Object -ComObject ADODB.Connection; $c.Open("Provider=Search.CollatorDSO;Extended Properties='Application=Windows';");` +
      `$r=$c.Execute("SELECT TOP 40 System.ItemPathDisplay FROM SYSTEMINDEX WHERE SCOPE='file:${os.homedir().replace(/\\/g, '/').replace(/'/g, "''")}' AND (System.FileName LIKE '%${s}%' OR FREETEXT('${s}'))");` +
      `while(-not $r.EOF){$r.Fields.Item(0).Value; $r.MoveNext()}`);
    paths = out.split(/\r?\n/).filter(Boolean);
  }
  if (!paths.length) HOME_DIRS().forEach(d => walk(d, q, paths));
  const seen = new Set();
  return paths.filter(p => !seen.has(p) && seen.add(p)).slice(0, 25).map(p => {
    let st = null; try { st = fs.statSync(p); } catch {}
    return st && st.isFile() ? { path: p, name: path.basename(p), size: st.size, mtime: st.mtimeMs } : null;
  }).filter(Boolean).sort((a, b) => b.mtime - a.mtime);
}
async function recentFiles(days = 7) {
  const since = Date.now() - days * 86400e3, out = [];
  if (isMac) {
    const r = await run('mdfind', ['-onlyin', os.homedir(), `kMDItemLastUsedDate >= $time.today(-${days})`]);
    r.split('\n').filter(p => p && !p.includes('/Library/') && !p.endsWith('.app')).slice(0, 60).forEach(p => out.push(p));
  } else if (isWin) {
    const dir = path.join(app.getPath('appData'), 'Microsoft', 'Windows', 'Recent');
    try { fs.readdirSync(dir).filter(f => f.endsWith('.lnk')).forEach(f => { const p = path.join(dir, f); try { if (fs.statSync(p).mtimeMs > since) out.push(p); } catch {} }); } catch {}
  }
  return out.slice(0, 60).map(p => { let st = {}; try { st = fs.statSync(p); } catch {} return { path: p, name: path.basename(p).replace(/\.lnk$/, ''), mtime: st.mtimeMs || 0 }; })
    .sort((a, b) => b.mtime - a.mtime);
}
const KINDS = { Images: /\.(png|jpe?g|gif|webp|heic|svg|bmp|tiff?)$/i, PDFs: /\.pdf$/i, Documents: /\.(docx?|txt|rtf|odt|pages|md|xlsx?|csv|pptx?|key|numbers)$/i,
  Archives: /\.(zip|rar|7z|tar|gz)$/i, Installers: /\.(dmg|pkg|exe|msi|appx)$/i, Audio: /\.(mp3|wav|m4a|aac|flac|ogg)$/i, Videos: /\.(mp4|mov|mkv|avi|webm)$/i };
function tidyDownloads(apply) {
  const dir = app.getPath('downloads'), plan = {};
  let files = [];
  try { files = fs.readdirSync(dir, { withFileTypes: true }).filter(d => d.isFile() && !d.name.startsWith('.')).map(d => d.name); } catch {}
  for (const f of files) {
    const kind = Object.keys(KINDS).find(k => KINDS[k].test(f)) || 'Other';
    (plan[kind] = plan[kind] || []).push(f);
  }
  if (apply) for (const [kind, list] of Object.entries(plan)) {
    const to = path.join(dir, kind); fs.mkdirSync(to, { recursive: true });
    for (const f of list) {
      let dest = path.join(to, f), n = 1;
      while (fs.existsSync(dest)) dest = path.join(to, `${path.parse(f).name} (${n++})${path.parse(f).ext}`);
      try { fs.renameSync(path.join(dir, f), dest); } catch {}
    }
  }
  return Object.fromEntries(Object.entries(plan).map(([k, v]) => [k, v.length]));
}

// Folder watcher: tell the person when a new file arrives.
const watchers = new Map();
function startWatch(dir) {
  if (watchers.has(dir) || !fs.existsSync(dir)) return;
  let known = new Set(); try { known = new Set(fs.readdirSync(dir)); } catch {}
  try {
    const w = fs.watch(dir, () => setTimeout(() => {
      let now = []; try { now = fs.readdirSync(dir); } catch {}
      for (const f of now) if (!known.has(f) && !f.startsWith('.') && !/\.(crdownload|part|tmp|download)$/i.test(f)) {
        known.add(f); toPanel('event', { type: 'file-arrived', name: f, folder: path.basename(dir), path: path.join(dir, f) });
      }
    }, 1500));
    watchers.set(dir, w);
  } catch {}
}
function stopWatch(dir) { const w = watchers.get(dir); if (w) { w.close(); watchers.delete(dir); } }

// Clipboard history (kept on this computer only)
let clipTimer = null, clips = [], lastClip = '';
function loadClips() { try { clips = JSON.parse(fs.readFileSync(dataFile('clipboard.json'), 'utf8')); } catch { clips = []; } }
function startClipboard() {
  if (clipTimer) return;
  lastClip = clipboard.readText();
  clipTimer = setInterval(() => {
    const t = clipboard.readText();
    if (t && t !== lastClip && t.length < 20000) {
      lastClip = t;
      clips = [{ text: t, at: Date.now() }, ...clips.filter(c => c.text !== t)].slice(0, 60);
      try { fs.writeFileSync(dataFile('clipboard.json'), JSON.stringify(clips)); } catch {}
    }
  }, 1200);
}
function stopClipboard() { clearInterval(clipTimer); clipTimer = null; }

// ---------- Ollama (free AI on this computer) ----------
async function ollama(kind, body) {
  try {
    if (kind === 'models') {
      const r = await net.fetch('http://127.0.0.1:11434/api/tags');
      const j = await r.json();
      return (j.models || []).map(m => m.name).filter(n => !/embed|cloud|nomic|bge/i.test(n));
    }
    const r = await net.fetch('http://127.0.0.1:11434/api/chat', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    const j = await r.json();
    if (j.error) throw new Error(j.error);
    return j.message?.content || '';
  } catch (e) { if (kind === 'models') return []; throw e; }
}

// ---------- email (Mac Mail app) ----------
async function mail(kind, text) {
  if (!isMac) return { error: 'not-mac' };
  if (kind === 'latest') {
    const out = await osa(`tell application "Mail"
  set m to item 1 of (messages of inbox)
  return (sender of m) & "\\n" & (subject of m) & "\\n" & (date received of m as string) & "\\n" & (content of m)
end tell`);
    if (!out) return { error: 'no-access' };
    const [from, subject, date, ...body] = out.split('\n');
    return { from, subject, date, body: body.join('\n').slice(0, 4000) };
  }
  if (kind === 'reply') {
    const safe = String(text).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
    const out = await osa(`tell application "Mail"
  set m to item 1 of (messages of inbox)
  set r to reply m with opening window
  set content of r to "${safe}" & return & return & (content of r)
  activate
end tell
return "ok"`);
    return out.trim() === 'ok' ? { ok: true } : { error: 'no-access' };
  }
}

// ---------- location (real position for the weather) ----------
async function location() {
  if (isWin) {
    const out = await ps(`Add-Type -AssemblyName System.Device; $w=New-Object System.Device.Location.GeoCoordinateWatcher; $w.Start();` +
      `$t=0; while(($w.Status -ne 'Ready') -and ($t -lt 60)){Start-Sleep -Milliseconds 100; $t++}; $c=$w.Position.Location;` +
      `if(-not $c.IsUnknown){"$($c.Latitude),$($c.Longitude)"}`);
    const m = out.trim().match(/^(-?[\d.]+),(-?[\d.]+)$/);
    if (m) return { lat: +m[1], lon: +m[2] };
  }
  if (isMac) {
    const out = await run('osascript', ['-l', 'JavaScript', '-e', `ObjC.import('CoreLocation');
var m = $.CLLocationManager.alloc.init; m.requestWhenInUseAuthorization; m.startUpdatingLocation;
var res = ''; for (var i = 0; i < 40; i++) { $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.2));
var l = m.location; if (l && !l.isNil()) { res = l.coordinate.latitude + ',' + l.coordinate.longitude; break; } } res;`], { timeout: 12000 });
    const m = out.trim().match(/^(-?[\d.]+),(-?[\d.]+)$/);
    if (m) return { lat: +m[1], lon: +m[2] };
  }
  return null;
}

// ---------- IPC ----------
ipcMain.on('open-app', (e, name) => { try { e.returnValue = openApp(name); } catch { e.returnValue = false; } });
ipcMain.on('media', (_e, cmd) => media(cmd));
ipcMain.on('window', () => toPanel('island', 'collapse'));
ipcMain.on('show', () => showPanel());

ipcMain.handle('get-settings', () => {
  const d = screen.getPrimaryDisplay();
  return { ...settings, platform: process.platform, notch: isMac && d.workArea.y - d.bounds.y > 30 };
});
ipcMain.handle('set-setting', (_e, k, v) => setSetting(k, v));
ipcMain.handle('model-url', () => 'app://sparrow/model/model.tar.gz');
ipcMain.handle('play-song', (_e, q, where) => playSong(q, where));
ipcMain.handle('find-files', (_e, q) => findFiles(q));
ipcMain.handle('recent-files', (_e, d) => recentFiles(d));
ipcMain.handle('open-path', (_e, p, reveal) => reveal ? shell.showItemInFolder(p) : shell.openPath(p));
ipcMain.handle('tidy-downloads', (_e, apply) => tidyDownloads(apply));
ipcMain.handle('clips', (_e, action, text) => {
  if (action === 'copy') { clipboard.writeText(text); lastClip = text; return true; }
  if (action === 'clear') { clips = []; try { fs.writeFileSync(dataFile('clipboard.json'), '[]'); } catch {} return []; }
  return clips;
});
ipcMain.handle('pick-folder', async () => { const r = await dialog.showOpenDialog(panel, { properties: ['openDirectory'] }); return r.canceled ? null : r.filePaths[0]; });
ipcMain.handle('watch', (_e, action, dir) => {
  if (action === 'add' && dir) { settings.watch = [...new Set([...(settings.watch || []), dir])]; startWatch(dir); }
  if (action === 'remove') { settings.watch = (settings.watch || []).filter(d => d !== dir); stopWatch(dir); }
  saveSettings(); return settings.watch;
});
ipcMain.handle('ollama', (_e, kind, body) => ollama(kind, body));
ipcMain.handle('mail', (_e, kind, text) => mail(kind, text));
ipcMain.handle('location', () => location());
// AI requests go out from here (no browser CORS limits). Only known AI services are allowed.
const AI_HOSTS = ['api.groq.com', 'openrouter.ai', 'generativelanguage.googleapis.com', 'api.openai.com', 'api.anthropic.com',
  'api.x.ai', 'api.deepseek.com', 'api.mistral.ai', 'api.perplexity.ai'];
ipcMain.handle('http', async (_e, url, headers, body) => {
  const u = new URL(url);
  if (u.protocol !== 'https:' || !AI_HOSTS.includes(u.hostname)) return { status: 400, text: JSON.stringify({ error: { message: 'Blocked host' } }) };
  try {
    const r = await net.fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body });
    return { status: r.status, text: await r.text() };
  } catch (e) { return { status: 0, text: JSON.stringify({ error: { message: 'No internet: ' + e.message } }) }; }
});
ipcMain.handle('save-file', async (_e, name, base64) => {
  const r = await dialog.showSaveDialog(panel, { defaultPath: path.join(app.getPath('documents'), name) });
  if (r.canceled || !r.filePath) return null;
  fs.writeFileSync(r.filePath, Buffer.from(base64, 'base64'));
  shell.showItemInFolder(r.filePath);
  return r.filePath;
});

// ---------- start ----------
app.whenReady().then(async () => {
  loadSettings(); loadClips(); serveApp();
  if (isMac && app.dock) app.dock.hide();     // lives in the menu bar
  const allow = ['media', 'notifications', 'geolocation', 'clipboard-read', 'clipboard-sanitized-write'];
  session.defaultSession.setPermissionRequestHandler((_wc, perm, cb) => cb(allow.includes(perm)));
  session.defaultSession.setPermissionCheckHandler((_wc, perm) => allow.includes(perm));
  if (settings.firstRun) {
    settings.firstRun = false; saveSettings();
    app.setLoginItemSettings({ openAtLogin: settings.login, openAsHidden: true, args: ['--hidden'] });
  }
  if (isMac) { try { await systemPreferences.askForMediaAccess('microphone'); } catch {} }
  createPanel(); createTray(); loadApps();
  if (settings.clipboard) startClipboard();
  (settings.watch || []).forEach(startWatch);
  const hidden = process.argv.includes('--hidden') || app.getLoginItemSettings().wasOpenedAtLogin;
  if (!hidden) panel.webContents.once('did-finish-load', () => setTimeout(showPanel, 1600));
  globalShortcut.register('CommandOrControl+Shift+Space', togglePanel);
  screen.on('display-metrics-changed', () => panel && panel.setBounds(islandBounds()));
});
app.on('before-quit', () => { quitting = true; });
app.on('will-quit', () => globalShortcut.unregisterAll());
app.on('window-all-closed', e => e.preventDefault());
app.on('activate', () => showPanel());
