# Dream cave authoritative time gates

This slice implements only the five reviewed MapWarpPoint entrances and the shared
server clock. Four TimeMan visual/dialogue projections remain a separate slice;
registering the complete quest and restricting helper destinations belongs to the
route manifest/helper. No additional timed village gates are enabled.

## Manifest contract

Use `world.time_gates: "dream-cave"`. In `sources`, pin the SHA256 of every path in
`tools/quest_time_gates.py:SOURCES`. The normal module loader verifies those SHAs.
The loader derives exactly five gate records from the active
`gmsv/data/map/mapwarp.txt:2746,2748,2749,2751,2801`; the world importer compares
these with the original create suffix before attaching `requires_time`,
`time_source`, and `time_source_line`. Missing/mismatched source gates fail closed.
Other suffixes remain evidence only (`source_time_suffix`). Old unsuffixed doors
and return portals are unchanged. Reimport world assets after activating this
manifest contract; this foundation itself does not register the dream module.

## Source and runtime

The source chain is `_MAP_WARPPOINT` in `include/version.h:219`,
`map/map_warppoint.c:34–40,100–101,211–220`, and `map/readmap.c:916–923`.
Original client `netproc.cpp:2171–2185` consumes the event field and
`map.cpp:2955–2976` checks A/M/N. This establishes the local source behavior,
not the behavior of an unavailable historical executable.

`handletime.c:55–73,100–115` uses epoch 912771809 and 5400 real seconds per
1024-hour day. Integer division/remainder retain C truncation toward zero.
M is 700<h<=930, evening 200<h<=300, N is 300<h<=700, otherwise noon.
A accepts noon or evening. The separate TimeMan AFTER predicate is 126<h<300.
`OriginalWorldClock.clock` is one server-owned callable shared across characters;
only tests replace it. No command field supplies time or phase.

Backend passage authorization and actual map arrival both validate the currently
occupied source portal, current server phase, and original destination cell.
The second check prevents crossing a phase boundary after authorization. Rejected
arrival emits the authoritative old position to repair a client's speculative
map load. Existing server-issued quest travel receipts retain their protocol;
route helpers must not authorize destinations beyond the original gates.

Party follows use an internal Backend method called by ProfileHub after the
leader's accepted move. The client string `client: "party"` provides no authority.
No save schema changes, NPC flags, item transactions or party settlement changes.

The two final battle sources `400/sb_muge1.arg` / `400/sb_muge2.arg` have an empty
`start msg:` spelling. Only that empty field in those two scripts is accepted;
nonempty/other-script variants are rejected. Ten source enemy positions remain
unchanged; both maps' victories Warp to map 41, respectively (34,39)/(33,39).

## Verification

`test_quest_time_gates.py` checks real active mapwarp records against create
portals, strict source coverage, mismatches, and unchanged other door metadata.
`original_time_passage_test.gd` covers signed epoch/day edges, every phase edge,
the distinct AFTER interval, all five gates, bad source/destination, clock changes
between requests, fake party/hour fields, unchanged returns and real two-socket
Backend commands. This does not claim four TimeMan rendering or complete dream
route/UI acceptance; those still require their next slices.

Validation for this slice: 26 Python source/import tests passed; the dedicated
real Backend/two-socket/party suite passed without script errors. Existing sea
passage and quest helper suites passed. `lan_party_test` reports zero failed
assertions but has `remote_players.gd:96,226` freed-instance script errors. The
same errors reproduce with all four changed runtime files restored to HEAD
(`bonus-time-party-baseline.log`), so that suite is not reported as passing and
its independent UI lifecycle fix was escalated to the parent.
