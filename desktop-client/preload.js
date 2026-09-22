const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("tt", {
  state: () => ipcRenderer.invoke("state"),
  login: (email, password) => ipcRenderer.invoke("login", { email, password }),
  register: (email, password) => ipcRenderer.invoke("register", { email, password }),
  verify: (email, code) => ipcRenderer.invoke("verify", { email, code }),
  resend: (email) => ipcRenderer.invoke("resend", { email }),
  clock: (on) => ipcRenderer.invoke("clock", on),
  logout: () => ipcRenderer.invoke("logout"),
  openWebsite: () => ipcRenderer.invoke("openWebsite"),
  openLog: () => ipcRenderer.invoke("openLog"),
  onState: (fn) => ipcRenderer.on("state", (_e, s) => fn(s)),
});
