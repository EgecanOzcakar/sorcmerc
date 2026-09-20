# content/

Content packs that ship with the game. Same format, same loader and same
validator as anything a player drops in `user://mods/` — see
`docs/modding.md`, which is the authoring guide for both.

| Pack | What it is |
|---|---|
| `example-world/` | a map and nothing else: the shortest thing that is a working pack. Copy this to start one. |
| `ashen-road/` | a free three-chapter campaign with its own map, cast, quest chain, monsters and items |
| `vault-of-the-ember-crown/` | a paid DLC, and the thing that keeps the paid path honest: it is gated by `core/mod/entitlement.gd` like any other, and is locked in a normal build until it is owned |

Packs found here are marked **official** by the registry — from the root they
were discovered in, never from anything a pack can write about itself.

To see the paid one while working: `SORCMERC_UNLOCK_DLC=1`, or any build with
the `playtest` feature.
