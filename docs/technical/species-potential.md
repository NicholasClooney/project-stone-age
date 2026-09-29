# Species potential data

`client/data/species_potential.json` holds, for every pet template, the Lv.120 stats of a **full-grade** pet (all four growth weights +2) trained from capture to 120. 宠物大全 ranks and describes species with it; the game only reads the file and never simulates.

## Regenerating

```sh
python3 tools/build_species_potential.py            # 1,000,000 pets per species and basis, all cores
python3 tools/build_species_potential.py --pets 20000 --output build/test.json   # quick check
```

It compiles `tools/species_potential.c` to `build/species_potential`, feeds it the pet templates of `client/assets/legacy/encounters/catalog.json` and writes the JSON (one species per line). The later album pets have no original stats (`stats_known` false, [8.0 pets](../reverse-engineering/pets-8.0.md)) and are skipped, so the file still has 459 species. Pass `--jobs 6` on a machine that is also running the game. A full run took about 4 minutes on 14 cores (2026-09-29, busy machine). Rerun after re-importing encounters; commit the result.

## Rules

`species_potential.c` generalizes `tools/pet_quality_tail.c` and uses the integer rules of `client/server/progression.gd` and `encounter_catalog.gd`:

- birth: weights +2 each, 10 points placed at random, base = points × (initial + (L − 1) × wild_growth) for a pet caught at level L;
- growth rank from the template's weight sum (≥100, 95, 90, 85, 80 → 0 to 4, else 5), roll 450 + 20·rank to +50 percent;
- each level up to 120: 10 random points, base += (weight + extra) × roll / 100;
- `derived()` for HP, attack, defence and speed.

Two bases per species: `lv1` (caught at Lv.1) and, when the species' lowest ordinary wild catch level is above 1, `wild` at that level. The lowest level uses the hunt's area and group filter (`pet_hunt_rules.gd` candidates). Each basis is split into 16 chunks with fixed seeds, so the result does not depend on the process count. The random generator (xoshiro256**) is not Godot's; the distribution is the same.

## Fields

Per species (template id): `wild_level` (lowest wild catch level, 0 if none) and `lv1` / `wild` with `pets`, `level`, `mean_sum`, `mean_attack`, `mean_defence`, `mean_speed`, `mean_hp`, `median`, `top10`, `top1`, `top01` (三围合 percentiles: the largest value at least that share of pets reach), `max` (sample maximum), `top1_attack`, `top01_attack`.

## Check

Blue dragon (template 92), Lv.1, 1,000,000 pets: mean 616.79, attack 288.83, top 1% 621, top 0.1% **622**, max 625. [Pet quality](../game-systems/pet-quality.md) gives 616.8 / 621 / 623 from 20,000 pets; its 400-million-pet tail (≥622 is 0.49%, ≥623 is 0.086%) puts the 0.1% point at 622, as here. `pet_encyclopedia_test` also grows 200 pets with `progression.gd` itself and checks the mean against the file.
