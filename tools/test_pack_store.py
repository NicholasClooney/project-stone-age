"""web/pack_store.js under Node with a fake network and an in-memory store.

Skipped without Node (18+, for fetch's Response, Headers and Blob). The page
script answers pack downloads (tagged with the X-Stone-Age-Pack header) from
its store when the stored size matches, and otherwise fetches, stores a
complete response and never sends the header. Other requests pass through.
The IndexedDB side and dropping the old IDBFS cache are exercised in a real
browser by tools/web_pack_cache_probe.mjs. docs/technical/web-client.md, "Pack cache".
"""
import json
import shutil
import subprocess
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "web" / "pack_store.js"

HARNESS = r"""
const install = require(process.argv[1]);
const results = {};
const stored = new Map([["old.pck", new Blob([new Uint8Array(3)])], ["short.pck", new Blob([new Uint8Array(2)])], ["buffer.pck", new Uint8Array(5).buffer]]);
let drops = 0;
const backend = {
  get: async (key) => stored.get(key),
  put: async (key, blob) => { stored.set(key, blob); },
  keys: async () => [...stored.keys()],
  remove: async (keys) => keys.forEach((key) => stored.delete(key)),
  dropOld: async () => { drops++; return 7; },
};
const requests = [];
const win = {Headers, Response, Blob, fetch: async (url, init) => {
  const headers = new Headers(init && init.headers);
  requests.push({url, pack: headers.get("X-Stone-Age-Pack"), accept: headers.get("Accept")});
  if (url.endsWith("missing.pck")) return new Response("no", {status: 404});
  if (url.endsWith("truncated.pck")) return new Response(new Uint8Array(4), {status: 200});
  return new Response(new Uint8Array(url.endsWith("new.pck") ? 6 : 1), {status: 200});
}};
const api = install(win, backend);
const tag = (file, bytes) => ({headers: [["X-Stone-Age-Pack", `${file} ${bytes}`], ["Accept", "*/*"]]});
const settle = () => new Promise((r) => setTimeout(r, 10));
(async () => {
  await api.ready;
  results.dropsOldOnce = drops === 1 && api.oldDropped === 7;
  let response = await win.fetch("http://h/packs/old.pck", tag("old.pck", 3));
  results.hitFromStore = requests.length === 0 && response.status === 200 && (await response.arrayBuffer()).byteLength === 3 && response.headers.get("content-length") === "3";
  // An ArrayBuffer (stored where a browser refused Blobs) is a hit too.
  response = await win.fetch("http://h/packs/buffer.pck", tag("buffer.pck", 5));
  results.bufferIsHit = requests.length === 0 && (await response.arrayBuffer()).byteLength === 5 && api.hits === 2;
  response = await win.fetch("http://h/packs/new.pck", tag("new.pck", 6));
  results.missGoesToNetwork = requests.length === 1 && (await response.arrayBuffer()).byteLength === 6;
  results.headerNeverSent = requests[0].pack === null && requests[0].accept === "*/*";
  await settle();
  results.missIsStored = stored.has("new.pck") && stored.get("new.pck").size === 6 && api.stored === 1;
  await win.fetch("http://h/packs/new.pck", tag("new.pck", 6));
  results.storedMissHitsNextTime = requests.length === 1;
  await win.fetch("http://h/packs/short.pck", tag("short.pck", 1));
  results.wrongSizeRefetched = requests.length === 2;
  await settle();
  results.wrongSizeReplaced = stored.get("short.pck").size === 1;
  response = await win.fetch("http://h/packs/missing.pck", tag("missing.pck", 1));
  await settle();
  results.failureNotStored = response.status === 404 && !stored.has("missing.pck");
  await win.fetch("http://h/packs/truncated.pck", tag("truncated.pck", 9));
  await settle();
  results.incompleteNotStored = !stored.has("truncated.pck");
  const before = requests.length;
  await win.fetch("http://h/packs.json?1", {headers: [["Accept", "*/*"]]});
  await win.fetch("http://h/index.wasm");
  results.othersPassThrough = requests.length === before + 2 && requests[before].url === "http://h/packs.json?1";
  const count0 = requests.length;
  const read = await new Promise((resolve) => api.read("new.pck", 6, resolve));
  const taken = api.take("new.pck");
  results.readHandsOverBytes = read === "ok" && taken instanceof Uint8Array && taken.byteLength === 6 && requests.length === count0;
  results.takeOnce = api.take("new.pck") === null;
  results.readWrongSizeMisses = (await new Promise((resolve) => api.read("new.pck", 7, resolve))) === "miss";
  results.readUnknownMisses = (await new Promise((resolve) => api.read("nope.pck", 1, resolve))) === "miss";
  const listed = await new Promise((resolve) => api.list(resolve));
  results.lists = JSON.parse(listed).sort().join(",") === ["buffer.pck", "new.pck", "old.pck", "short.pck"].join(",");
  api.remove(JSON.stringify(["old.pck", "buffer.pck"]));
  await settle();
  results.removes = !stored.has("old.pck") && !stored.has("buffer.pck") && stored.has("new.pck");
  // No IndexedDB at all (some private modes): packs just come from the network.
  const plain = {Headers, Response, Blob, fetch: async (url, init) => { requests.push({url, pack: new Headers(init && init.headers).get("X-Stone-Age-Pack")}); return new Response(new Uint8Array(1)); }};
  const bare = install(plain, null);
  await bare.ready;
  const count = requests.length;
  await plain.fetch("http://h/packs/a.pck", tag("a.pck", 1));
  const empty = await new Promise((resolve) => bare.list(resolve));
  results.noStorageStillWorks = !bare.available && requests.length === count + 1 && requests[count].pack === null && empty === "[]";
  console.log(JSON.stringify(results));
})();
"""


@unittest.skipUnless(shutil.which("node"), "Node is not installed")
class PackStoreTest(unittest.TestCase):
    def test_page_script(self):
        result = subprocess.run(["node", "-e", HARNESS, str(SCRIPT)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        checks = json.loads(result.stdout.strip().splitlines()[-1])
        failed = [name for name, ok in checks.items() if not ok]
        self.assertEqual(failed, [], checks)


if __name__ == "__main__":
    unittest.main()
