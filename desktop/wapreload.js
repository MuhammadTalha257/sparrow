// Runs in Zuffi's own WhatsApp Web window: gives the page one way to tell Zuffi about new messages.
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('zuffiWAPost', m => { try { ipcRenderer.send('wa-ev', JSON.parse(JSON.stringify(m))); } catch {} });
