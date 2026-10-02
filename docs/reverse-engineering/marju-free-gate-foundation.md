# Marju original free gate

`genout/meiro.create:167` binds `npcgen_warpman|file:genout/wpm_120_19_15`.
Declare `handlers:{"genout/wpm_120_19_15":{kind:"warpman",events:[37,38]}}`,
SHA-pin the actual create, argument, itemset and jobdaily files as usual. The
route module must import maps 120/122 and retain the script in
`world.restored_scripts`; no scenic replacement or helper bypass is supplied.

The strict parser accepts exactly WARP, FREE, MONEY, FreeMsg, PayMsg, PartyMsg,
MoneyMsg for this subset, with `FREE:LV>49` and `MONEY:-1`. It emits a FREEWARP
branch with the original free condition, confirmation and Warp122,6,5; source
fields retain all messages and the negative sentinel. It does not emit DelStone.

Source `gmsv/npc/npc_warpman.c:228–231,560–566` refuses party membership;
`:254–268` shows FreeMsg for FREE, while `:300–309` sends PayMsg with OK only
when MONEY contains a minus sign. This is not a negative price or free pass for
an underlevel player. `:393–400` checks party again on confirmation. Runtime
uses the existing server token and candidate-profile save, checks current level
and authoritative party again, and refuses an unimported/out-of-bounds target
before committing a location that could not be loaded. No inventory cost,
reward, additional progress flag or equipment behavior is introduced.

The source fixture includes SHA-pinned actual LS2MAP120/122 header metadata for
isolated backend readback tests. Tests do not bypass profile validation. Python
reconstructs the bound source NPC and checks metadata against read_map. Real
Backend/Session tests cover 49/50, zero gold, cancel, changed level, save failure,
unimported map, successful persisted destination and token replay. Real ProfileHub
party membership changing after the offer is refused using original PartyMsg;
two sockets cannot forge the free condition and share the successful transaction.
This is the public gate interface; the route agent owns natural travel, helper,
map import and final mobile verification. No full suite was run.
