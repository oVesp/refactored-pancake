# World generation (Midgard)

The owner replaced the eroded voxel world with a stylized, vertical, zone-graph world (2026-10-28). The references are walled fantasy Roblox worlds for the look and Kenshi for scale and variety. The centre section is built in the place. The old eroded-terrain pipeline is still in the repo; see *Old pipeline* for what remains.

Originality: the references give style and scale only. No layout, landmark, location name or unique feature of any referenced game is copied (game-design §2).

Code: `src/ServerStorage/WorldGen/Midgard.luau` (authored graph and tuning), `Gen/` (pure generator, runs in Lune and Studio), `Sections.luau` (Studio builder), `Baked/` (locked zones, generated). Tools: `tools/worldgen/` (map preview, bake, prop upload), `tools/blender/world_props.py` (prop library). Tests: `tests/specs/WorldGraph.spec.luau`.

## Goals

- **Perceived size over raw size.** A zone feels big because sight lines are short: cliffs, tiers and fog hide what is next. Hidden areas need something to hide behind, not more distance.
- **Verticality separates zones.** Zones sit on elevation tiers; the cliff between two tiers is the border. There is no requirement for a wall on every edge.
- **Section-by-section authoring.** One zone can be regenerated, viewed and tuned in seconds without moving any other zone.

## Size

10,240 × 10,240 studs per realm Place, **provisional**: the owner commits a final size after the first sections are played. Base walk speed is 16 studs/s, so a straight crossing takes about 11 minutes and a real route about 17. Authoring happens inside `sections` rectangles; the centre section is X -1024..1024, Z -1360..688.

## Layout: the zone graph (`Midgard.luau`)

- **Nodes**: `zone` (a playable area) or `pocket` (a hidden area). Each has an id, biome, danger band, tier (or an explicit `floor` for ledge pockets), radius `r` and usually an authored position. A node without `x`/`z` is placed by a deterministic force layout next to the nodes it connects to. `roof = true` covers a pocket so it sits inside the ground around it. `locked = true` freezes a signed-off zone (see the section loop).
- **Edges**: `open` (no border feature), `pass` (a gap through the ridge or rim between them), `ramp` / `stairs` (a path between tiers, straight across or `along = true` down the lower zone's border), `cave` (a roofed tunnel), `drop` (one-way, down; no geometry beyond the cliff). `secret` marks an edge with no signpost.
- **Pads**: the Map zones (`Workspace.Map.Zones`), held flat at the Map ground level; a test keeps them equal to `Map.rbxmx`.
- **Lakes**: water below the zone floor, with a sand shore.
- **Roads**: dirt polylines painted into the terrain (village to the camp gate, plaza to the dev yard and east).
- **Settlements** (`settlements`): what dresses each pad. See *Settlements*.

Centre section: village, fields, orchard and goblin camp on the valley floor (tier 0); south hollow below (tier -1, lake); east terrace (tier 1), west heights (tier 2) and north rim (tier 3) above; pockets `cellar-hollow` (cave from the village), `camp-den` (cave from the goblin camp) and `fern-ledge` (ledge between fields and east terrace, reached by drops).

## Generator (`Gen/`)

Every stage is a pure function of position, seeded per zone (`Hash.named(seed, id)`) and per border (`Hash.pair`), so a zone's output depends only on the graph data near it.

1. **Ownership** (`Field.owner`): a multiplicatively weighted Voronoi diagram on domain-warped coordinates (two warp scales). A point belongs to the node with the smallest distance / `r`, so borders curve and larger nodes claim more ground. Past `r` from every site, or outside every section, is mountain rim.
2. **Height** (`Field.sample`):
   - zone floor plus gentle per-zone noise;
   - **terraces**: realm-wide noise above a biome's thresholds lifts the floor one or two steps, fading out near pads, lakes and open borders;
   - **ridges** between same-tier neighbours that have no `open` edge;
   - **rim**: from every nearby zone the ground climbs in ledges (`rim.rise`, `rim.ledge`), and the rim takes the lowest climb, so between zones it rises from both sides to a crest under a noisy ceiling;
   - pads flattened, lakes carved;
   - **corridors** for ramps, stairs, passes and caves, which override the height along a polyline. `along` paths follow the lower zone's border at a fixed offset, on the side that keeps farther from pads.
3. **Parts** (`Cliffs.build`): wherever the ground rises more than `cliff.step` between neighbouring samples there is a face, whatever made it. Face points on the zone's ground are thinned to `cliff.spacing` and each grows a column of stacked, jittered blocks from below the low ground to the top of that face's ledge, with a grass cap. Columns never cover walkable corridor ground: each footprint is tested against points across every corridor's width, and the column shrinks or is dropped. Rim columns may rise into spires. Standalone outcrops dot zone floors. Stairs get Part steps; caves and roofed pockets get roof slabs up to the ground they cut through.
4. **Props** (`Props.scatter`): groves from a realm-wide noise mask thresholded so each biome covers its `groves` share of the zone; trees Poisson-disc spaced for the biome density, a few loners outside groves, bushes around trees, boulders on a jittered lattice; all kept off corridors, water, pads and slopes.
5. **Settlements** (`Settlement.forZone`): see below.
6. **Terrain**: one 4-stud column per sample; faces steeper than a cliff step are painted with the rock material. Studio draws solid terrain half a voxel above the height a linear occupancy encodes, so the writer lowers ground by 2 studs (water is not shifted).

## Settlements

The Map (`tools/world/build.luau`) keeps only gameplay objects:
- zone volumes and the spawn point;
- trainers and the vendor;
- the dev yard;
- spawners;
- the creation stage.

The generator builds everything that dresses the pads, around those objects. `Anchors.fromMap` reads them (with a spawner's spawn radius), and nothing generated comes within `settlements.clear` studs of one. Footprints never overlap; tests check both rules.

- **Village** (VillageCore):
  - a cobbled plaza;
  - lots along every road and around the plaza, each house or barn standing back `setback` studs with its door side to the road;
  - a perimeter fence with gaps at the roads;
  - crates, a wagon and hay near the buildings.
- **Farmland** (WheatFields): `Plots.layout` splits the pad either side of the road into plots by binary space partition.
  - Each plot has a terrace level (0, 1.5 or 3 studs over the pad), a crop and a furrow direction.
  - The terrain raises each plot with a 3-stud bank and paints furrows (Mud and Ground stripes) along its rows. Paths stay at pad level.
  - Wheat and sprouts grow in rows on the ridges; hay plots get bales; wheat plots get a scarecrow.
  - Raised plots get a stone lip, open in the middle of each side.
- **Orchard** (OrchardEdge): a jittered grid of fruit trees, an aisle along the road, fences and clutter.
- **Goblin camp** (GoblinCamp):
  - a palisade ring with two gate towers facing the village road;
  - tents on an inner ring, opening to the centre;
  - the fire brazier, the chieftain's dais and clutter.
- **Fixtures** are authored positions for gameplay objects and set pieces:
  - the village well (`Purifiable` water) and two braziers;
  - the camp brazier (`Kindleable` bowl);
  - the dais.

  Their templates carry the tag as a `WorldTag` attribute; only placed copies get the CollectionService tag, so a template in ServerStorage is never a spell target.

`SpawnService` stands each enemy on the ground below its spawn point (terrain and `Workspace.World`), so terraced plots and the dais are handled.

## Village kit (MegaKit)

`tools/blender/village_kit.py` (headless Blender 5.2) builds 28 assets into `build/village_kit.glb` with a manifest `build/village_kit.json`:
- **10 houses and 2 barns** from `tools/blender/house_generator.py` (Quaternius Medieval Village MegaKit, CC0);
- **kit props**: fence, crate, wagon, stone border;
- **structures built on the kit's own trim-sheet materials**: well, brazier, scarecrows, palisades, gate tower, tents, dais.

Roblox compatibility fixes, all in the script:
- Normal maps from the kit's OpenGL set (`Normals Godot-Unity`); the default set is DirectX-style.
- Textures scaled to 1024 px.
- `MI_WoodTrim_Wear` merged into `MI_WoodTrim`: its wear overlay needs the kit shader and a second UV set, which is dropped.
- Heavy kit pieces decimated once in the library: a three-story house went from 45k to 20k triangles. Interior floors are dropped.
- Each asset exported as one object per material (`<Asset>__<Material>`), so Roblox makes one MeshPart per material and the names keep the material.
- Untextured materials (glass, canvas, cloth, metal) and the vine tint listed in the manifest; Roblox drops glTF base colours.
- Axes measured with marker cubes: the Roblox glTF import maps Blender X to -X and Y to +Z, so an asset's front faces Roblox -Z. The manifest records bounds in Roblox axes and `front = "-Z"`.

`python tools/worldgen/props.py upload --creator-user 82401475 --library village` uploads it. That writes the asset id, the materials and the asset metadata to `content/world/village.json`, which Rojo maps to `WorldGen.VillageManifest`. `Sections.ImportVillage()` then fills `ServerStorage.VillageKit`:
- one Model per asset, pivoted at its footprint centre on the ground, at `settlements.scale` (3.2 studs per kit metre);
- materials coloured from the manifest;
- the well's `Water` and the braziers' `Bowl` gameplay parts added at their manifest anchors.

## Props: procedural low-poly at low cost

- **Few, large props.** Broadleaf trees about 58 studs and pines about 72 at scale 1, scaled 0.8 to 1.4.
- **Variant library.** `tools/blender/world_props.py` (headless Blender 5.2) builds 49 seeded variants: 8 Broadleaf, 8 Pine, 6 Snag, 6 Bush, 6 Boulder, and for the settlements 4 Wheat, 3 Sprout, 6 Fruit (orchard trees) and 2 Hay. Each part has at most about 450 triangles. Canopies are convex hulls of a few random points; pines are stacked low-sided cones.
- **Upload and import.**
  1. `python tools/worldgen/props.py upload --creator-user 82401475` uploads the FBX through Open Cloud. It records the asset id and a geometry hash in `content/world/props.json`, which Rojo maps to `WorldGen.PropsManifest`.
  2. `Sections.ImportProps()` makes `ServerStorage.WorldProps`: one Model per variant, pivoted at the base and scaled to the species height.
  3. Every placed prop is a clone of a variant, so identical meshes render as one instanced batch.
- **Two instances per tree at most.**
  - The trunk collides; the canopy has collision, query and touch off.
  - Parts are placed bare, without a Model.
  - Collision fidelity stays Default, because the MCP context cannot set it. Setting trunks and boulders to Hull in Studio is cheaper.
- Rejected: trees built from 6 to 12 Parts each, which would be about 10 times the instances.

## Section loop

1. Edit `Midgard.luau` (nodes, edges, tuning).
2. `lune run tools/worldgen/map` writes `build/worldgen-centre.png` in about 10 seconds. It shows shaded ground, water, borders, corridors, pads, every cliff part and labelled nodes.
3. In Studio Edit mode, after Rojo syncs, require a fresh copy: `local c = game.ServerStorage.WorldGen:Clone(); c.Parent = game.ServerStorage; local S = require(c.Sections)`. After a library upload, run `S.ImportProps()` or `S.ImportVillage()` first. Then run one of:
   - `S.Build("orchard")`: about 1 to 6 seconds per zone;
   - `S.Build("orchard", true)`: the zone and every zone whose ground lies within the build margin of it;
   - `S.Build()`: everything, about 25 seconds for the centre.

   A zone reads each 256-stud terrain block it touches, replaces only its own columns, and writes the block back. Its parts go to `Workspace.World/<zone>/<Kind>`.
4. `S.View("orchard", k)` puts the camera behind the site, clear of parts, facing N/E/S/W for `k` 1 to 4. It returns the camera position and target, which the Studio MCP `screen_capture` takes.
5. When a zone is signed off, set `locked = true` and run `lune run tools/worldgen/bake`. That writes `Baked/<zone>.luau` with terrain columns, parts and props. Builds then use the bake, so generator changes can no longer alter the zone. `--rebake <zone>` regenerates one on purpose.

`S.Reset()` clears all terrain and the `World` folder. It also moves the old `Workspace.Nature` props to `ServerStorage.RetiredNature`, where they stay until the owner deletes them.

## Not built yet

- **Per-zone mood**: the atmosphere still blends by the old region bands (`tools/terrain/lib/Config.luau`), not by zone.
- **Prop culling**: `PropDetail` culls the old `Nature` chunks. The new props are few enough not to need it yet.
- **Climbing**: `climb` edges and ledge routes wait for a climbing mechanic (game-design §12).
- **Water and caves inside zones**: only lakes, cave corridors and roofed pockets exist.

## Old pipeline (to be removed)

`tools/terrain/` (eroded heightfield generator), `src/ServerStorage/WorldGen/Apply.luau`, the generated `WorldGen/Data/` (about 16 MB), their `worldgen:*` register rows and `tests/specs/WorldGen.spec.luau` describe the replaced world.
- The place no longer uses them: `Reset()` cleared their terrain, and their props are parked in `ServerStorage.RetiredNature`.
- `Atmosphere` still reads the region bands from `tools/terrain/lib/Config.luau`. Removal therefore goes together with per-zone moods.
