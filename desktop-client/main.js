// TimeTracker desktop client (Windows / Linux / macOS) — Electron.
//
// Mirrors the native macOS app: clock in/out, activity every minute, a screenshot
// every 10 minutes, foreground app tracking, idle warnings that pause the timer, and
// best-effort sync to the same API the website reads from.

const { app, BrowserWindow, Tray, Menu, ipcMain, powerMonitor, desktopCapturer, screen,
        dialog, nativeImage, shell, Notification } = require("electron");
const path = require("path");
const fs = require("fs");
const { execFile } = require("child_process");

// Windows: en riktig, ren install av TimeTracker-Setup.exe gav ett helt SVART fönster —
// ready-to-show sköt igång, men renderer/index.html målades aldrig upp, bara BrowserWindows
// egen backgroundColor syntes. Klassiskt tecken på att Electrons GPU-process/kompositor
// faller på det här Windows-läget (vanligt på vissa grafikdrivrutiner, i RDP/VM). Programvaru-
// rendering löser det på bekostnad av lite GPU-prestanda, obetydligt för en 420×620-popup.
// Måste sättas FÖRE app.whenReady(). Verifierat 2026-09-23: svart fönster -> riktig UI efter
// den här raden, på samma installation.
if (process.platform === "win32") app.disableHardwareAcceleration();

const API = "https://timetracker-api.elliot-897.workers.dev";
const WEBSITE = "https://timetracker-web.elliot-897.workers.dev";
const SCREENSHOT_EVERY_MIN = 10;   // one screenshot per N minutes (first minute always)
const IDLE_THRESHOLD_SEC = 60;     // no input for this long → warning, timer paused
const SHOT_WIDTH = 1280, SHOT_QUALITY = 40;

// ---------- persistence ----------
const dataDir = () => app.getPath("userData");
const fileIn = (name) => path.join(dataDir(), name);
const readJSON = (name, fallback) => { try { return JSON.parse(fs.readFileSync(fileIn(name), "utf8")); } catch { return fallback; } };
const writeJSON = (name, value) => { fs.mkdirSync(dataDir(), { recursive: true }); fs.writeFileSync(fileIn(name), JSON.stringify(value, null, 2)); };
const log = (msg) => { const line = `${new Date().toISOString()} ${msg}\n`; try { fs.appendFileSync(fileIn("tracker.log"), line); } catch {} console.log(line.trim()); };

let session = readJSON("session.json", null);   // { token, user }
let shifts  = readJSON("shifts.json", []);      // [{ id, start, end }]
let queue   = readJSON("queue.json", []);       // failed API calls to retry

// ---------- API ----------
async function api(pathname, { method = "GET", body, raw, retryable = false } = {}) {
  const headers = {};
  if (session && session.token) headers.Authorization = "Bearer " + session.token;
  if (!raw) headers["Content-Type"] = "application/json";
  try {
    const res = await fetch(API + pathname, { method, headers, body: raw ? body : (body !== undefined ? JSON.stringify(body) : undefined) });
    const data = await res.json().catch(() => ({}));
    if (res.status === 401 && session) { log("Session expired"); session = null; writeJSON("session.json", null); broadcast(); }
    if (!res.ok) throw new Error(data.error || `Server error (${res.status})`);
    return data;
  } catch (e) {
    if (retryable && !raw) { queue.push({ pathname, method, body }); writeJSON("queue.json", queue); }
    throw e;
  }
}
async function drainQueue() {
  if (!queue.length || !session) return;
  const pending = queue; queue = []; writeJSON("queue.json", queue);
  for (const item of pending) { try { await api(item.pathname, { ...item, retryable: true }); } catch {} }
}
setInterval(drainQueue, 60000);

// ---------- helpers ----------
const pad = (n) => String(n).padStart(2, "0");
const dayKey = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const stamp = (d) => `${dayKey(d)}_${pad(d.getHours())}-${pad(d.getMinutes())}-${pad(d.getSeconds())}`;
const uuid = () => require("crypto").randomUUID();
const activeShift = () => shifts.find((s) => !s.end);
const todaySeconds = () => {
  const today = dayKey(new Date());
  return shifts.filter((s) => s.start.slice(0, 10) === today || (s.start.slice(0, 10) < today && !s.end))
    .reduce((sum, s) => sum + ((s.end ? new Date(s.end) : new Date()) - new Date(s.start)) / 1000, 0);
};

// ---------- foreground app (no native modules: PowerShell / xdotool / osascript) ----------
function foregroundApp() {
  return new Promise((resolve) => {
    const done = (name, title) => resolve(name ? { name, title: title || null } : null);
    const run = (cmd, args, parse) => execFile(cmd, args, { timeout: 4000, windowsHide: true }, (err, out) => {
      if (err) return resolve(null); try { parse(String(out).trim()); } catch { resolve(null); } });
    if (process.platform === "win32") {
      const ps = `Add-Type @"
using System;using System.Runtime.InteropServices;using System.Text;
public class FG{[DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")]public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
[DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);}
"@
$h=[FG]::GetForegroundWindow();$sb=New-Object System.Text.StringBuilder 512;[void][FG]::GetWindowText($h,$sb,512);$pid2=0;[void][FG]::GetWindowThreadProcessId($h,[ref]$pid2)
$p=Get-Process -Id $pid2 -ErrorAction SilentlyContinue;$n=if($p){if($p.MainModule){$p.MainModule.FileVersionInfo.FileDescription}else{$p.ProcessName}};if(-not $n){$n=$p.ProcessName}
Write-Output ($n + "|" + $sb.ToString())`;
      run("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", ps], (out) => { const i = out.indexOf("|"); done(out.slice(0, i), out.slice(i + 1)); });
    } else if (process.platform === "darwin") {
      run("osascript", ["-e", 'tell application "System Events" to set p to first process whose frontmost is true\ntell application "System Events" to set t to ""\ntry\ntell application "System Events" to set t to name of front window of p\nend try\nreturn (name of p) & "|" & t'],
        (out) => { const i = out.indexOf("|"); done(out.slice(0, i), out.slice(i + 1)); });
    } else {
      run("sh", ["-c", "w=$(xdotool getactivewindow) && p=$(xdotool getwindowpid $w) && echo \"$(cat /proc/$p/comm)|$(xdotool getwindowname $w)\""],
        (out) => { const i = out.indexOf("|"); done(out.slice(0, i), out.slice(i + 1)); });
    }
  });
}

// ---------- tracker ----------
const tracker = {
  running: false, ticks: 0, samples: [], apps: {}, currentApp: null, rolling: [],
  timers: [],
  start() {
    if (this.running) return;
    this.running = true; this.ticks = 0; this.samples = []; this.apps = {}; this.rolling = [];
    this.timers.push(setInterval(() => this.sample(), 1000));
    this.timers.push(setInterval(() => this.sampleApp(), 5000));
    this.timers.push(setInterval(() => this.closeMinute(this.ticks % SCREENSHOT_EVERY_MIN === 0), 60000));
    this.sampleApp();
    this.closeMinute(true);   // the first minute of a shift always gets a screenshot
    log("Tracker started");
  },
  stop() {
    this.timers.forEach(clearInterval); this.timers = []; this.running = false;
    log("Tracker stopped");
  },
  // One sample per second: was there any input in the last second?
  sample() {
    const idle = powerMonitor.getSystemIdleTime();
    const active = idle < 1;
    this.samples.push(active);
    this.rolling.push(active); if (this.rolling.length > 60) this.rolling.shift();
    if (idle >= IDLE_THRESHOLD_SEC) idleWarning.trigger(idle);
    broadcast();
  },
  async sampleApp() {
    const fg = await foregroundApp();
    if (!fg || !fg.name) return;
    this.currentApp = fg.name;
    const a = (this.apps[fg.name] = this.apps[fg.name] || { name: fg.name, seconds: 0, title: null });
    a.seconds += 5; a.title = fg.title;
  },
  liveActivity() { return this.rolling.length ? Math.round(this.rolling.filter(Boolean).length * 100 / this.rolling.length) : 0; },
  async closeMinute(withScreenshot) {
    this.ticks++;
    const samples = this.samples; this.samples = [];
    const apps = Object.values(this.apps).sort((a, b) => b.seconds - a.seconds); this.apps = {};
    const seconds = samples.length;
    const overall = seconds ? Math.round(samples.filter(Boolean).length * 100 / seconds) : 0;
    const now = new Date();
    let keys = [];
    if (withScreenshot) {
      const file = await captureScreenshot(now);
      if (file) keys = [file.key];
    }
    const record = { ts: now.toISOString(), keyboard: overall, mouse: overall, overall, apps, screenshots: keys };
    log(`Minute: ${overall}% over ${seconds}s · ${apps[0] ? apps[0].name : "no app"}${keys.length ? " · screenshot" : ""}`);
    api("/api/minutes", { method: "POST", body: [record], retryable: true }).catch((e) => log("Sync minute failed: " + e.message));
  },
};

// Captures the display under the cursor as a small JPEG, saves it locally and uploads it.
// Returns { key, path } where key is "<day>/<file>.jpg" (the server prefixes the user id).
async function captureScreenshot(now) {
  try {
    const cursor = screen.getCursorScreenPoint();
    const display = screen.getDisplayNearestPoint(cursor);
    const scale = display.scaleFactor || 1;
    const sources = await desktopCapturer.getSources({ types: ["screen"],
      thumbnailSize: { width: Math.round(display.size.width * scale), height: Math.round(display.size.height * scale) } });
    if (!sources.length) return null;
    const src = sources.find((s) => String(s.display_id) === String(display.id)) || sources[0];
    let img = src.thumbnail;
    if (img.isEmpty()) return null;
    if (img.getSize().width > SHOT_WIDTH) img = img.resize({ width: SHOT_WIDTH });
    const jpeg = img.toJPEG(SHOT_QUALITY);
    const day = dayKey(now), file = `${stamp(now)}.jpg`;
    const dir = path.join(dataDir(), "screenshots", day); fs.mkdirSync(dir, { recursive: true });
    const full = path.join(dir, file); fs.writeFileSync(full, jpeg);
    const key = `${day}/${file}`;
    api(`/api/upload?key=${encodeURIComponent(key)}`, { method: "POST", raw: true, body: jpeg })
      .catch((e) => log("Upload failed: " + e.message));
    return { key, path: full };
  } catch (e) { log("Screenshot failed: " + e.message); return null; }
}

// ---------- shifts ----------
function pushShifts() { api("/api/shifts", { method: "POST", body: shifts.map((s) => ({ id: s.id, start: s.start, end: s.end || undefined })), retryable: true }).catch(() => {}); }
function clockIn() {
  if (activeShift() || !session) return;
  shifts.push({ id: uuid(), start: new Date().toISOString(), end: null });
  writeJSON("shifts.json", shifts); pushShifts(); tracker.start(); broadcast(); updateTray();
}
function clockOut(at = new Date()) {
  const s = activeShift(); if (!s) return;
  s.end = at.toISOString();
  writeJSON("shifts.json", shifts); pushShifts(); tracker.stop(); broadcast(); updateTray();
}

// ---------- idle warning ----------
const idleWarning = {
  showing: false,
  async trigger(idleSeconds) {
    if (this.showing || !activeShift()) return;
    this.showing = true;
    const shift = activeShift();
    let since = new Date(Date.now() - idleSeconds * 1000);
    if (since < new Date(shift.start)) since = new Date(shift.start);
    clockOut(since);   // pause where input stopped so the idle stretch is never counted
    log("Idle: timer paused at " + since.toISOString());
    const shot = await captureScreenshot(new Date());
    const warning = { id: uuid(), startedAt: since.toISOString(), activity: 0, app: tracker.currentApp, screenshot: shot ? shot.key : undefined };
    api("/api/warnings", { method: "POST", body: warning, retryable: true }).catch(() => {});
    showWindow();
    const { response } = await dialog.showMessageBox(win, {
      type: "warning", title: "You have been idle",
      message: "You have been idle",
      detail: `No activity since ${pad(since.getHours())}:${pad(since.getMinutes())}.\n\nThe timer is paused and this time is NOT counted as worked. A warning has been recorded and is visible to your admin.\n\nGet back to work to restart the timer, or clock out.`,
      buttons: ["Back to work", "Clock out"], defaultId: 0, cancelId: 1, noLink: true,
    });
    const resumed = response === 0;
    api("/api/warnings", { method: "POST", body: { ...warning, resolvedAt: new Date().toISOString(), outcome: resumed ? "resumed" : "clockedOut" }, retryable: true }).catch(() => {});
    if (resumed) clockIn();
    this.showing = false;
  },
};

// ---------- window & tray ----------
let win = null, tray = null;
const iconPath = path.join(__dirname, "assets", "icon.png");

function createWindow() {
  win = new BrowserWindow({
    width: 420, height: 620, resizable: false, show: false, title: "TimeTracker",
    icon: iconPath, backgroundColor: "#05060c", autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, "preload.js"), contextIsolation: true, nodeIntegration: false },
  });
  win.loadFile(path.join(__dirname, "renderer", "index.html"));
  win.once("ready-to-show", () => win.show());
  // Closing hides to the tray while a shift is running; quit from the tray menu.
  win.on("close", (e) => { if (!app.isQuitting && activeShift()) { e.preventDefault(); win.hide(); } });
}
function showWindow() { if (!win) createWindow(); win.show(); win.focus(); }

function updateTray() {
  if (!tray) {
    tray = new Tray(nativeImage.createFromPath(iconPath).resize({ width: 18, height: 18 }));
    tray.on("click", showWindow);
  }
  const on = !!activeShift();
  tray.setToolTip(on ? "TimeTracker — tracking" : "TimeTracker — clocked out");
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: on ? "Clock out" : "Clock in", enabled: !!session, click: () => (on ? clockOut() : clockIn()) },
    { label: "Open TimeTracker", click: showWindow },
    { label: "Take screenshot now", enabled: on, click: () => captureScreenshot(new Date()) },
    { label: "Open dashboard (web)", click: () => shell.openExternal(WEBSITE) },
    { type: "separator" },
    { label: "Log out", enabled: !!session, click: logout },
    { label: "Quit", click: () => { app.isQuitting = true; if (activeShift()) clockOut(); app.quit(); } },
  ]));
}

function snapshot() {
  const s = activeShift();
  return { loggedIn: !!session, user: session ? session.user : null, clockedIn: !!s, since: s ? s.start : null,
    todaySeconds: todaySeconds(), activity: tracker.running ? tracker.liveActivity() : null, app: tracker.currentApp,
    platform: process.platform, version: app.getVersion() };
}
function broadcast() { if (win && !win.isDestroyed()) win.webContents.send("state", snapshot()); }

async function logout() {
  if (activeShift()) clockOut();
  try { await api("/api/logout", { method: "POST" }); } catch {}
  session = null; writeJSON("session.json", null); broadcast(); updateTray();
}

// ---------- IPC ----------
ipcMain.handle("state", () => snapshot());
ipcMain.handle("login", async (_e, { email, password }) => {
  const r = await api("/api/login", { method: "POST", body: { email, password } });
  session = { token: r.token, user: r.user }; writeJSON("session.json", session);
  drainQueue(); updateTray(); broadcast(); return snapshot();
});
ipcMain.handle("register", async (_e, { email, password }) => api("/api/register", { method: "POST", body: { email, password } }));
ipcMain.handle("verify", async (_e, { email, code }) => {
  const r = await api("/api/verify", { method: "POST", body: { email, code } });
  session = { token: r.token, user: r.user }; writeJSON("session.json", session);
  updateTray(); broadcast(); return snapshot();
});
ipcMain.handle("resend", async (_e, { email }) => api("/api/resend-code", { method: "POST", body: { email } }));
ipcMain.handle("clock", async (_e, on) => { on ? clockIn() : clockOut(); return snapshot(); });
ipcMain.handle("logout", async () => { await logout(); return snapshot(); });
ipcMain.handle("openWebsite", () => shell.openExternal(WEBSITE));
ipcMain.handle("openLog", () => shell.openPath(dataDir()));

// ---------- lifecycle ----------
const single = app.requestSingleInstanceLock();
if (!single) app.quit();
app.on("second-instance", showWindow);

app.whenReady().then(() => {
  createWindow(); updateTray();
  // Resume a shift that was open when the app last quit.
  if (session && activeShift()) tracker.start();
  if (session) drainQueue();
  powerMonitor.on("suspend", () => { if (activeShift()) { log("System sleeping: clocking out"); clockOut(); } });
  powerMonitor.on("lock-screen", () => { if (activeShift()) { log("Screen locked: clocking out"); clockOut(); } });
  app.on("activate", showWindow);
});
app.on("window-all-closed", () => { /* keep running in the tray */ });
app.on("before-quit", () => { app.isQuitting = true; });
