# World generation (Midgard terrain)

Code: `tools/terrain/` (offline Lune generator), `src/ServerStorage/WorldGen/Apply.luau` (Studio applier), `src/ServerStorage/WorldGen/Data/` (generated, do not hand-edit). Tests: `tests/specs/WorldGen.spec.luau`.

## Workflow

1. Tune `tools/terrain/lib/Config.luau`.
2. `lune run tools/terrain/build` regenerates `Data/` and writes `build/terrain-preview.ppm` (top-down height and material preview).
3. In Studio, Edit mode: `require(game.ServerStorage.WorldGen.Apply).Apply()`. Use `ApplyTerrain()`, `ApplyScatter({ "Trees" })`, `ApplyPois()` or `Clear()` for partial runs. Save the place afterwards.

Output is deterministic: the same seed and Config give the same bytes in Lune and in Studio.

## Tile

- 2048 × 2048 studs, 512 × 512 columns of 4 studs, origin X=-1024 Z=-1360, so the gameplay areas (village, fields, orchard, goblin camp) sit inside it. Terrain is the only ground: the Map has no ground slabs or baseplate.
- Floor at y=-80, water level y=-3, seed `20261024`.

## Pipeline (`build.luau`)

1. **Layout** (`Layout.luau`): pads from the `Map.Zones` volumes and prop blockers from `src/Workspace/Map.rbxmx`, the village-to-camp road from `Config.roads`, lake at (260, 330) r≈150, meandering creek on a Catmull-Rom spline from the north ridge to the lake.
2. **Heightfield** (`Heightfield.luau`): valley corridor around pads, creek and lake; fBm hills; ridged-noise north ridge (z -900 to -1250); raised edges; domain-warped detail.
3. **Erosion** (`Erosion.luau`): droplet hydraulic erosion (0.5 droplets per cell), then thermal talus at 38°, masked off pads.
4. **Water** (`Water.luau`): creek carved with a downstream-monotonic surface, lake filled; flow accumulation by Priority-Flood plus D8.
5. **Pads** flattened to `padHeight` (0.2, the Map ground level) with a feather, so buildings and props sit flush.
6. **POIs and trails** (`Paths.luau`): two flat lookouts (`PoiSite` tag), A* trails with slope and water costs, carved into the heightfield.
7. **Biomes and materials** (`Materials.luau`): Meadow, Field, MixedForest, PineForest, WetForest, Bog, Ridge from height, slope, moisture (flow, creek and lake distance) and noise; standard materials Grass, LeafyGrass, Ground, Mud, Sand, Rock, Slate, Pavement. Each zone gets its own material (`Config.padMaterials`) with a ragged edge, and roads are painted Ground.
8. **Scatter** (`Scatter.luau`): Bridson Poisson-disc per layer (Paths, Trees, Rocks, Understory, Cover, Pebbles), weighted asset groups per biome, slope limits, sinking and normal alignment. Canopy trees run at about twice pack size and may interlock (`canopyOverlap`); understory and cover only keep the trunk area clear (`trunkClearance`). About 19.7k props.

## Applier (`Apply.luau`)

- Terrain written with `WriteVoxelChannels` in 64 × 64-column tiles, yielding between tiles; `MaterialColors` set to the palette.
- Props cloned from the Nature MEGAPACK in `ServerStorage`, re-pivoted to their bounding-box bottom centre, anchored, scripts stripped; collision on trunks only for trees, off for cover.
- Placed under `Workspace.Nature/<Layer>/<256-stud chunk>`. Anything marked `Locked` or tagged `ScatterExclude` survives a re-apply.

## Data format

- `Meta.luau`: tile constants, asset list, POIs, trails.
- `Terrain01`–`16`: 32 rows each, base64 of 5 bytes per column: u16 height `(h+128)*16`, u8 material, u16 water surface (0 = dry).
- `Scatter<Layer>`: one line per prop: `assetIdx x y z yaw ux uz scale`.

## Owner toggles (not scriptable)

- Expanded Terrain and `Terrain.Decoration` (animated grass on Grass) are Studio settings; both are on in the place (2026-10-24).
