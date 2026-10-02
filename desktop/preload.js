// Safe bridge between the Sparrow web app and the computer (Mac / Windows).
const { contextBridge, ipcRenderer } = require('electron');
const inv = (...a) => ipcRenderer.invoke(...a);

contextBridge.exposeInMainWorld('SparrowDesktop', {
  platform: () => process.platform === 'darwin' ? 'mac' : process.platform === 'win32' ? 'windows' : 'linux',
  openApp: name => ipcRenderer.sendSync('open-app', name),
  media: cmd => ipcRenderer.send('media', cmd),
  window: what => ipcRenderer.send('window', what),
  show: () => ipcRenderer.send('show'),
  state: s => ipcRenderer.send('state', s),
  getSettings: () => inv('get-settings'),
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
  mail: (kind, text) => inv('mail', kind, text),
  location: () => inv('location'),
  http: (url, headers, body) => inv('http', url, headers, body),
  saveFile: (name, base64) => inv('save-file', name, base64),
  onCommand: f => ipcRenderer.on('command', (_e, c) => f(c)),
  onEvent: f => ipcRenderer.on('event', (_e, ev) => f(ev)),
  // used by the little top bar
  onState: f => ipcRenderer.on('state', (_e, s) => f(s)),
  pillClick: () => ipcRenderer.send('pill-click'),
  pillTalk: () => ipcRenderer.send('pill-talk'),
});
