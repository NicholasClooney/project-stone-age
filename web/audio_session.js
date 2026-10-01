// Keeps the web client's sound alive across system audio interruptions
// (docs/technical/web-client.md, "Audio interruptions").
//
// WebKit (Safari on iPhone, iPad, Vision Pro, Mac) can move an AudioContext to
// "suspended" or the non-standard "interrupted" state when the system pauses
// media (a call, Siri, stepping out of the environment on Vision Pro), and it
// often does not come back on its own; resume() only works from a user gesture
// and is sometimes rejected the first time. Godot creates its AudioContext
// inside the engine where the page cannot reach it, so this script, loaded in
// <head> before the engine, wraps the constructor to keep a reference, then:
//   - reports every state change and page hide/show to the game
//     (window.stoneAgeAudio.listener, set by client/scripts/web_audio.gd);
//   - on every tap, click or key press while the context is not running, plays
//     a short silent media element (re-activates the page's audio session) and
//     calls resume(), retrying on the next gesture if it fails;
//   - after the page was hidden, the first gesture also starts a one-sample
//     buffer, which wakes a context that reports "running" but went silent;
//   - offers Media Session helpers so system controls can pause and resume
//     the radio and show the playing track.
(function (root) {
  "use strict";

  function install(win, doc, nav) {
    var Native = win.AudioContext || win.webkitAudioContext;
    var api = {contexts: [], listener: null, returned: false, log: [], resumes: 0, session: ""};
    win.stoneAgeAudio = api;
    // iOS / iPadOS 16.4+ Safari: a "playback" audio session plays through the
    // ring/silent switch, like a music app (the default "auto" session is
    // silenced in silent mode). Set before any AudioContext is created.
    try {
      if (nav && nav.audioSession && "type" in nav.audioSession) {
        nav.audioSession.type = "playback";
        api.session = String(nav.audioSession.type);
      }
    } catch (error) { api.session = "unavailable"; }
    if (!Native) return api;

    function note(what) {
      api.log.push(what);
      if (api.log.length > 50) api.log.shift();
      if (typeof api.listener === "function") {
        try { api.listener(what); } catch (error) { /* the game may be reloading */ }
      }
    }

    function Wrapped(options) {
      var context = options === undefined ? new Native() : new Native(options);
      api.contexts.push(context);
      context.addEventListener("statechange", function () { note("state:" + context.state); });
      return context;
    }
    Wrapped.prototype = Native.prototype;
    win.AudioContext = Wrapped;
    if (win.webkitAudioContext) win.webkitAudioContext = Wrapped;

    api.context = function () { return api.contexts[api.contexts.length - 1] || null; };
    api.state = function () { var c = api.context(); return c ? c.state : "none"; };

    // A data URL of `samples` frames of 8 kHz, 8-bit mono silence (0.1 s for 800).
    function silentWav(samples) {
      function u32(n) { return String.fromCharCode(n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >>> 24) & 255); }
      function u16(n) { return String.fromCharCode(n & 255, (n >> 8) & 255); }
      var header = "RIFF" + u32(36 + samples) + "WAVE" + "fmt " + u32(16) + u16(1) + u16(1) + u32(8000) + u32(8000) + u16(1) + u16(8) + "data" + u32(samples);
      var body = new Array(samples + 1).join(String.fromCharCode(128));
      var text = header + body;
      var encoded = win.btoa ? win.btoa(text) : Buffer.from(text, "binary").toString("base64");
      return "data:audio/wav;base64," + encoded;
    }
    api.silentWav = silentWav;

    var silence = null;
    function unlockMedia() {
      // A playing media element makes WebKit reactivate the page's audio session.
      try {
        if (!silence) {
          silence = doc.createElement("audio");
          silence.src = silentWav(800);
          silence.setAttribute("playsinline", "");
          silence.preload = "auto";
        }
        var played = silence.play();
        if (played && played.catch) played.catch(function () {});
      } catch (error) { /* not allowed here; the resume below may still work */ }
    }

    function tick(context) {
      // One silent sample through the graph wakes a context that says "running"
      // but lost its output while the page was away.
      try {
        var buffer = context.createBuffer(1, 1, context.sampleRate || 44100);
        var source = context.createBufferSource();
        source.buffer = buffer;
        source.connect(context.destination);
        source.start(0);
      } catch (error) { /* harmless */ }
    }

    api.resume = function () {
      var context = api.context();
      if (!context || context.state === "closed") return false;
      if (context.state !== "running") {
        api.resumes += 1;
        unlockMedia();
        try {
          var resumed = context.resume();
          if (resumed && resumed.catch) resumed.catch(function () { note("resume-failed"); });
        } catch (error) { note("resume-failed"); }
        tick(context);
        return true;
      }
      if (api.returned) {
        api.returned = false;
        tick(context);
        return true;
      }
      return false;
    };

    function gesture() { api.resume(); }
    ["pointerdown", "touchend", "mousedown", "keydown"].forEach(function (type) {
      doc.addEventListener(type, gesture, true);
    });
    doc.addEventListener("visibilitychange", function () {
      if (doc.hidden) note("hidden");
      else { api.returned = true; note("visible"); }
    });
    win.addEventListener("pagehide", function () { note("hidden"); });
    win.addEventListener("pageshow", function () { api.returned = true; note("visible"); });

    // Media Session: system play/pause controls and the Now Playing title.
    api.setNowPlaying = function (title, playing) {
      if (!nav || !nav.mediaSession) return;
      try {
        if (title) {
          var Metadata = win.MediaMetadata;
          nav.mediaSession.metadata = Metadata ? new Metadata({title: title, artist: "石器时代 电台"}) : null;
        } else {
          nav.mediaSession.metadata = null;
        }
        nav.mediaSession.playbackState = title ? (playing ? "playing" : "paused") : "none";
      } catch (error) { /* unsupported */ }
    };
    api.setActions = function (onPlay, onPause) {
      if (!nav || !nav.mediaSession || !nav.mediaSession.setActionHandler) return;
      try {
        nav.mediaSession.setActionHandler("play", function () { api.resume(); if (onPlay) onPlay(); });
        nav.mediaSession.setActionHandler("pause", function () { if (onPause) onPause(); });
      } catch (error) { /* unsupported */ }
    };
    return api;
  }

  if (typeof module !== "undefined" && module.exports) module.exports = install;
  else install(root, root.document, root.navigator);
})(typeof window !== "undefined" ? window : this);
