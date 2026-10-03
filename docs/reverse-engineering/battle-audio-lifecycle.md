# Battle audio lifetime and map return

Source root: `references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/`.
This audit separates source behaviour from the requested project changes.

## Source evidence

- `system/battleproc.cpp:1044–1046` calls `fade_out_bgm()` on battle exit.
  `system/process.cpp:524–532` explicitly stops the remaining BGM on return
  to the map, redraws the map, and restores the previous map track when no
  map marker selected another. Source does **not** wait for a song to end.
- `system/t_music.cpp:685–690` initializes the fade index to integer
  `bgm_tbl[track].volume * t_music_bgm_volume / 15`. Ordinary battle entry 5
  is `sabgm_b0`, volume 122 (`2789`), and the default music setting is 15
  (`3528`). `3469–3487` lowers that index by one per check and stops on the
  check after it reaches zero. The volume table (`1859–1863`) is logarithmic:
  DirectSound hundredths of a dB, equivalent to `50*log10(index/127)` dB.
- The check chain is `gamemain.cpp:288` → `t_music.cpp:3623–3625`
  (`cdda_play`) → `3491–3506` (`check_se_loop`/`bgm_fade_check`). The checked-in
  `systeminc/version.h:575` leaves `_OPTIMIZATIONFLIP_` disabled; `627` defines
  `_SYSTEM_SLEEP_=6`. `gamemain.cpp:102–108,595–611,822–828,941–945` targets
  6 ms per main loop, including catch-up iterations. Thus a full-volume
  fade has **123 checks, nominally 0.738 seconds**, not an arbitrary one-second
  fade or 122 frames at 60 Hz. Real source timing depends on workload and the
  map return may stop it early; this is a nominal conversion, not a measured
  Windows-client audio duration. The port accumulates 6 ms steps from frame
  delta, independent of animation acceleration/render frequency, and lets
  the fade finish before starting map music. Its continuous slider maps to
  the source's 0–15 setting when the fade begins.
- New battles select music in `battleproc.cpp:452–478`; `play_bgm`
  (`t_music.cpp:2847–2849`) calls `stop_thread`, which stops/releases only the
  old music buffers (`640–656`). There are never overlapping BGM tracks.
- Capture success saves the previous track, sets happy255, and starts BGM 0
  (`oft/oft.cpp:8672–8677`). It requests the saved track when that counter
  expires (`8732–8737`). BGM 0 is `sabgm_s0`, with loop flag zero
  (`t_music.cpp:2783,2954–2957`). The current port's animation already models
  happy255 as 4.25 seconds at 1× (`battle_view.gd`, `queue_capture`); that is
  the port's 255/60 presentation conversion, **not a proven 4.25-second source
  wall clock**. This audio change preserves that cue and all animation timing.
- Source SE use a separate 64-slot voice array (`t_music.cpp:60,97–102`);
  `play_se:3009–3112` reuses slots and throttles duplicate cues. Battle entry,
  map return and music stopping do not stop this whole pool. The original
  does not promise no stealing when its ring wraps.

## Port behaviour and deliberate project changes

Ordinary wins currently emit result SE 202 or level-up SE 211
(`battle_view.gd`, result panel), not a separate victory BGM. The music
library calls `sabgm_s0` “胜利”, but the existing game uses it for successful
capture. No new ordinary-win song or separate second jingle was invented.
The settings music tooltip and player changelog state this distinction.

The game scene owns one streamed music player and a maximum of seven effect
players (the existing current-plus-six budget). Returning to the map only
hides the battle view; those players remain alive. Effects now change ownership
by swapping the current/spare player references, instead of restarting a copy
at a guessed playback position. This also preserves an already-playing copy
of the **same** sound. At capacity a new cue is omitted: already-admitted SE
finish naturally, and there is no queue of stale cues or growing node list.
New battles never clear the effect pool. Effects-off mutes ongoing tails and
suppresses new cues; music-off mutes without halting completion.

A game-owned audio controller has a single frame callback and one music
`finished` connection, with no per-battle timers, detached players or retained
callback chain. New battles clear its pending music/fade/capture ownership,
then replace the old music. Explicit game shutdown cancels pending recovery.

**项目改动：胜利结算音效与捕获成功曲播完后恢复地图音乐。**
The ordinary battle BGM fades using the source steps; any still-playing result
SE finishes before map music starts. Capture `sabgm_s0` plays once from a
private non-looping stream, preserving the cached stream used by the library
and radio. An early happy255 restoration cue waits for actual completion;
if the song ends first it waits for the animation cue. Map return supersedes
that saved battle-track target, and later map changes update the pending map
track. A new battle replaces old music immediately. Multiple accelerated
captures within one battle share an unfinished jingle rather than stacking or
restarting it. These full-jingle/no-SE-stealing rules are project changes,
not claims about the original client.

Watched automation still suspends the radio, preserving its track/position;
between battles audio can now finish into map music, and the run's final tail
finishes before the radio resumes. An explicitly active, unsuspended radio
continues to own music as before. `web/audio_session.js` is unchanged: no new
AudioContext, session category, gesture handler, or media-session interface.
The controller holds fade steps while the player/context is suspended or
interrupted; a closed context cannot strand a pending transition. Null/stopped
music cannot wait forever for a nonexistent `finished` signal.

## Verification boundary

`battle_audio_tail_test.gd` uses the real scene, authority-opened/closed battles,
AudioStreamPlayer lifecycle/finished signals, the imported capture Ogg and
silent PCM fixtures. It checks fade timing, identical SE, overload bounds,
ordinary victory, capture cue ordering, repeated battles, mute/volume,
interrupted/closed context-state injection and scene disposal. Conditions use
`tests/support/wait.gd`, not fixed sleeps. Existing capture/showcase/radio/music/
settings/web suites cover their shared paths; showcase and smoke expectations
now wait for actual audio completion.

Desktop verification uses macOS Godot 4.6, headless + Dummy audio. It validates
engine mixing/completion and ownership, **not speaker output or listening**.
`tools/test_audio_session.py` runs the unchanged JS against fake browser
objects in Node, and `web_audio_test.gd` injects page/context states. No browser
automation tool was exposed in this agent session; no real browser/WebAudio,
Safari/Vision Pro interruption, background-tab playback or audible quality
verification is claimed.
