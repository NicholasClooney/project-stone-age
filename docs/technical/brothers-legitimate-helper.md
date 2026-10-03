# Five brothers legitimate helper navigation

The helper preserves the actual source sequence: original entrance 300 → 31701,
all question floors, papers → crystal, REQUEST31, original floor gate, one of
five final guards. The first/fourth corridors return to map 300 and the
second/third to floor 31705 (ev28.create:367–430); only the fifth corridor
uses 14/15,60 → 14,5 (439–448) into the reward hall. All five pet choices
remain available there: reward choice is not a matching guard number.
The enabled `_MAP_WARPPOINT` table independently agrees at
`gmsv/data/map/mapwarp.txt:2057–2066`; no convenience exit is substituted.
The fixture keeps all five guard and pet assertions: it obtains the original
papers/crystal once, walks guards1–5 and their four decoy exits in order, then
uses the fifth corridor. At the legitimate hall, alternative reward cases
restore only the actual pre-reward profile; they never assign arrival proof.
See golden-legitimate-helper.md for the split targeted suite coverage.
REQUEST31 is not gated on a prior final victory. Arrival marks and successful-save
commit rules belong to the existing server arrival policy, not this helper.

Outside the cave, the root guidance returns a public map-300 point adjacent to
the original entrance with an empty target NPC ID. Inside, helper navigation is
only a no-op at the current NPC interaction position, with a current source
branch and valid server arrival/action policy. Other steps are instructions,
not distant cave destinations. Raw old reward IDs and stale quest steps cannot
teleport into the reward hall. Restart clears arrival authority as before.

The named cache key uses the current brothers map and nearby static NPC IDs,
not a deep copy of the full active catalog on every walking report. Existing
adult, other cave, and golden helper dispatches remain separate.

Targeted coverage: the original full five-pet/save-failure/two-device assertions
remain in brothers_golden_quests_test; two actual WebSocket connections
also check original REQUEST28, superseded tokens and denied raw reward travel.
Helpers add public-entry, unchanged-near
position, stale-step and restart rejection assertions. The remote UI driver
sends actual report_position commands across the original maps before clicking
source dialogues. Golden return fixtures are still explicit isolated source
fixtures, pending the separate golden arrival adaptation.
