// Web memory probe: opens the web build in Chromium (Playwright), plays a short
// tour through window.stoneAgeDev and the keyboard, and records after each
// step the wasm heap, IndexedDB usage (the downloaded packs, which IDBFS
// mirrors in MEMFS, i.e. page memory), the JS heap, Web Audio buffers and the browser processes'
// resident memory. Then it reloads the page to show what a second visit
// loads back from IndexedDB. See docs/technical/memory-baseline.md.
//
//   npm install --prefix <scratch> playwright-core
//   node tools/web_memory_probe.mjs --modules <scratch> \
//     --url 'http://127.0.0.1:8790/?server=ws://127.0.0.1:8791' \
//     --chrome ~/Library/Caches/ms-playwright/chromium-<rev>/chrome-mac-arm64/'Google Chrome for Testing.app'/Contents/MacOS/'Google Chrome for Testing' \
//     --out build/memory-probe-web.json
//
// Serve the build and a backend on ports of your own (not the live 8780/8781):
//   python3 tools/serve_web.py --port 8790 --bind 127.0.0.1
//   <godot> --headless --path client --audio-driver Dummy --script res://server/server_main.gd -- --port=8791 --bind=127.0.0.1 --save=/tmp/probe-save.json
import { createRequire } from "node:module";
import { execSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const args = Object.fromEntries(process.argv.slice(2).reduce((pairs, value, index, all) => {
  if (value.startsWith("--")) pairs.push([value.slice(2), all[index + 1]]);
  return pairs;
}, []));
// --modules: the folder playwright-core was installed into (npm --prefix).
const require = createRequire(args.modules ? `${args.modules}/package.json` : import.meta.url);
const { chromium } = require("playwright-core");
const MB = 1048576;
const rows = [];

// Counts every Web Audio buffer the page creates (Godot's web "sample"
// playback decodes whole streams into AudioBuffers) and keeps weak refs to
// tell how many are still alive after a GC.
const audioHook = () => {
  const created = { count: 0, bytes: 0, refs: [] };
  window.__audioBuffers = created;
  const note = (buffer) => {
    created.count += 1;
    created.bytes += buffer.length * buffer.numberOfChannels * 4;
    created.refs.push(new WeakRef(buffer));
    return buffer;
  };
  // The wasm heap: this Emscripten build exports neither FS nor the HEAP
  // views, so keep every WebAssembly.Memory the page creates or instantiates.
  const memories = (window.__wasmMemories = []);
  const keep = (value) => { if (value instanceof WebAssembly.Memory && !memories.includes(value)) memories.push(value); };
  const scan = (result) => {
    const instance = result && (result.instance || result);
    if (instance && instance.exports) for (const value of Object.values(instance.exports)) keep(value);
    return result;
  };
  WebAssembly.Memory = new Proxy(WebAssembly.Memory, { construct(target, a) { const memory = new target(...a); keep(memory); return memory; } });
  for (const name of ["instantiate", "instantiateStreaming"]) {
    const native = WebAssembly[name];
    WebAssembly[name] = function (...a) { return native.apply(this, a).then(scan); };
  }
  // Main-thread tasks over 50 ms: streamed music is mixed on the main thread in
  // this no-threads build, so a task longer than the audio buffer is a gap.
  const tasks = (window.__longTasks = []);
  try {
    new PerformanceObserver((list) => { for (const entry of list.getEntries()) tasks.push(entry.duration); })
      .observe({ type: "longtask", buffered: true });
  } catch (e) { /* not supported */ }
  const original = BaseAudioContext.prototype.createBuffer;
  BaseAudioContext.prototype.createBuffer = function (...a) { return note(original.apply(this, a)); };
  const Native = window.AudioBuffer;
  window.AudioBuffer = new Proxy(Native, { construct(target, a) { return note(new target(...a)); } });
};

const pageStats = async () => {
  const result = { stoneAge: window.stoneAge || null };
  if (window.performance && performance.memory) {
    result.js_used_mb = performance.memory.usedJSHeapSize / 1048576;
    result.js_total_mb = performance.memory.totalJSHeapSize / 1048576;
  }
  result.wasm_heap_mb = (window.__wasmMemories || []).reduce((sum, memory) => sum + memory.buffer.byteLength, 0) / 1048576;
  // IndexedDB holds user:// (the pack cache); IDBFS keeps a full copy of it
  // in MEMFS, which is JS memory of this page.
  if (navigator.storage && navigator.storage.estimate) {
    const estimate = await navigator.storage.estimate();
    result.storage_mb = estimate.usage / 1048576;
  }
  if (window.__audioBuffers) {
    if (window.gc) window.gc();
    const buffers = window.__audioBuffers;
    let aliveBytes = 0;
    let alive = 0;
    for (const ref of buffers.refs) {
      const buffer = ref.deref();
      if (buffer) { alive += 1; aliveBytes += buffer.length * buffer.numberOfChannels * 4; }
    }
    result.audio = { created: buffers.count, created_mb: buffers.bytes / 1048576, alive, alive_mb: aliveBytes / 1048576 };
  }
  if (window.__longTasks) {
    const tasks = window.__longTasks.splice(0);
    result.long_tasks = { over_50ms: tasks.length, over_100ms: tasks.filter((d) => d > 100).length, over_200ms: tasks.filter((d) => d > 200).length, longest_ms: Math.round(Math.max(0, ...tasks)) };
  }
  return result;
};

// Resident size of the browser's processes by role, from outside (ps).
function processStats(rootPid) {
  const table = execSync("ps -axo pid=,ppid=,rss=,command=").toString().trim().split("\n").map((line) => {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/);
    return match && { pid: +match[1], ppid: +match[2], rss: +match[3], command: match[4] };
  }).filter(Boolean);
  // Chrome for Testing is only ever started by this probe (and other tests),
  // so its processes are the browser, renderer, GPU and utility processes.
  const roles = {};
  for (const row of table) {
    if (!row.command.includes("Chrome for Testing") && !row.command.includes(String(rootPid))) continue;
    const role = (row.command.match(/--type=([a-z-]+)/) || [null, "browser"])[1] + (row.command.includes("--utility-sub-type=audio") ? "-audio" : "");
    let footprint = -1;
    try {
      const text = execSync(`footprint -p ${row.pid} 2>/dev/null`).toString();
      const match = text.match(/Footprint:\s+([\d.]+)\s+(KB|MB|GB)/);
      if (match) footprint = +match[1] * { KB: 1 / 1024, MB: 1, GB: 1024 }[match[2]];
    } catch (e) { /* process gone */ }
    const entry = roles[role] || (roles[role] = { processes: 0, rss_mb: 0, footprint_mb: 0, largest_footprint_mb: 0 });
    entry.processes += 1;
    entry.rss_mb += row.rss / 1024;
    entry.footprint_mb += Math.max(footprint, 0);
    // The game's page is the largest renderer; spare and extension renderers are small.
    entry.largest_footprint_mb = Math.max(entry.largest_footprint_mb, footprint);
  }
  return roles;
}

async function sample(page, browserPid, step) {
  const stats = await page.evaluate(pageStats);
  const row = { step, ...stats, processes: processStats(browserPid) };
  rows.push(row);
  const renderer = row.processes.renderer || {};
  const gpu = row.processes["gpu-process"] || {};
  console.log(`[web] ${step} | wasm ${(row.wasm_heap_mb || 0).toFixed(0)} MB | idb ${(row.storage_mb || 0).toFixed(0)} MB | js ${(row.js_used_mb || 0).toFixed(0)} MB | audio alive ${row.audio ? row.audio.alive_mb.toFixed(0) : "?"} MB of ${row.audio ? row.audio.created_mb.toFixed(0) : "?"} | page renderer footprint ${(renderer.largest_footprint_mb || 0).toFixed(0)} MB (all renderers rss ${(renderer.rss_mb || 0).toFixed(0)}) | gpu rss ${(gpu.rss_mb || 0).toFixed(0)} fp ${(gpu.footprint_mb || 0).toFixed(0)} | mounted ${row.stoneAge ? row.stoneAge.mounted : "?"} | long tasks ${JSON.stringify(row.long_tasks || {})}`);
  console.log(`[web]    processes ${JSON.stringify(row.processes)}`);
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function until(page, predicate, timeout = 120000) {
  const limit = Date.now() + timeout;
  while (Date.now() < limit) {
    if (await page.evaluate(predicate).catch(() => false)) return true;
    await wait(500);
  }
  console.log(`[web] timed out waiting for ${predicate}`);
  return false;
}

const settled = "window.stoneAge && !window.stoneAge.waiting_screen && window.stoneAge.pending === 0";
const dev = (page, name) => page.evaluate((action) => window.stoneAgeDev(action), name);

async function battle(page) {
  await dev(page, "encounter");
  await until(page, "window.stoneAge && window.stoneAge.battle && window.stoneAge.pending === 0", 60000);
  await wait(4000);
}

async function leaveBattle(page) {
  await dev(page, "escape");
  await wait(4000);
  await dev(page, "return");
  await until(page, "window.stoneAge && !window.stoneAge.battle", 30000);
  await wait(2000);
}

const browser = await chromium.launch({
  executablePath: args.chrome,
  headless: true,
  args: ["--enable-precise-memory-info", "--js-flags=--expose-gc", "--autoplay-policy=no-user-gesture-required", "--enable-unsafe-swiftshader", "--use-angle=swiftshader", "--ignore-gpu-blocklist"],
});
const browserPid = browser.process ? browser.process().pid : null;
const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
await context.addInitScript(audioHook);
const page = await context.newPage();
page.on("console", (message) => { if (/error|packs\]/i.test(message.text())) console.log(`[page] ${message.text().slice(0, 200)}`); });
const pid = browserPid || +execSync("pgrep -n 'Google Chrome for Testing'").toString().trim();

await page.goto(args.url);
await until(page, settled, 240000);
await page.mouse.click(640, 400);
await wait(3000);
await sample(page, pid, "01 startup: village (first visit, packs downloaded)");
await dev(page, "explore");
await until(page, `window.stoneAge && window.stoneAge.map === 100 && window.stoneAge.pending === 0`, 120000);
await wait(3000);
await sample(page, pid, "02 Samgir wilderness (map 100)");
await battle(page);
await sample(page, pid, "03 battle open");
await leaveBattle(page);
await sample(page, pid, "04 after the battle");
for (let i = 0; i < 3; i++) { await battle(page); await leaveBattle(page); }
await sample(page, pid, "05 after 3 more battles");
await dev(page, "pets");
await wait(3000);
await sample(page, pid, "06 pet window");
await page.keyboard.press("Escape");
await wait(1000);
await page.keyboard.press("b");
await wait(4000);
for (let i = 0; i < 40; i++) { await page.mouse.move(640, 420); await page.mouse.wheel(0, 400); await wait(400); }
await wait(5000);
await sample(page, pid, "07 宠物大全 grid scrolled");
await page.keyboard.press("Escape");
await wait(1000);
await dev(page, "village");
await until(page, `window.stoneAge && window.stoneAge.map === 1000 && window.stoneAge.pending === 0`, 60000);
await wait(3000);
await sample(page, pid, "08 back in the village");
// The radio through 5 tracks, then off: what its tracks cost and whether they go.
for (let i = 0; i < 5; i++) {
  const before = await page.evaluate(() => (window.stoneAge && window.stoneAge.radio) || "");
  await dev(page, "radio_next");
  await until(page, `window.stoneAge && window.stoneAge.radio && window.stoneAge.radio !== ${JSON.stringify(before)} && window.stoneAge.music.includes(window.stoneAge.radio)`, 60000);
  await wait(3000);
}
await sample(page, pid, "08a radio, 5 tracks");
await dev(page, "radio_off");
await wait(4000);
await sample(page, pid, "08b radio off");
await page.reload();
await until(page, settled, 240000);
await wait(3000);
await sample(page, pid, "09 reload: second visit startup (packs from IndexedDB)");
// What IDBFS copied into MEMFS at this start: every file in IndexedDB's
// /userfs store (navigator.storage.estimate lags behind by minutes).
const idb = await page.evaluate(() => new Promise((resolve) => {
  const open = indexedDB.open("/userfs");
  open.onerror = () => resolve(null);
  open.onsuccess = () => {
    const db = open.result;
    const totals = { files: 0, mb: 0, packs: 0, packs_mb: 0 };
    const cursor = db.transaction(["FILE_DATA"], "readonly").objectStore("FILE_DATA").openCursor();
    cursor.onsuccess = () => {
      const entry = cursor.result;
      if (!entry) { resolve(totals); return; }
      const bytes = entry.value && entry.value.contents ? entry.value.contents.byteLength : 0;
      totals.files += 1;
      totals.mb += bytes / 1048576;
      if (String(entry.key).includes("/packs/")) { totals.packs += 1; totals.packs_mb += bytes / 1048576; }
      entry.continue();
    };
    cursor.onerror = () => resolve(totals);
  };
}));
console.log(`[web] IndexedDB /userfs after the reload: ${JSON.stringify(idb)}`);
rows.push({ step: "idb_contents", ...idb });
if (args.out) writeFileSync(args.out, JSON.stringify(rows, null, 2));
await browser.close();
