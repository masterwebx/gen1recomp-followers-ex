# Followers EX

Control modes, pack size, party/BOX LEADER. Pack, player-as-Pokemon, and Wilds OW spawns use **PokePC** walker sheets (16×96). Includes a Dramatic Shape billboard UV fix so non-walker sheets are not zoomed into their top-left 16×16.

## Requires

- [gen1recomp](https://github.com/bryanthaboi/gen1recomp) / pokemon-love2d (mod API 2)
- [PokéPC Followers](https://github.com/gamecorner-033/PokePCFollowers) (`PokePCFollowers_VoxelMerge` or compatible sprite pack) — sprites; Followers EX embeds the control/pack/trailer engine
- [Wilds of Kanto](https://github.com/YoDrehDenSwagAuf/overworld-spawn-mod) (`overworld_wild_spawns`) — 0.6.x recommended

### Optional

- [Shiny Pokemon](https://github.com/masterwebx/gen1recomp-shiny-pokemon) — PokePC sheet bake + sparkles for pack shinies
- [Dramatic Shape](https://github.com/DramaticShape/DramaticShapeVoxelMod) — voxel overworld (billboard UV fix applies when present)

## OPTIONS

Pause **OPTIONS → FOLLOWERS EX → OPEN**:

- **CONTROL MODE** — TRAINER or POKEMON
- **TRAINER FOLLOWS** — YES puts you on the Pokemon with the trainer trailing
- **FOLLOWERS** — how many party mons trail (0–6)
- **SHOW IN MENU** — Start menu entry **FLL EX** (default off)
- **TOWN SPAWNS** — ON allows wild OW spawns in towns (borrows a nearby route’s grass table)
- **GRASS LIFT** — ON = wilds above tall grass; OFF = immersed (default **off**)

Wild OW spawn tiles are always filtered to what the player can walk to (ledges count as reachable).

Wilds animated OW sprites are forced off so spawns use the same PokePC walker sheets as the pack (correct 16×16 billboard framing under Dramatic Shape).

- Yellow: setting **LEADER** always puts that mon in party slot **2**; **Pikachu stays slot 1** as the talkable companion (trainer and pokemon modes)
- Yellow **TRAINER** follow keeps the stock talkable Pikachu; other party mons trail *behind* it
- Yellow **POKEMON** / pack modes: face the party Pikachu trailer and press A for the emotion scene

## Party (leader only)

- **LEADER** — set this party mon as leader (hidden if already leader)
- **TRAINER** / **BE MON** / **+TRAINER** / **PACK N** (◀▶ changes N)

## Bill's PC

**BOX LEADER** — pick a boxed mon as overworld leader (above PRINT BOX / SEE YA).

## License

MIT
