# 1st Game (Godot 4.6)

Idle / automation prototype: authored grid map, manual gathering first, then machines and power in small vertical slices.

## Folder structure

| Path | Role |
|------|------|
| `project.godot` | Project settings; `GameState` autoload; main scene entry |
| `scenes/main.tscn` | Main UI: map (left) + panel (right) |
| `scripts/main.gd` | Binds labels/buttons to `GameState` |
| `scripts/game_state.gd` | Autoload: resources, map, chop/regrow, crafting, JSON save/load |
| `scripts/map/world_map.gd` | `WorldMap` class: cell enum, ASCII → grid, starter + expanded layouts |
| `scripts/map/map_grid_view.gd` | `TileMapLayer` + Kenney sheet; forwards clicks |
| `scripts/map/tiny_town_atlas.gd` | `TinyTownAtlas`: path to `tilemap_packed.png` + `WorldMap.Cell` → atlas coords (edit sprites here) |
| `kenney_tiny-town/Tilemap/tilemap_packed.png` | CC0 atlas (12×11 @ 16px); used at runtime |

## Current behavior

- Map visuals use **Kenney Tiny Town** (`tilemap_packed.png`, 2× scale). Swap sprites by editing `TinyTownAtlas.ATLAS` in `scripts/map/tiny_town_atlas.gd` (each value is atlas column/row).
- Starter map: grass, **home** (`H`), **river** (`~`), **trees** (`T`); click trees for wood (manual multiplier vs base chop).
- Stumps regrow to trees after a timer.
- Small passive wood from “home” (placeholder for later crafting/base rules).
- **Expand territory** spends wood and appends a strip with **quarry** and **copper mine** tiles. **Quarry:** click grey tiles for **stone** (per-tile cooldown). Copper mine is still visual-only.
- **Crafting (home):** convert wood into **planks** (`PLANK_WOOD_COST` wood -> `PLANKS_PER_CRAFT` plank) from the side panel button.
- **Automation prototype:** craft/place **water wheels** on river, build **shaft lines**, and place **harvesters** on grass next to powered shafts for passive wood gain.

### Balance (edit in `scripts/game_state.gd`)

| Constant | Default | Notes |
|----------|---------|--------|
| `WOOD_PER_CHOP_BASE` | `2.0` | Multiplied by `MANUAL_WOOD_MULT` for clicks. |
| `MANUAL_WOOD_MULT` | `2.5` | Manual chop = **5** wood at defaults. |
| `TREE_REGROW_SEC` | `24.0` | Stump → tree. |
| `HOME_PASSIVE_WOOD_PER_SEC` | `0.05` | Idle drip from home. |
| `EXPANSION_WOOD_COST` | `100.0` | First territory expansion (~20 chops if wood only from trees). |
| `STONE_PER_MANUAL_GATHER` | `1.0` | Stone per successful quarry click. |
| `QUARRY_COOLDOWN_SEC` | `2.0` | Same quarry tile cannot be mined again until this elapses. |
| `PLANK_WOOD_COST` | `8.0` | Wood spent per plank craft. |
| `PLANKS_PER_CRAFT` | `1.0` | Planks gained per craft action. |
| `SHAFT_KIT_PLANK_COST` | `2.0` | Planks spent per shaft kit craft. |
| `SHAFT_KIT_STONE_COST` | `1.0` | Stone spent per shaft kit craft. |
| `SHAFT_KITS_PER_CRAFT` | `1.0` | Kits gained per craft action. |
| `WHEEL_KIT_PLANK_COST` | `3.0` | Planks spent per water wheel kit. |
| `WHEEL_KIT_STONE_COST` | `2.0` | Stone spent per water wheel kit. |
| `HARVESTER_KIT_PLANK_COST` | `4.0` | Planks spent per harvester kit. |
| `HARVESTER_KIT_STONE_COST` | `3.0` | Stone spent per harvester kit. |
| `HARVESTER_WOOD_PER_SEC` | `0.8` | Passive wood per powered harvester. |

### Save / load

- **File:** `user://save.json` (Godot resolves this under the editor/player [user data folder](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html) for the project).
- **Contents:** format `v` (**5** = current): `wood`, **`stone`**, **`planks`**, kit counts (`shaft/wheel/harvester`), placed object cells (`shafts/wheels/harvesters`), `territory_expanded`, full `world_map` cell grid, stump `regrow`, **`quarry_cd`** cooldowns. Saves with `v: 1..4` still load; missing fields default safely.
- **When:** load on startup; save after chops, quarry mines, and expansion, and on quit (`_exit_tree` on `GameState`).

## First implementation steps (do in order)

Use this as a checklist; stop each step when it feels playable before moving on.

1. ~~**Stabilize the core loop + save/load**~~ — Done (balance constants + JSON persistence).

2. ~~**Kenney Tiny Town tile visuals**~~ — `TileMapLayer` + `tilemap_packed.png`; project uses **nearest** canvas texture filter (`project.godot`).

3. ~~**One new resource, one interaction**~~ — Done: **stone** from **quarry** clicks (`GameState.try_mine_quarry`), per-tile cooldown, UI label, persisted in save `v: 2`.

4. ~~**First crafting action (home)**~~ — Done: wood -> planks button + persistence.

5. ~~**Second recipe + first placeable object**~~ — Done: shaft kit crafting + grass-only shaft placement mode.

6. ~~**Automation prototype**~~ — Done: wheel -> powered shafts -> harvester passive wood.

7. **Player inventory vs world**  
   - Decide: everything in `GameState` scalars vs a small `Inventory` resource.  
   - **One shared storage** building can wait until items and UI lists exist.

8. **First machine, one power type**  
   - **Water wheel** on river + **wooden shaft** in straight lines only → powers **one** consumer (e.g. wood harvester OR pump).  
   - Rules: place/break, validate straight shaft, show “powered” state on tiles. **Defer electricity and wire** until this feels good.

9. **Machine I/O (minimal)**  
   - Machine has internal buffer + output rate; player or a single haul method empties it.  
   - **Either** conveyors **or** drones first—not both.

10. **Second power / logistics tier**  
   - e.g. copper → wire → underground power **or** expand shaft rules—only after step 5 is fun.

11. **Factory building & recipes**  
   - Unlock “factory” scene/UI; faster machine crafting than home.  
   - Recipe data as arrays or `.tres` resources so you do not hardcode everything in `GameState`.

## Future ideas (backlog)

_Not committed order—pull into “First steps” when ready._

- Water: collect from river; well/pond tiles; **pump** requires electricity; infinite source with **throughput** from machinery tier.
- Seeds (~5% on chop): new tree plots vs regrow-in-place (you already have regrow).
- Copper: mine tile + manual wire crafting (slow) → machine wire; wire = power transmission under tile.
- Solar (no storage) + **power plant** as battery; water wheel charges battery when shaft-linked.
- Buildings: **storage site** (shared cap), **player home** crafting only (or remove passive wood if redundant).
- Digger / miner / automaton / drones—each with **one** clear job first.
- Map **seeded** generation after authored maps feel done.
- Prestige or meta upgrades if the loop runs long.

## Running

Open the folder in **Godot 4.6** (matches `config/features`) and run the main scene (`F5`).
