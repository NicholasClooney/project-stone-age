// Pack cache probe: how a warm pack cache affects the web client's start.
// Fills the browser with packs the way a build before the pack store did
// (Emscripten IDBFS entries under /userfs/packs/, which the engine copies into
// memory at startup), then opens the game a few times in a fresh headless
// Chromium on the same profile and records per visit: time until the engine
// runs game code and until startup settles, the wasm heap, the page renderer's
// footprint, pack requests that reached the network, and what IndexedDB holds
// (IDBFS and the pack store). See docs/technical/memory-baseline.md.
//
//   node tools/web_pack_cache_probe.mjs --modules <dir with playwright-core> \
//     --url 'http://127.0.0.1:8792/?server=ws://127.0.0.1:8793' \
//     --chrome <Chrome for Testing binary> --profile <scratch dir> \
//     [--seed-mb 1000] [--visits 2] [--project "Stone Age — 萨姆吉尔村"] [--out build/pack-cache-probe.json]
//
// --seed-mb: how many MB of the build's packs to plant in IDBFS first (all of
// them by default; 0 skips seeding). The page must be foreground or headless:
// background tabs throttle requestAnimationFrame and stall the engine.
import { createRequire } from "node:module";
import { execSync } from "node:child_process";
import { rmSync, writeFileSync } from "node:fs";

const args = Object.fromEntries(process.argv.slice(2).reduce((pairs, value, index, all) => {
  if (value.startsWith("--")) pairs.push([value.slice(2), all[index + 1]]);
  return pairs;
}, []));
const require = createRequire(args.modules ? `${args.modules}/package.json` : import.meta.url);
const { chromium } = require("playwright-core");
const MB = 1048576;
const visits = Number(args.visits || 2);
const seedMb = args["seed-mb"] === undefined ? Infinity : Number(args["seed-mb"]);
const origin = new URL(args.url).origin;
const rows = [];

const wasmHook = () => {
  // Frames the page draws (headless SwiftShader runs well below 60 fps).
  window.__frames = 0;
  const tick = () => { window.__frames += 1; requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
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
};

// Plants packs the way IDBFS stores files: {timestamp, mode, contents} under
// user://packs/<file> (/userfs/godot/app_userdata/<project name>/packs/) in the
// FILE_DATA store of the "/userfs" database.
const seed = async ({ limit, user }) => {
  const index = await (await fetch("/packs/packs.json")).json();
  const files = Object.values(index.packs).sort((a, b) => a.file.localeCompare(b.file));
  const db = await new Promise((resolve, reject) => {
    const open = indexedDB.open("/userfs", 21);
    open.onupgradeneeded = () => {
      const store = open.result.createObjectStore("FILE_DATA");
      store.createIndex("timestamp", "timestamp", { unique: false });
    };
    open.onsuccess = () => resolve(open.result);
    open.onerror = () => reject(open.error);
  });
  const put = (entries) => new Promise((resolve, reject) => {
    const tx = db.transaction("FILE_DATA", "readwrite");
    for (const [key, value] of entries) tx.objectStore("FILE_DATA").put(value, key);
    tx.oncomplete = resolve;
    tx.onerror = () => reject(tx.error);
  });
  const dirs = ["/userfs/godot", "/userfs/godot/app_userdata", user, user + "/packs"];
  await put(dirs.map((dir) => [dir, { timestamp: new Date(), mode: 16895 }]));
  let bytes = 0, count = 0, batch = [], batchBytes = 0;
  for (const entry of files) {
    if (bytes + entry.bytes > limit) continue;
    const data = new Uint8Array(await (await fetch("/packs/" + entry.file)).arrayBuffer());
    batch.push([user + "/packs/" + entry.file, { timestamp: new Date(), mode: 33206, contents: data }]);
    bytes += data.byteLength; batchBytes += data.byteLength; count += 1;
    if (batchBytes > 32 * 1048576) { await put(batch); batch = []; batchBytes = 0; }
  }
  if (batch.length) await put(batch);
  db.close();
  return { packs: count, mb: bytes / 1048576 };
};

// What IndexedDB holds: the IDBFS store (copied into memory at every start)
// and the pack store (read one pack at a time).
const storage = async () => {
  const sum = (name, storeName, measure) => new Promise((resolve) => {
    const open = indexedDB.open(name);
    open.onupgradeneeded = () => open.transaction.abort();
    open.onerror = () => resolve(null);
    open.onsuccess = () => {
      const db = open.result;
      if (!db.objectStoreNames.contains(storeName)) { db.close(); resolve(null); return; }
      const totals = { entries: 0, mb: 0, packs: 0, packs_mb: 0, other_mb: 0, largest_other: [] };
      const cursor = db.transaction(storeName, "readonly").objectStore(storeName).openCursor();
      cursor.onsuccess = () => {
        const entry = cursor.result;
        if (!entry) { db.close(); resolve(totals); return; }
        const bytes = measure(entry.value);
        totals.entries += 1;
        totals.mb += bytes / 1048576;
        if (String(entry.key).endsWith(".pck")) { totals.packs += 1; totals.packs_mb += bytes / 1048576; }
        else if (bytes > 0) {
          totals.other_mb += bytes / 1048576;
          totals.largest_other.push([String(entry.key).replace(/^.*app_userdata\/[^/]+\//, "user://"), bytes]);
          totals.largest_other.sort((a, b) => b[1] - a[1]);
          totals.largest_other.length = Math.min(totals.largest_other.length, 5);
        }
        entry.continue();
      };
    };
  });
  return {
    idbfs: await sum("/userfs", "FILE_DATA", (v) => (v && v.contents ? v.contents.byteLength : 0)),
    pack_store: await sum("stone-age-packs", "packs", (v) => (v ? (v.size ?? v.byteLength ?? 0) : 0)),
  };
};

function rendererFootprint(rootPid) {
  const table = execSync("ps -axo pid=,ppid=,command=").toString().trim().split("\n").map((line) => {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(.*)$/);
    return match && { pid: +match[1], ppid: +match[2], command: match[3] };
  }).filter(Boolean);
  const children = new Set([rootPid]);
  for (let changed = true; changed;) {
    changed = false;
    for (const row of table) if (children.has(row.ppid) && !children.has(row.pid)) { children.add(row.pid); changed = true; }
  }
  let largest = 0;
  for (const row of table) {
    if (!children.has(row.pid) || !row.command.includes("--type=renderer")) continue;
    try {
      const match = execSync(`footprint -p ${row.pid} 2>/dev/null`).toString().match(/Footprint:\s+([\d.]+)\s+(KB|MB|GB)/);
      if (match) largest = Math.max(largest, +match[1] * { KB: 1 / 1024, MB: 1, GB: 1024 }[match[2]]);
    } catch (e) { /* gone */ }
  }
  return largest;
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function until(page, predicate, timeout) {
  const limit = Date.now() + timeout;
  while (Date.now() < limit) {
    if (await page.evaluate(predicate).catch(() => false)) return true;
    await wait(100);
  }
  return false;
}

async function launch() {
  const context = await chromium.launchPersistentContext(args.profile, {
    executablePath: args.chrome,
    headless: true,
    viewport: { width: 1280, height: 800 },
    args: ["--enable-precise-memory-info", "--autoplay-policy=no-user-gesture-required", "--enable-unsafe-swiftshader", "--use-angle=swiftshader", "--ignore-gpu-blocklist"],
  });
  // The browser process is the one started with this profile and no --type.
  const pid = execSync("ps -axo pid=,command=").toString().split("\n")
    .filter((line) => line.includes(`--user-data-dir=${args.profile}`) && !line.includes("--type="))
    .map((line) => +line.trim().split(/\s+/)[0])[0];
  return { context, pid };
}

// --keep-profile: reuse the profile (and its cache) from an earlier run.
if (!args["keep-profile"]) rmSync(args.profile, { recursive: true, force: true });
if (seedMb > 0 && !args["keep-profile"]) {
  const { context } = await launch();
  const page = await context.newPage();
  await page.goto(`${origin}/packs/packs.json`);
  const planted = await page.evaluate(seed, { limit: Number.isFinite(seedMb) ? seedMb * MB : Number.MAX_SAFE_INTEGER, user: `/userfs/godot/app_userdata/${args.project || "Stone Age — 萨姆吉尔村"}` });
  console.log(`[probe] planted ${planted.packs} packs, ${planted.mb.toFixed(0)} MB in IDBFS (user://packs/)`);
  rows.push({ step: "seed", ...planted, storage: await page.evaluate(storage) });
  await context.close();
}

for (let visit = 1; visit <= visits; visit++) {
  const { context, pid } = await launch();
  await context.addInitScript(wasmHook);
  const page = await context.newPage();
  const packRequests = [];
  page.on("request", (request) => { if (/\/packs\/.+\.pck/.test(request.url())) packRequests.push(request.url().split("/").pop()); });
  page.on("console", (message) => { if (/packs\]|error/i.test(message.text())) console.log(`[page] ${message.text().slice(0, 160)}`); });
  const started = Date.now();
  await page.goto(args.url);
  const engine = await until(page, "!!window.stoneAge", 300000);
  const engineMs = Date.now() - started;
  // Playable: the waiting screen is gone and the map is built. Settled: the
  // neighbouring maps' packs prefetched in the background are mounted too.
  const playable = await until(page, "window.stoneAge && !window.stoneAge.waiting_screen && window.stoneAge.map >= 0", 300000);
  const playableMs = Date.now() - started;
  const settled = await until(page, "window.stoneAge && !window.stoneAge.waiting_screen && window.stoneAge.pending === 0 && window.stoneAge.map >= 0", 300000);
  const settledMs = Date.now() - started;
  const frames = await page.evaluate(() => window.__frames || 0);
  await wait(3000);
  const stats = await page.evaluate(() => ({
    wasm_heap_mb: (window.__wasmMemories || []).reduce((sum, m) => sum + m.buffer.byteLength, 0) / 1048576,
    js_used_mb: performance.memory ? performance.memory.usedJSHeapSize / 1048576 : null,
    mounted: window.stoneAge ? window.stoneAge.mounted : null,
    store: window.stoneAgePackStore ? { hits: window.stoneAgePackStore.hits, misses: window.stoneAgePackStore.misses, stored: window.stoneAgePackStore.stored, old_dropped: window.stoneAgePackStore.oldDropped, errors: window.stoneAgePackStore.errors } : null,
  }));
  const row = { step: `visit ${visit}`, engine_ok: engine, playable_ok: playable, settled_ok: settled, engine_ms: engineMs, playable_ms: playableMs, settled_ms: settledMs, fps: frames / (settledMs / 1000), ...stats,
    page_renderer_footprint_mb: rendererFootprint(pid), pack_requests: packRequests.length, storage: await page.evaluate(storage) };
  rows.push(row);
  console.log(`[probe] visit ${visit}: game code after ${(engineMs / 1000).toFixed(1)} s, playable after ${(playableMs / 1000).toFixed(1)} s, prefetch done after ${(settledMs / 1000).toFixed(1)} s (${row.fps.toFixed(0)} fps) | wasm ${row.wasm_heap_mb.toFixed(0)} MB | js ${row.js_used_mb ? row.js_used_mb.toFixed(0) : "?"} MB | page renderer ${row.page_renderer_footprint_mb.toFixed(0)} MB | mounted ${row.mounted} | pack requests ${row.pack_requests} | store ${JSON.stringify(row.store)}`);
  console.log(`[probe]    IndexedDB ${JSON.stringify(row.storage)}`);
  await context.close();
}
if (args.out) writeFileSync(args.out, JSON.stringify(rows, null, 2));
