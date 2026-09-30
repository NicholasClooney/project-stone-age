// Keeps the web client's downloaded asset packs across visits without putting
// them in user:// (docs/technical/web-client.md, "Pack cache").
//
// user:// on the web is Emscripten's IDBFS: at every start the engine copies
// the whole IndexedDB store into memory (MEMFS) before the game runs. Packs
// used to live there, so a well-travelled browser loaded hundreds of MB it
// never mounted. This script, loaded in <head> before the engine, instead:
//   - keeps packs in an IndexedDB database of its own ("stone-age-packs"),
//     keyed by the content-hashed file name, that nothing loads at startup;
//   - hands a stored pack to the game in one piece (read() then take()), which
//     writes it into memory just before mounting it;
//   - wraps window.fetch: a request carrying the X-Stone-Age-Pack header
//     (client/scripts/web_pack_store.gd adds it to pack downloads) goes to the
//     network and a complete response is stored (or, if the pack turned up in
//     the database meanwhile, is answered from there); the header never
//     leaves the page;
//   - deletes the packs an older build cached in IDBFS (user://packs/), in a
//     transaction that starts before the engine reads IDBFS, so even the first
//     start after the update does not load them; the packs a session needs
//     download again once;
//   - lets the game list and delete stored packs (window.stoneAgePackStore).
// The game writes each pack it mounts into a MEMFS folder outside IDBFS.
// Plain IndexedDB, not the Cache API: caches exist only in secure contexts,
// and the LAN page is plain http.
(function (root) {
  "use strict";

  var HEADER = "X-Stone-Age-Pack";
  var DB_NAME = "stone-age-packs";
  var STORE = "packs";
  var OLD_DB = "/userfs";
  var OLD_STORE = "FILE_DATA";
  // user:// is /userfs/godot/app_userdata/<project name>/ in the web build.
  var OLD_ROOT = "/userfs/godot/app_userdata/";
  var OLD_PACKS = /^\/userfs\/godot\/app_userdata\/[^/]+\/packs(?:\/[^/]+)?$/;

  function sizeOf(value) {
    if (!value) return -1;
    if (typeof value.size === "number") return value.size;
    if (typeof value.byteLength === "number") return value.byteLength;
    return -1;
  }

  // The IndexedDB side. Values are Blobs (Chrome keeps them on disk and
  // streams them); an ArrayBuffer when a browser refuses to store a Blob.
  function indexedDbBackend(idb, win) {
    var opening = null;
    function open() {
      if (!opening) {
        opening = new Promise(function (resolve, reject) {
          var request = idb.open(DB_NAME, 1);
          request.onupgradeneeded = function () {
            if (!request.result.objectStoreNames.contains(STORE)) request.result.createObjectStore(STORE);
          };
          request.onsuccess = function () {
            var db = request.result;
            db.onversionchange = function () { db.close(); opening = null; };
            resolve(db);
          };
          request.onerror = function () { opening = null; reject(request.error); };
        });
      }
      return opening;
    }
    function transact(mode, work) {
      return open().then(function (db) {
        return new Promise(function (resolve, reject) {
          var tx = db.transaction(STORE, mode);
          var out;
          work(tx.objectStore(STORE), function (value) { out = value; });
          tx.oncomplete = function () { resolve(out); };
          tx.onerror = tx.onabort = function () { reject(tx.error); };
        });
      });
    }
    function put(key, value) {
      return transact("readwrite", function (store) { store.put(value, key); });
    }
    return {
      get: function (key) {
        return transact("readonly", function (store, set) {
          var request = store.get(key);
          request.onsuccess = function () { set(request.result); };
        });
      },
      put: function (key, blob) {
        return put(key, blob).catch(function (error) {
          // Some WebKit versions cannot store Blobs in IndexedDB.
          if (!error || error.name !== "DataCloneError" || !blob.arrayBuffer) throw error;
          return blob.arrayBuffer().then(function (buffer) { return put(key, buffer); });
        });
      },
      keys: function () {
        return transact("readonly", function (store, set) {
          var request = store.getAllKeys();
          request.onsuccess = function () { set(request.result); };
        });
      },
      remove: function (keys) {
        return transact("readwrite", function (store) {
          keys.forEach(function (key) { store.delete(key); });
        });
      },
      // Deletes user://packs/ and everything in it from IDBFS, walking keys
      // only (no pack is read). The engine's IDBFS read, which starts once
      // the engine has downloaded, waits for this readwrite transaction.
      // Resolves with how many files it deleted.
      dropOld: function () {
        return new Promise(function (resolve) {
          var request;
          try { request = idb.open(OLD_DB); } catch (error) { resolve(0); return; }
          request.onupgradeneeded = function () {
            // No IDBFS database yet: do not create one (the engine does).
            request.transaction.abort();
          };
          request.onerror = function () { resolve(0); };
          request.onblocked = function () { resolve(0); };
          request.onsuccess = function () {
            var db = request.result;
            if (!db.objectStoreNames.contains(OLD_STORE)) { db.close(); resolve(0); return; }
            var dropped = 0;
            var tx = db.transaction(OLD_STORE, "readwrite");
            var store = tx.objectStore(OLD_STORE);
            var cursor = store.openKeyCursor(win.IDBKeyRange.bound(OLD_ROOT, OLD_ROOT + "￿"));
            cursor.onsuccess = function () {
              var entry = cursor.result;
              if (!entry) return;
              if (OLD_PACKS.test(String(entry.primaryKey))) {
                store.delete(entry.primaryKey);
                dropped += 1;
              }
              entry.continue();
            };
            tx.oncomplete = function () { db.close(); resolve(dropped); };
            tx.onerror = tx.onabort = function () { db.close(); resolve(0); };
          };
        });
      },
    };
  }

  function install(win, backend) {
    var api = {hits: 0, misses: 0, stored: 0, errors: 0, oldDropped: 0, lastError: ""};
    win.stoneAgePackStore = api;
    var nativeFetch = win.fetch;
    if (!nativeFetch) return api;
    if (!backend) {
      try {
        backend = win.indexedDB ? indexedDbBackend(win.indexedDB, win) : null;
      } catch (error) { backend = null; }
    }
    function fail(error) {
      api.errors += 1;
      api.lastError = String(error && (error.name || error.message) || error);
    }
    api.ready = backend
      ? backend.dropOld().then(function (count) { api.oldDropped = count; }, fail)
      : Promise.resolve();
    api.available = !!backend;
    function lookup(file) {
      return backend ? api.ready.then(function () { return backend.get(file); }) : Promise.resolve(null);
    }

    win.fetch = function (input, init) {
      var headers = init && init.headers ? new win.Headers(init.headers) : null;
      var tag = headers ? headers.get(HEADER) : null;
      if (!tag) return nativeFetch.apply(win, arguments);
      headers.delete(HEADER);
      var clean = {};
      for (var key in init) clean[key] = init[key];
      clean.headers = headers;
      var parts = tag.trim().split(/\s+/);
      var file = parts[0];
      var bytes = Number(parts[1]);
      return lookup(file).catch(function (error) { fail(error); return null; }).then(function (hit) {
        if (hit && sizeOf(hit) === bytes) {
          api.hits += 1;
          return new win.Response(hit, {status: 200, headers: {"Content-Type": "application/octet-stream", "Content-Length": String(bytes)}});
        }
        api.misses += 1;
        return nativeFetch.call(win, input, clean).then(function (response) {
          if (backend && response.ok) {
            response.clone().blob().then(function (blob) {
              if (blob.size !== bytes) return;
              return backend.put(file, blob).then(function () { api.stored += 1; });
            }).catch(fail);
          }
          return response;
        });
      });
    };

    // callback(json): the stored file names as a JSON array ("[]" on errors).
    api.list = function (callback) {
      var keys = backend ? api.ready.then(function () { return backend.keys(); }) : Promise.resolve([]);
      keys.then(function (names) { callback(JSON.stringify(names || [])); }, function (error) { fail(error); callback("[]"); });
    };
    // Reads a stored pack for the game: callback("ok") once take(file) can
    // hand over its bytes (a Uint8Array, which Godot's JavaScriptBridge.eval
    // returns as a PackedByteArray), callback("miss") when it is not stored
    // or has the wrong size.
    var taken = {};
    api.read = function (file, bytes, callback) {
      lookup(file).then(function (value) {
        if (!value || sizeOf(value) !== Number(bytes)) { api.misses += 1; callback("miss"); return; }
        return (value.arrayBuffer ? value.arrayBuffer() : Promise.resolve(value)).then(function (buffer) {
          taken[file] = new Uint8Array(buffer);
          api.hits += 1;
          callback("ok");
        });
      }).catch(function (error) { fail(error); callback("miss"); });
    };
    api.take = function (file) {
      var data = taken[file];
      delete taken[file];
      return data || null;
    };
    // files: a JSON array of file names.
    api.remove = function (files) {
      if (!backend) return;
      var names = typeof files === "string" ? JSON.parse(files) : files;
      if (!names.length) return;
      api.ready.then(function () { return backend.remove(names); }).catch(fail);
    };
    return api;
  }

  install.indexedDbBackend = indexedDbBackend;
  if (typeof module !== "undefined" && module.exports) module.exports = install;
  else install(root);
})(typeof window !== "undefined" ? window : this);
