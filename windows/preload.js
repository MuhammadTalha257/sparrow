// Safe bridge between the Sparrow web app and Windows.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('SparrowDesktop', {
  platform: () => 'windows',
  openApp: name => ipcRenderer.sendSync('open-app', name),
  media: cmd => ipcRenderer.send('media', cmd),
  window: what => ipcRenderer.send('window', what),
  show: () => ipcRenderer.send('show'),
  state: s => ipcRenderer.send('state', s),
  getSettings: () => ipcRenderer.invoke('get-settings'),
  setSetting: (k, v) => ipcRenderer.invoke('set-setting', k, v),
  modelUrl: () => ipcRenderer.invoke('model-url'),
  onCommand: f => ipcRenderer.on('command', (_e, c) => f(c)),
  // used by the little top bar
  onState: f => ipcRenderer.on('state', (_e, s) => f(s)),
  pillClick: () => ipcRenderer.send('pill-click'),
  pillTalk: () => ipcRenderer.send('pill-talk'),
});
