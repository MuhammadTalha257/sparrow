// Sparrow for Windows — a small panel + a little bar at the top of the screen.
// It keeps running in the tray so reminders, the morning briefing and the
// evening check-in happen even when the window is closed.
const { app, BrowserWindow, Tray, Menu, ipcMain, shell, screen, globalShortcut, protocol, net, nativeImage, session } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn, execFile } = require('child_process');
const { pathToFileURL } = require('url');

const isWin = process.platform === 'win32';
const WWW = path.join(__dirname, 'www');
const MODEL = app.isPackaged ? path.join(process.resourcesPath, 'model') : path.join(__dirname, 'model');
const settingsFile = () => path.join(app.getPath('userData'), 'sparrow-settings.json');

let panel = null, pill = null, tray = null, quitting = false;
let settings = { login: true, pill: true, firstRun: true };

function loadSettings() {
  try { settings = Object.assign(settings, JSON.parse(fs.readFileSync(settingsFile(), 'utf8'))); } catch {}
}
function saveSettings() {
  try { fs.writeFileSync(settingsFile(), JSON.stringify(settings)); } catch {}
}

if (!app.requestSingleInstanceLock()) { app.quit(); }
app.on('second-instance', () => showPanel());
app.setAppUserModelId('app.sparrowai.sparrow');

// Serve the app from app://sparrow/ so modules, fetch and the voice model all work offline.
protocol.registerSchemesAsPrivileged([{ scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true, corsEnabled: true } }]);

function serveApp() {
  protocol.handle('app', req => {
    const u = new URL(req.url);
    let p = decodeURIComponent(u.pathname);
    let base = WWW;
    if (p.startsWith('/model/')) { base = MODEL; p = p.slice('/model'.length); }
    const file = path.normalize(path.join(base, p === '/' ? '/index.html' : p));
    if (!file.startsWith(base)) return new Response('no', { status: 403 });
    return net.fetch(pathToFileURL(file).toString());
  });
}

// ---------- windows ----------
function panelBounds() {
  const wa = screen.getPrimaryDisplay().workArea;
  const w = 420, h = Math.min(760, wa.height - 80);
  return { width: w, height: h, x: Math.round(wa.x + (wa.width - w) / 2), y: wa.y + (settings.pill ? 64 : 12) };
}

function createPanel() {
  panel = new BrowserWindow({
    ...panelBounds(), show: false, frame: false, resizable: true, minWidth: 360, minHeight: 480,
    backgroundColor: '#140D09', title: 'Sparrow', icon: path.join(WWW, 'icons', 'icon-512.png'),
    alwaysOnTop: true, skipTaskbar: false, roundedCorners: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false,
      backgroundThrottling: false, autoplayPolicy: 'no-user-gesture-required', spellcheck: false,
    },
  });
  panel.loadURL('app://sparrow/index.html');
  panel.on('close', e => { if (!quitting) { e.preventDefault(); panel.hide(); } });
  panel.on('blur', () => { /* stays open until hidden, like a notepad */ });
  // Links open in the normal browser; tel:/mailto:/app links go to Windows.
  panel.webContents.setWindowOpenHandler(({ url }) => { shell.openExternal(url); return { action: 'deny' }; });
  panel.webContents.on('will-navigate', (e, url) => { if (!url.startsWith('app://')) { e.preventDefault(); shell.openExternal(url); } });
}

function createPill() {
  const wa = screen.getPrimaryDisplay().workArea;
  const w = 340, h = 52;
  pill = new BrowserWindow({
    width: w, height: h, x: Math.round(wa.x + (wa.width - w) / 2), y: wa.y + 6,
    frame: false, transparent: true, resizable: false, movable: true, skipTaskbar: true, alwaysOnTop: true,
    focusable: false, hasShadow: false, show: false,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true },
  });
  pill.setAlwaysOnTop(true, 'screen-saver');
  pill.setVisibleOnAllWorkspaces(true);
  pill.loadFile(path.join(__dirname, 'pill.html'));
  pill.once('ready-to-show', () => { if (settings.pill) pill.showInactive(); });
}

function showPanel() {
  if (!panel) return;
  if (panel.isMinimized()) panel.restore();
  panel.show(); panel.focus();
}
function togglePanel() { panel && panel.isVisible() && panel.isFocused() ? panel.hide() : showPanel(); }

// ---------- tray ----------
function createTray() {
  const img = nativeImage.createFromPath(path.join(WWW, 'icons', 'icon-192.png')).resize({ width: 16, height: 16 });
  tray = new Tray(img);
  tray.setToolTip('Sparrow');
  const menu = () => Menu.buildFromTemplate([
    { label: 'Open Sparrow', accelerator: 'Ctrl+Shift+Space', click: showPanel },
    { label: 'Talk to Sparrow', click: () => { showPanel(); panel.webContents.send('command', 'listen'); } },
    { type: 'separator' },
    { label: 'Show the sparrow bar', type: 'checkbox', checked: settings.pill, click: i => setSetting('pill', i.checked) },
    { label: 'Start with Windows', type: 'checkbox', checked: settings.login, click: i => setSetting('login', i.checked) },
    { type: 'separator' },
    { label: 'Quit Sparrow', click: () => { quitting = true; app.quit(); } },
  ]);
  tray.setContextMenu(menu());
  tray.on('click', togglePanel);
  tray.refresh = () => tray.setContextMenu(menu());
}

function setSetting(k, v) {
  settings[k] = v; saveSettings();
  if (k === 'login') app.setLoginItemSettings({ openAtLogin: v, args: ['--hidden'] });
  if (k === 'pill' && pill) { v ? pill.showInactive() : pill.hide(); panel && panel.setBounds(panelBounds()); }
  tray && tray.refresh && tray.refresh();
}

// ---------- opening apps ----------
const KNOWN = {
  chrome: 'chrome', 'google chrome': 'chrome', edge: 'msedge', 'microsoft edge': 'msedge', firefox: 'firefox',
  notepad: 'notepad', calculator: 'calc', calc: 'calc', paint: 'mspaint', 'task manager': 'taskmgr',
  explorer: 'explorer', 'file explorer': 'explorer', files: 'explorer', 'my files': 'explorer',
  cmd: 'cmd', 'command prompt': 'cmd', terminal: 'wt', powershell: 'powershell', 'control panel': 'control',
  word: 'winword', excel: 'excel', powerpoint: 'powerpnt', outlook: 'outlook', 'vs code': 'code', vscode: 'code', 'visual studio code': 'code',
  settings: 'ms-settings:', 'windows settings': 'ms-settings:', 'wifi settings': 'ms-settings:network-wifi', 'bluetooth': 'ms-settings:bluetooth',
  spotify: 'spotify:', whatsapp: 'whatsapp:', teams: 'msteams:', 'microsoft teams': 'msteams:', camera: 'microsoft.windows.camera:',
  store: 'ms-windows-store:', 'microsoft store': 'ms-windows-store:', photos: 'ms-photos:', clock: 'ms-clock:', alarms: 'ms-clock:',
  mail: 'outlookmail:', calendar: 'outlookcal:', maps: 'bingmaps:', weather: 'msnweather:', 'snipping tool': 'ms-screenclip:',
};
const FOLDERS = { downloads: 'downloads', documents: 'documents', desktop: 'desktop', pictures: 'pictures', music: 'music', videos: 'videos', home: 'home' };
let startApps = [];     // [{ name, id }] from Windows' Start menu (includes Store apps)

function loadStartApps() {
  if (!isWin) return;
  execFile('powershell.exe', ['-NoProfile', '-Command', 'Get-StartApps | ConvertTo-Json -Compress'], { windowsHide: true, maxBuffer: 8e6 }, (err, out) => {
    if (err) return;
    try { startApps = [].concat(JSON.parse(out)).map(a => ({ name: String(a.Name), id: String(a.AppID) })); } catch {}
  });
}
const norm = s => s.toLowerCase().replace(/[^a-z0-9 ]/g, '').replace(/\s+/g, ' ').trim();

function openApp(raw) {
  const name = norm(String(raw).replace(/^(the|my)\s+/i, '').replace(/\s+(app|application|folder|program)$/i, ''));
  if (!name) return false;
  if (FOLDERS[name] || FOLDERS[name.replace(/ folder$/, '')]) {
    shell.openPath(app.getPath(FOLDERS[name] || FOLDERS[name.replace(/ folder$/, '')])); return true;
  }
  // Installed apps first (exact, then starts-with, then contains)
  const hit = startApps.find(a => norm(a.name) === name)
    || startApps.find(a => norm(a.name).startsWith(name))
    || (name.length > 3 && startApps.find(a => norm(a.name).includes(name)));
  if (hit) { spawn('explorer.exe', [`shell:AppsFolder\\${hit.id}`], { detached: true, windowsHide: true }).unref(); return true; }
  const k = KNOWN[name];
  if (k) {
    if (k.includes(':')) shell.openExternal(k);
    else spawn('cmd.exe', ['/c', 'start', '""', k], { detached: true, windowsHide: true }).unref();
    return true;
  }
  return false;
}

// ---------- media keys & volume ----------
const VK = { playpause: 179, next: 176, prev: 177, volup: 175, voldown: 174, mute: 173 };
function media(cmd) {
  if (!isWin) return;
  const ps = (script) => spawn('powershell.exe', ['-NoProfile', '-Command', script], { windowsHide: true, detached: true }).unref();
  if (cmd === 'lock') { spawn('rundll32.exe', ['user32.dll,LockWorkStation'], { detached: true }).unref(); return; }
  if (cmd.startsWith('vol:')) {
    // 50 steps of 2% each: mute-to-zero, then step up
    const n = Math.round(+cmd.slice(4) / 2);
    ps(`$w=New-Object -ComObject WScript.Shell; 1..50|%{$w.SendKeys([char]174)}; 1..${n}|%{$w.SendKeys([char]175)}`);
    return;
  }
  const code = VK[cmd]; if (!code) return;
  const times = cmd === 'volup' || cmd === 'voldown' ? 5 : 1;
  ps(`$w=New-Object -ComObject WScript.Shell; 1..${times}|%{$w.SendKeys([char]${code})}`);
}

// ---------- IPC ----------
ipcMain.on('open-app', (e, name) => { try { e.returnValue = openApp(name); } catch { e.returnValue = false; } });
ipcMain.on('media', (_e, cmd) => media(cmd));
ipcMain.on('window', (_e, what) => { if (what === 'min') panel.minimize(); else panel.hide(); });
ipcMain.on('show', () => showPanel());
ipcMain.on('state', (_e, s) => pill && pill.webContents.send('state', s));
ipcMain.on('pill-click', () => togglePanel());
ipcMain.on('pill-talk', () => { showPanel(); panel.webContents.send('command', 'listen'); });
ipcMain.handle('get-settings', () => settings);
ipcMain.handle('set-setting', (_e, k, v) => setSetting(k, v));
ipcMain.handle('model-url', () => 'app://sparrow/model/model.tar.gz');

// ---------- start ----------
app.whenReady().then(() => {
  loadSettings();
  serveApp();
  session.defaultSession.setPermissionRequestHandler((_wc, perm, cb) => cb(['media', 'notifications', 'geolocation'].includes(perm)));
  session.defaultSession.setPermissionCheckHandler((_wc, perm) => ['media', 'notifications', 'geolocation'].includes(perm));
  if (settings.firstRun) {
    settings.firstRun = false; saveSettings();
    app.setLoginItemSettings({ openAtLogin: settings.login, args: ['--hidden'] });
  }
  createPanel(); createPill(); createTray(); loadStartApps();
  const hidden = process.argv.includes('--hidden') || app.getLoginItemSettings().wasOpenedAtLogin;
  panel.once('ready-to-show', () => { if (!hidden) showPanel(); });
  globalShortcut.register('CommandOrControl+Shift+Space', togglePanel);
  screen.on('display-metrics-changed', () => panel && panel.setBounds(panelBounds()));
});
app.on('before-quit', () => { quitting = true; });
app.on('will-quit', () => globalShortcut.unregisterAll());
app.on('window-all-closed', e => e.preventDefault());
