# World generation (Midgard)

**Status (2026-10-28): redesign decided, not built.** The owner replaced the eroded voxel world with a stylized, vertical, zone-graph world (reference: the look of walled fantasy Roblox worlds; Kenshi for scale and variety only). Nothing below the *Target design* heading exists in code yet. Until the centre section is rebuilt, the place still holds the old output, described under *Current pipeline*.

Originality: the references give style and scale only. No layout, landmark, location name or unique feature of any referenced game is copied (game-design §2).

## Target design

### Goals

- **Perceived size over raw size.** A zone feels big because sight lines are short: cliffs, tiers and fog hide what is next. Hidden areas need something to hide behind, not more distance.
- **Verticality separates zones.** Zones sit on elevation tiers; the cliff between two tiers is the border. There is no requirement for a wall on every edge.
- **Section-by-section authoring.** One zone can be regenerated, viewed and tuned in seconds without moving any other zone.

### Size

10,240 × 10,240 studs per realm Place, **provisional**: the owner commits a final size after the first sections are played. Base walk speed is 16 studs/s, so a straight crossing takes about 11 minutes and a real route about 17.

### Layout: the zone graph

Authored data, one file per realm (`content/world/midgard.json`):

- **Nodes**: `zone` (a playable area), `pocket` (a hidden area inside or above a cliff band), `landmark`. Each has an id, biome, danger band, elevation tier, target area, and optional anchor position.
- **Edges**: how two nodes connect. Kinds: `ramp` (a path cut into the cliff), `stairs`, `bridge` (across a chasm), `cave` (tunnel through a cliff band), `drop` (one-way, down), `climb` (needs a climbing mechanic, see open questions), `open` (same tier, no cliff). `secret: true` marks an edge with no visual signpost.

Same-tier neighbours may share an open border; neighbours on different tiers always meet at a cliff band.

### Generation stages

Each stage is a pure Luau module shared by Lune and Studio, seeded per zone (`hash(worldSeed, zoneId)`) and per border (`hash(worldSeed, lowId, highId)`), so rebuilding one zone never shifts another.

1. **Placement**: graph to 2D. Anchored nodes stay put; the rest settle by a force layout, then cells are cut as a power diagram weighted by target area and clipped to the world. Pockets are placed inside the cliff band of their parent edge.
2. **Elevation**: each cell gets its tier height plus low-amplitude noise. Borders between tiers become cliff bands (polylines with a width). Edges carve their crossing into the band: ramps and stairs as switchbacks, caves as tunnels, bridges across gaps.
3. **Floors**: voxel terrain heightfield for walkable ground (grass, paths, water), written with the existing `WriteVoxelChannels` writer. Cliff bands are filled with Rock voxels under the parts so no gap shows.
4. **Cliffs**: a procedural Part kit along each cliff band. Each band segment is a column of 2 to 5 stacked blocks (20 to 120 studs, yaw jitter about ±8°, tilt about ±4°) in the biome's rock material and palette, with a thin grass cap that overhangs the top face. Shelf blocks form ledges, which is where pockets and climb routes live. Plain Parts only, no unions. Budget: about 1,500 cliff parts per zone, tuned after profiling.
5. **Props**: see below.
6. **Mood**: each zone names an atmosphere mood; the atmosphere controller blends by zone instead of by region band.

### Props: procedural low-poly at low cost

Built for performance first:

- **Few, large props.** Trees 40 to 150 studs tall cover the same ground with a fraction of the instances.
- **Variant library, not per-prop geometry.** A seeded offline generator (headless Blender script) makes about 16 to 32 low-poly variants per biome (bent trunk, 3 to 7 faceted canopy slabs, about 400 triangles or fewer), imported once in Studio. Every placed prop is a clone of a variant, so identical mesh and material render as one instanced batch.
- **Two instances per tree at most**: a trunk with box collision and a canopy with no collision and `CanQuery` off. Single MeshParts, no Model.
- **Clustered scatter with a per-zone budget**: groves and clearings instead of uniform cover, Poisson-disc inside clusters.
- **Distance**: engine streaming, client culling (`PropDetail`) and fog as the far plane stay as they are.
- Rejected: trees built from 6 to 12 Parts each (about 10 times the instances and physics and replication cost).

### Section loop

The unit of iteration is one zone and its borders.

1. Edit the zone in `midgard.json` or its tuning.
2. In Studio Edit mode: `WorldGen.BuildSection("zoneId")` clears and rebuilds that zone's terrain, cliffs and props (target under 10 seconds). `ClearSection` removes it.
3. Fixed camera bookmarks per zone are captured with the Studio MCP `screen_capture` and compared with the previous pass and the references.
4. Lune writes a top-down map (zones, tiers, edges, pockets) for the whole realm on every build.
5. When a zone is signed off, it is marked `locked`; Lune bakes it to `Data/Zones/<id>.luau` and later builds keep the baked data.

### Retired when the centre section lands

`tools/terrain/lib/Erosion.luau`, the region and mountain code in `Heightfield.luau`, `Scatter.luau` and the Nature MEGAPACK layers, the generated `Data/` (about 16 MB), the `worldgen:*` rows in `content/register.json`, the matching `WorldGen.spec` cases, the `Nature` folder in the place (about 43k props), the region bands in `Atmosphere` moods, and `PropDetail` distances tuned for the old props. The voxel writer in `Apply.luau`, streaming settings and the day cycle stay.

### Open questions

- **Climbing**: `climb` edges and ledge pockets need a climbing mechanic, which no system defines yet.
- **Final realm size** after the first sections are played.

## Current pipeline (to be replaced)

Code: `tools/terrain/` (offline Lune generator), `src/ServerStorage/WorldGen/Apply.luau` (Studio applier), `src/ServerStorage/WorldGen/Data/` (generated). Tests: `tests/specs/WorldGen.spec.luau`.

- `lune run tools/terrain/build` (about 2 minutes) bakes a 10,240-stud world (5 × 5 tiles of 2,048 studs, 8-stud columns, seed `20261024`): start valley, highlands north, ridged mountains, swamp west, plains east, coast south; droplet and thermal erosion; river splines, lake and sea; A* roads to one site per region; 12 biomes; layered Poisson scatter of the Nature MEGAPACK (about 117k props).
- In Studio: `require(game.ServerStorage.WorldGen.Apply).Apply()` (or `ApplyTerrain`, `ApplyScatter`, `ApplyPois`, `Clear`, `ApplyStreaming`), several minutes, in a spawned task; then save. Terrain is upsampled to 4-stud voxels; props go under `Workspace.Nature/<Layer>/<256-stud chunk>`.
- **Place state (2026-10-28):** only the centre tile is kept. Terrain, props and POI markers outside X -1024..1024, Z -1360..688 were cleared in Studio. `Data/` and the applier still describe the full world, so a full `Apply()` would refill the outer tiles.
