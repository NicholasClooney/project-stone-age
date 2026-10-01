"""web/audio_session.js against fake browser objects, run with Node.

Skipped without Node. The script wraps the AudioContext constructor, reports
state changes and page visibility to the game, resumes a non-running context
on every user gesture (after starting a silent media element), and drives the
Media Session. docs/technical/web-client.md, "Audio interruptions".
"""
import json
import shutil
import subprocess
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "web" / "audio_session.js"

HARNESS = r"""
const install = require(process.argv[1]);
const results = {};
const listeners = {doc: {}, win: {}};
const on = (bag) => (type, fn) => { (bag[type] = bag[type] || []).push(fn); };
const fire = (bag, type) => (bag[type] || []).forEach((fn) => fn({type}));
let played = 0, resumeCalls = 0, sources = 0, rejectNext = false;
class FakeContext {
  constructor() { this.state = "suspended"; this.sampleRate = 48000; this._l = []; this.destination = {}; }
  addEventListener(type, fn) { if (type === "statechange") this._l.push(fn); }
  set(state) { this.state = state; this._l.forEach((fn) => fn()); }
  resume() { resumeCalls++; if (rejectNext) { rejectNext = false; return Promise.reject(new Error("no")); } this.set("running"); return Promise.resolve(); }
  createBuffer() { return {}; }
  createBufferSource() { return {connect() {}, start() { sources++; }}; }
}
const handlers = {};
const store = {};
const nav = {userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", audioSession: {type: "auto"}, mediaSession: {metadata: null, playbackState: "none", setActionHandler(name, fn) { handlers[name] = fn; }}};
const win = {localStorage: {getItem: (k) => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }}, AudioContext: FakeContext, addEventListener: on(listeners.win), btoa: (s) => Buffer.from(s, "binary").toString("base64"),
  MediaMetadata: function (m) { Object.assign(this, m); }};
const doc = {hidden: false, addEventListener: on(listeners.doc),
  createElement: () => ({setAttribute() {}, play() { played++; return Promise.resolve(); }})};
const api = install(win, doc, nav);
const playbackSession = nav.audioSession.type === "playback" && api.session === "playback" && api.mix === false;
api.setMix(true);
const mixes = nav.audioSession.type === "ambient" && store.stoneAgeAudioMix === "1";
const remembered = install({AudioContext: FakeContext, addEventListener() {}, localStorage: win.localStorage}, doc, {userAgent: nav.userAgent, audioSession: {type: "auto"}}).mix === true;
const visionNav = {userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari", audioSession: {type: "auto"}};
const visionMixes = install({AudioContext: FakeContext, addEventListener() {}}, doc, visionNav).mix === true && visionNav.audioSession.type === "ambient";
api.setMix(false);
const events = [];
api.listener = (e) => events.push(e);

const ctx = new win.AudioContext();
results.wrapped = ctx instanceof FakeContext && api.context() === ctx && api.state() === "suspended";
fire(listeners.doc, "pointerdown");
results.firstTapResumes = ctx.state === "running" && resumeCalls === 1 && played === 1;
ctx.set("interrupted");
results.reportsInterrupted = events.includes("state:interrupted");
fire(listeners.doc, "keydown");
results.gestureResumesInterrupted = ctx.state === "running" && resumeCalls === 2 && played === 2;
ctx.set("suspended");
rejectNext = true;
fire(listeners.doc, "touchend");
Promise.resolve().then(() => new Promise((r) => setTimeout(r, 0))).then(() => {
  results.rejectedResumeNoted = events.includes("resume-failed") && ctx.state === "suspended";
  fire(listeners.doc, "mousedown");
  results.retriesOnNextGesture = ctx.state === "running" && resumeCalls === 4;
  const callsBefore = resumeCalls, sourcesBefore = sources;
  fire(listeners.doc, "pointerdown");
  results.runningTapIsQuiet = resumeCalls === callsBefore && sources === sourcesBefore;
  doc.hidden = true; fire(listeners.doc, "visibilitychange");
  doc.hidden = false; fire(listeners.doc, "visibilitychange");
  results.reportsVisibility = events.includes("hidden") && events.includes("visible");
  fire(listeners.doc, "pointerdown");
  results.returnTicksOnce = sources === sourcesBefore + 1 && resumeCalls === callsBefore;
  fire(listeners.doc, "pointerdown");
  results.onlyFirstTapAfterReturn = sources === sourcesBefore + 1;
  let play = 0, pause = 0;
  api.setActions(() => play++, () => pause++);
  api.setNowPlaying("伊甸大陆", true);
  results.nowPlaying = nav.mediaSession.metadata.title === "伊甸大陆" && nav.mediaSession.metadata.artist === "石器时代 电台" && nav.mediaSession.playbackState === "playing";
  ctx.set("suspended");
  handlers.play(); handlers.pause();
  results.systemControls = play === 1 && pause === 1 && ctx.state === "running";
  api.setNowPlaying("", false);
  results.clearsNowPlaying = nav.mediaSession.metadata === null && nav.mediaSession.playbackState === "none";
  results.silentWav = api.silentWav(800).startsWith("data:audio/wav;base64,UklGR");
  results.playbackSession = playbackSession;
  results.mixSwitch = mixes && remembered && nav.audioSession.type === "playback";
  results.otherDevicesMix = visionMixes;
  console.log(JSON.stringify(results));
});
"""


@unittest.skipUnless(shutil.which("node"), "Node is not installed")
class AudioSessionTest(unittest.TestCase):
    def test_page_script(self):
        result = subprocess.run(["node", "-e", HARNESS, str(SCRIPT)], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        checks = json.loads(result.stdout.strip().splitlines()[-1])
        failed = [name for name, ok in checks.items() if not ok]
        self.assertEqual(failed, [], checks)


if __name__ == "__main__":
    unittest.main()
