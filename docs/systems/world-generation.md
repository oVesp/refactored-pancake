# World generation (Midgard terrain)

Code: `tools/terrain/` (offline Lune generator), `src/ServerStorage/WorldGen/Apply.luau` (Studio applier), `src/ServerStorage/WorldGen/Data/` (generated, do not hand-edit). Tests: `tests/specs/WorldGen.spec.luau`.

## Workflow

1. Tune `tools/terrain/lib/Config.luau`.
2. `lune run tools/terrain/build` (about 2 minutes) regenerates `Data/` and writes `build/terrain-preview.ppm` (top-down height and material preview, one pixel per 8 studs).
3. In Studio, Edit mode: `require(game.ServerStorage.WorldGen.Apply).Apply()`. Use `ApplyTerrain()`, `ApplyScatter({ "Trees" })`, `ApplyPois()` or `Clear()` for partial runs. A full apply takes several minutes; run it in a spawned task. Save the place afterwards.
4. When regenerating, also update the `worldgen:*` rows in `content/register.json` if the file list changed.

Output is deterministic: the same seed and Config give the same bytes in Lune and in Studio.

## World

- 10,240 × 10,240 studs: a 5 × 5 grid of 2,048-stud tiles. Data is 1,280 × 1,280 columns of 8 studs, origin X=-5120 Z=-5456. The centre tile holds the gameplay areas (village, fields, orchard, goblin camp). Terrain is the only ground: the Map has no ground slabs or baseplate.
- Floor at y=-80, sea level y=-3, seed `20261024`.
- Regions (`Config.world`) blend in over about 1,000 studs with noise-warped borders:

| Region | Where | Relief | Biomes |
|---|---|---|---|
| Start valley | centre | valley along the zones, creek and lake; hills around | Meadow, MixedForest, PineForest, WetForest, Bog, Ridge |
| Highlands | z -1400 to -2300 | hills 1.5× and lifted 60 studs | Heath, PineForest |
| Mountains | north of z -2400 | ridged peaks up to about 560 studs | Alpine (snow above about 360, glacier above about 460), Ridge |
| Swamp | west of x -2000 | flat, pools below sea level | Swamp, Bog |
| Plains | east of x 2100 | low rolling ground | Plains (groves), WetForest along the river |
| Coast | south of z 2300 | slopes to a sea floor at -42 | Beach, sea |

## Pipeline (`build.luau`)

1. **Layout** (`Layout.luau`): pads from the `Map.Zones` volumes and prop blockers from `src/Workspace/Map.rbxmx`, the village-to-camp road from `Config.roads`, the lake, river splines (`Config.water.rivers`: the Creek through the start valley and the Eastwater from the northern mountains to the sea), and the region weights.
2. **Heightfield** (`Heightfield.luau`): start-valley corridor, fBm hills reshaped per region, the north ridge behind the goblin camp (open past |x| 1300 as passes), ridged mountains, raised north/east/west edges, domain-warped detail, the coast falling to the sea floor.
3. **Erosion** (`Erosion.luau`): droplet hydraulic erosion (0.5 droplets per cell), then thermal talus at 38°, masked off pads, rivers, the lake, the sea and the swamp.
4. **Water** (`Water.luau`): each river is carved with a downstream-monotonic surface; the lake, the sea and swamp pools fill to sea level (ground below sea level elsewhere stays dry). Flow accumulation by Priority-Flood plus D8.
5. **Pads** flattened to `padHeight` (0.2, the Map ground level) with a feather, so buildings and props sit flush.
6. **POIs, sites and roads** (`Paths.luau`): two lookouts beside the start valley; one flat site per region (`SiteHighlands`, `SiteMountains`, `SiteSwamp`, `SitePlains`, `SiteCoast`, radius 48) for later towns and dungeons; A* trails in the valley and 14-stud roads from the valley to each site. All markers are tagged `PoiSite`.
7. **Biomes and materials** (`Materials.luau`): 12 biomes from region, height, slope, moisture and noise; materials Grass, LeafyGrass, Ground, Mud, Sand, Rock, Slate, Pavement, Snow, Glacier, Sandstone. Each zone gets its own material (`Config.padMaterials`) with a ragged edge, and roads are painted Ground.
8. **Scatter** (`Scatter.luau`): Bridson Poisson-disc per layer (Paths, Trees, Rocks, Understory, Cover, Pebbles), weighted asset groups per biome, slope limits, sinking and normal alignment. Canopy trees run at about twice pack size and may interlock (`canopyOverlap`); plains, heath and swamp trees gather in groves (`clump`).

## Prop budget

The whole world at start-valley density would be several hundred thousand props. Ground cover and pebbles appear only within `detailNear`..`detailFar` (1,200 to 2,200 studs) of the start; understory thins to a quarter outside it; trees drop to `outerTrees` (60%) and rocks to `outerRocks` (35%) far from the start. Terrain grass decoration covers the rest. Current output: about 117k props (44k trees, 35k rocks, 21k understory, 10k cover, 6k pebbles).

## Applier (`Apply.luau`)

- Terrain written with `WriteVoxelChannels` in blocks of 64 × 64 voxel columns (256 studs), yielding between blocks. The 8-stud data is upsampled to 4-stud voxels: heights and water bilinear, materials by a hashed pick among the four neighbouring cells. Each block fills from 24 studs below its lowest column (never below `floorY`) to keep mountain writes small. `MaterialColors` set to the palette.
- Props cloned from the Nature MEGAPACK in `ServerStorage`, re-pivoted to their bounding-box bottom centre, anchored, scripts stripped; collision on trunks only for trees, off for cover.
- Placed under `Workspace.Nature/<Layer>/<256-stud chunk>`. Anything marked `Locked` or tagged `ScatterExclude` survives a re-apply.

## Data format

- `Meta.luau`: world constants, material palette, asset list, layers (each with its module list and prop count), POIs and sites.
- `Terrain01`–`40`: 32 rows each, base64 of 5 bytes per column: u16 height `(h+128)*16`, u8 material, u16 water surface (0 = dry).
- `Scatter<Layer><band>`: props in 2,048-stud bands along Z, one line per prop: `assetIdx x y z yaw ux uz scale`.

## Owner toggles (not scriptable)

- Expanded Terrain and `Terrain.Decoration` (animated grass on Grass) are Studio settings; both are on in the place (2026-10-24).
