// Safe bridge between the Sparrow web app and the computer (Mac / Windows).
const { contextBridge, ipcRenderer } = require('electron');
const inv = (...a) => ipcRenderer.invoke(...a);

contextBridge.exposeInMainWorld('SparrowDesktop', {
  platform: () => process.platform === 'darwin' ? 'mac' : process.platform === 'win32' ? 'windows' : 'linux',
  openApp: name => ipcRenderer.sendSync('open-app', name),
  media: cmd => ipcRenderer.send('media', cmd),
  httpGet: url => ipcRenderer.invoke('http-get', url),
  typeText: text => ipcRenderer.invoke('type-text', text),
  window: what => ipcRenderer.send('window', what),
  show: () => ipcRenderer.send('show'),
  state: () => {},
  getSettings: () => inv('get-settings'),
  resetSettings: () => inv('reset-settings'),
  setSetting: (k, v) => inv('set-setting', k, v),
  modelUrl: () => inv('model-url'),
  playSong: (q, where) => inv('play-song', q, where),
  findFiles: q => inv('find-files', q),
  recentFiles: d => inv('recent-files', d),
  openPath: (p, reveal) => inv('open-path', p, reveal),
  tidyDownloads: apply => inv('tidy-downloads', apply),
  clips: (action, text) => inv('clips', action, text),
  pickFolder: () => inv('pick-folder'),
  watch: (action, dir) => inv('watch', action, dir),
  ollama: (kind, body) => inv('ollama', kind, body),
  sysinfo: () => inv('sysinfo'),
  mail: (kind, text) => inv('mail', kind, text),
  location: () => inv('location'),
  http: (url, headers, body) => inv('http', url, headers, body),
  saveFile: (name, base64) => inv('save-file', name, base64),
  openBusiness: tab => ipcRenderer.send('open-business', tab),
  openWindows: () => inv('open-windows'),
  focusWindow: pid => ipcRenderer.send('focus-window', pid),
  askIsland: text => ipcRenderer.send('ask-island', text),
  // Zuffi walking on the desktop
  pet: (kind, data) => ipcRenderer.send('pet', kind, data || {}),
  petMouse: inside => ipcRenderer.send('pet-mouse', inside),
  petAction: a => ipcRenderer.send('pet-action', a),
  petNext: () => inv('pet-next'),
  onPet: f => ipcRenderer.on('pet', (_e, v) => f(v)),
  onCommand: f => ipcRenderer.on('command', (_e, c) => f(c)),
  onEvent: f => ipcRenderer.on('event', (_e, ev) => f(ev)),
  // Mac speech engine (Apple): listening + natural voices
  nativeVoice: {
    available: () => ipcRenderer.sendSync('nv-available'),
    send: o => ipcRenderer.sendSync('nv', o),
    on: f => ipcRenderer.on('nv-ev', (_e, ev) => f(ev)),
  },
  // the island
  onIsland: f => ipcRenderer.on('island', (_e, v) => f(v)),
  islandState: st => ipcRenderer.send('island-state', st),
  mouseInside: inside => ipcRenderer.send('mouse-inside', inside),
});
