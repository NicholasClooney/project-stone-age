# Public corridor expansion audit

Base: b5ec513c. Original source revision: 0c58fb6683a49a178a8ad845a8c296c2cb83bd81.
`source-table.json` retains all 37 candidates, exact original link identities and source hashes. Original create blocks were rechecked; map hashes are importer provenance, not a separate map-file rehash. `geometry-rows.md` and `geometry-results.json` retain every accepted/rejected candidate and observed original A path length/outside cell.

29 new directional lanes pass geometry, alongside 7 unchanged lanes: 36 implementation candidates. New lanes cover maps100 (14),200 (14),5000 (1). This is an exact source/geometry list, not map-wide acceleration permission. An original door remains a separate walk/portal; five portal starts must first walk off the arrival cell. Restricted doors, approaches, dynamic occupation and changed source links cannot authorize fast travel. Existing executor and A planner are unchanged.

Validation already completed serially: geometry113 assertions/0 failures/2.529s; production audit/validate/next_segment interfaces555/0/25.807s. Interface proposals are24 stride/5 walk, not task benefits. The five truthful walk results are sea-goya, goya-karutana, goya-jaja, sea-tamutamu, karutana-phoenix. Do not change A to force a match. An earlier interface fixture failure used stale NPC occupancy; its correction uses normal npc_state.moved/refresh and asserts no residual block after restoration, with no production cache changes.

At this handoff only seven NEW lane identities have actual execution evidence (prefix public-v2-): yam-mati, mati-yam, jaja-goya, mati-marju, marju-mati, marinas-kou, yam-samgir. Execution suites/evidence are a separate follow-up commit. Jobs12/13/24/5/9 have actual B/C new-lane hits and original completion transactions; jobs1/11/30 only have incremental approach coverage here, not repeated complete legacy chains. Continuous job25 remains wholly protected with both new and old fast counts zero. An independent player-initiated public-start25 case is still pending. No claim is made that all29 lanes have real task execution coverage.

Eight map300 candidates remain excluded: forde-miner, forde-golden, forde-brothers, miner-forde, golden-forde, brothers-forde, forde-jiru, jiru-forde. Original A geometry produced no usable public path/prefix; the deeper cause is unresolved. B must not mask that failure. Script-NPC public approaches remain A. The map300 outer approach pocket,10202 permit gates, cave/maze interiors and original scripted transitions remain protected.

Fixed equal-NPC-world A/C compatibility is distinct from earlier uncontrolled-world diagnostics. Two uncontrolled comparisons failed at index362; each followed its own initial A path. Later input logging found unequal NPC occupation, but does not reconstruct the old failure's complete cause. These diagnostics must not be registered as passing formal suites. Wall times are test costs; logical movement and simulated time are separate evidence. Protected-time microdifferences are not speedup claims.

Integration owns suite registration and the final full run. This candidate commit does not publish the expansion to main/live.
