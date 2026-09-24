---
name: sorcmerc-compat
description: Keeps SorcMerc's co-op lockstep and its modding API stable through heavy feature work. Use BEFORE and AFTER any change that touches combat state or resolution (core/combat.gd, combatant.gd, ai.gd, encounter.gd, a new verb kind, status, pool or reaction), party/character serialization (character_save.gd, party.gd, coop.gd), or anything a content pack can write (data/*.json and data/effects/*.json schemas, Effects.KINDS/VERB_KEYS/REACTION_TRIGGERS, Quest.KINDS, story conditions/effects, world.json keys, manifest fields, catalog ids, factions, bands, themes). Says what must never break, which checks prove it, and how to extend each safely.
---

# SorcMerc compat: co-op lockstep and the modding API

Two promises outlive any feature:

- **Two co-op peers stay in lockstep.**
- **A content pack written against an API level keeps loading.**

Neither promise is visible from the feature you are building, so both are held by checks. This skill says what those checks are for, and what to do when one fails. `docs/spike-coop.md` and `docs/modding.md` are the long forms.

## The checks (all in `tools/run_tests.sh`, so CI runs them)

| check | holds |
|---|---|
| `tests/test_coop.gd` | Lockstep on the preset party over 40 seeds, with reaction prompts, objectives, a late joiner replaying the log, and a guest level-up |
| `tests/test_coop_kits.gd` | Lockstep for **every class and subclass** at levels 4 and 8. Every button crosses the wire, and the hash agrees after each intent. The drift detector is itself tested (a pool or a status payload alone is a drift). A refused intent changes nothing. |
| `tests/test_mod_api.gd` | The modding API snapshot (`tests/fixtures/mod_api.json`): vocabulary equal, documented in `docs/modding.md`, no id removed. The API-1 canary pack (`tests/fixtures/mods/api-canary/`) loads, applies and plays. |
| `tests/test_mod_packs.gd`, `test_world_pack.gd`, `test_story.gd` | The pack pipeline, maps and stories, including the shipped packs under `content/` |

Run them together while working:

```sh
tools/run_tests.sh tests/test_coop.gd tests/test_coop_kits.gd tests/test_mod_api.gd tests/test_mod_packs.gd
```

## Co-op: what lockstep needs from your change

Both peers build the same `Combat` from one setup (seed, spec, party as `CharacterSave` dicts) and apply the same intents in the same order. Only intents cross the wire (`Coop.perform/move/end_turn`), and `Coop.state_hash` must agree after every one. So:

1. **Every roll comes from `cb.rng`.** Never use `randi()`, `randf()`, `Time` or `hash()` of an object in anything a fight resolves. Cosmetic randomness (barks, camera) must use its own stream and never touch `cb.rng`.
2. **A refused intent changes nothing.** If `perform()` would return an error, it returns it **before** spending anything; `Combat._cast_refusal` is the pattern. The harness drops a refused intent unsent, and the AI re-plans after one.
3. **New fight state must be hashable and in the hash.** `state_hash` covers the rng, the turn, positions, HP, the economy, **pools** and every status **payload**.
   - A payload may hold a Combatant: `_plain()` writes it as its id. It must not hold a Callable, a Node or a float taken from the clock.
   - New state kept outside `statuses`, `econ` or `pools` must be added to `state_hash`, or drift in it is invisible.
4. **A new verb needs a stable, unique id.** Intents name verbs by id (`Coop.apply` finds `v["id"]` on the hero). Two verbs sharing an id on one hero is a desync. `test_class_abilities` and `test_coop_kits` both check uniqueness.
5. **A new Character field travels with the party.** The guest rebuilds the party from `CharacterSave.to_dict`. A field missing from `to_dict`/`from_dict` differs between peers. The `slots_used` bug of 2026-09-20 was exactly this.
6. **Anything the fight reads from the party must be in the setup.** Relations and callings ride in `Coop.setup_for` because the fight reads them. A new party-level input to combat goes there too.
7. **Process-global state (`static var`) is per peer.** Both peers must reach the same value by the same path; never let one screen set it.

When `test_coop_kits` fails, it names the intent it drifted on. Reproduce it with `tests/coop_harness.gd`, then diff the host's and guest's `econ`, `pools` and `_plain(statuses)` at that intent.

## The modding API: what a pack is promised

`core/mod/manifest.gd` `API := 1`. **A pack at or below this level loads, now and always.**

- **Adding vocabulary is free, if documented.** New effect kinds, feature keys, quest kinds, story keys, data files, factions or bands:
  1. Write the new term into `docs/modding.md`, in the section a pack author reads.
  2. Regenerate the snapshot:
     ```sh
     SNAPSHOT_WRITE=1 godot --headless --path . -s tests/test_mod_api.gd
     ```
  3. Commit `tests/fixtures/mod_api.json` with the change.
- **Removing or renaming vocabulary is a break.** Don't, if a compatible path exists: accept the old name and map it to the new one. If it is unavoidable:
  1. Bump `Manifest.API`.
  2. Keep reading the old form for lower-API packs.
  3. Write the migration into `docs/modding.md`.
  4. Regenerate the snapshot.
- **Ids a pack may name are never removed silently.** That covers spells, bestiary and monsters, items, classes, subclasses, species, backgrounds, feats, conditions, weapons, armor, and the effects keys. Renaming a monster strands every pack that spawns it. Add a new id, and retire an old one only as a break.
- **Packs are data, and only data.** No new feature may make a pack need code. If a mechanic should be moddable, it belongs in the closed vocabulary with a validator error for a typo. A silent dead-end is the worst failure a data format can have.
- **The canary is a third party's pack.** Never edit it to make a change pass; that is exactly the failure it exists to catch. Extend it when you add vocabulary a pack should be able to use.

## Checklist for a heavy feature PR

- [ ] New combat state: in `statuses`, `econ` or `pools`, or added to `Coop.state_hash`; no Callables or clock values in payloads.
- [ ] New verbs: unique ids; `perform()` refuses before spending; `test_coop_kits` passes.
- [ ] New Character or party fields: in `CharacterSave` / `Coop.setup_for`, and they default when missing.
- [ ] New pack vocabulary: documented in `docs/modding.md`, snapshot regenerated, canary extended if it matters.
- [ ] Nothing removed or renamed that a pack can write or name, unless it's a declared API bump.
- [ ] `tools/run_tests.sh` green, which includes all of the above.
