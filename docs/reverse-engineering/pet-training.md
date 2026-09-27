# Pet training: restored subset

Visit the **超级饲育员** in Samgir's pet shop, map **1003 (18,13)**. Talk across the counter from (18,15). Bring a captured pet and the original fee.

| ID | Skill | Fee | Executable source behavior |
|---|---|---:|---|
| 3 | 破除防御 | 1,500 | Attack without the target's normal guard reduction |
| 10 | 连续攻击 | 2,000 | Two attacks; original `gDamageDiv` divides damage by the number of attacks |
| 50 | 背水之战其之１ | 2,000 | Attack +25%, defence −35%, truncating each adjustment separately |

Prices and IDs come from `gmsv/data/petskill.txt`. The description of skill50 contradicts its executable arguments; use `攻%+25 防%-35`. The trainer's `skill_rate:1.0` and availability come from `gmsv/data/npc/genout/psks_1003_18_13`; actor16047, direction4 and coordinates come from `shop_m.create:78`.

## Presentation and authority

Original client `system/login.cpp:9443` dispatches skill shop screens. The first screen uses artwork **26139**, 432×428, with skill rows at (32,116), 21px spacing; the pet selection is a 7×5 tile stone window. Skill selection, pet selection and final confirmation retain this sequence. UI uses sounds202/203; unaffordable selection uses220. Purchase validates the current trainer location, available skill, pet, fee and battle state. Duplicate purchases cannot charge twice. Learned skills persist with the pet.

This subset permits three learned melee skills. Original skill-slot replacement and the trainer's other skills (status ailments, cooking and synthesis) remain unimplemented. Confirmation uses the original 8×2 tile window and yes/no assets26094/26095. Do not claim complete original training UI parity.

## Import and check

After importing the world, run `tools/import_pet_training.py CLIENT_SOURCE` with the asset Python environment. This extracts26139/16047 and appends the original trainer entry. Re-run after a full world import.

Run `scripts/run.sh --headless --script res://tests/pet_training_test.gd`. It checks original prices/layout, insufficient funds, confirmed purchase, duplicates, remote refusal and modal closure. All test launches remain muted. A rendered check is available with `--script res://tests/pet_training_test.gd -- --capture`, producing `/tmp/pet-training-original.png`.
