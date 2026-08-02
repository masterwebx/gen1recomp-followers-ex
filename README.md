# Followers EX

Control modes, pack size, party/BOX LEADER, and Wilds of Kanto overworld sprites that use PokéPC follower walk sheets.

## Requires

- **PokéPC Followers Voxel Merge** (`PokePCFollowers_VoxelMerge`) — public stub is enough for sprites; Followers EX embeds the control/pack/trailer engine.
- **Wilds of Kanto** (`overworld_wild_spawns`) — public release is enough; Followers EX adds town spawns + reachable-tile filter.

Optional: Shiny Pokemon for sparkles on followers/wilds.

## OPTIONS

Pause **OPTIONS → FOLLOWERS EX → OPEN**:

- **CONTROL MODE** — TRAINER or POKEMON
- **TRAINER FOLLOWS** — YES puts you on the Pokemon with the trainer trailing
- **FOLLOWERS** — how many party mons trail (0–6)
- **SHOW IN MENU** — Start menu entry **FLL EX** (default off)
- **WILDS SPRITES** — wild overworld mons use follower sheets
- **TOWN SPAWNS** — wilds in towns (borrow route grass / default)
- **REACHABLE ONLY** — only tiles the player can walk/surf/ledge to
- Voxel tall-grass lift for wild billboards (so stock Wilds does not need a local patch)

## Party (leader only)

Active mode is hidden. Remaining choices:

- **LEADER** — set this party mon as leader (hidden if already leader)
- **TRAINER** / **BE MON** / **+TRAINER** / **PACK N** (◀▶ changes N)

## Bill's PC

**BOX LEADER** — pick a boxed mon as overworld leader (above PRINT BOX / SEE YA).

## License

MIT
