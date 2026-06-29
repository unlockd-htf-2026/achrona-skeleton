# Achrona Challenges

Each row is one challenge: turn its one failing test GREEN to light up one node
on the shared Achrona globe. Reference version: `v1.0-reference-frozen`.

Run a challenge locally with the beginner wrapper:

```sh
./challenge <id>
```

| id | brief | file | run | track | globe node |
|----|-------|------|-----|-------|------------|
| `c1-stepy` | Make the hero move up/down: implement the single-frame vertical step (move by `dir*speed*dt`, clamp to the band). The app launches but the hero is frozen vertically until you fix it. | `test/challenges/c1_stepy_test.dart` | `./challenge c1-stepy` | Base | `node-c1-stepy` |
| `c11-desyncnetrate` | Compute the signed net Desync rate: gentle creep, recede after running clean, slowWave softens an advance but never flips a recede. | `test/challenges/c11_desyncnetrate_test.dart` | `./challenge c11-desyncnetrate` | Creative | `node-c11-desyncnetrate` |
| `c15-takeduespawns` | Drive the scripted spawner: return the spawns whose time has come (`timeOffset <= elapsed`), once each, in order, advancing the cursor. | `test/challenges/c15_takeduespawns_test.dart` | `./challenge c15-takeduespawns` | Online-Elite | `node-c15-takeduespawns` |
