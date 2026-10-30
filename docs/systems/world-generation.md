# World generation (Midgard)

Midgard is one continent (owner, 2026-10-29), laid out from the owner's sketch: a living world in the vein of Kenshi that runs without the player, who is one more adventurer in it. Two great powers, the **Holy Kingdom** and the **Dragon Empire**, hold most of the land. The neutral **Adventurers** hold two cities: the **Central Capital** on the mainland and the **Harbor** in the south-west. The rest belongs to minor factions (Elves, Dragons, Undead) or to nobody. Factions: [open world](open-world.md).

This replaced the zone-graph world (village, fields and goblin camp in one centre section, 2026-10-28). Its generator, Studio builder, bake tool, routes and tests were removed with it.

Originality: the sketch is the owner's own; region names and placeholder site names are generic. No layout, landmark, location name or unique feature of another game is copied (game-design §2).

Code: `src/ServerStorage/WorldGen/Continent.luau` (template), `Gen/Continent.luau` (pure generator and point query, runs in Lune and Studio), `Gen/Region.luau` (one region at stud scale, pure), `Gen/Camp.luau` (goblin camp layout), `Regions.luau` (Studio builder), `Gen/Hash.luau` (hashing and noise). Tools: `tools/worldgen/continent.luau`, `tools/worldgen/region.luau`. Tests: `tests/specs/Continent.spec.luau`, `tests/specs/Region.spec.luau`.

## Template (`Continent.luau`)

Unit map coordinates: `u` west to east, `v` north to south, both 0..1, so the data reads like the sketch. `size` is 20,480 studs (owner, 2026-10-29); a grid cell is 80 studs. Studs have the **Harbor village at the origin** (`origin`, `Continent.toStuds` and `toUnit`), so the Map's spawn, trainers, zones and dev yard keep their coordinates.

- **Heights** (`heights`, studs): water at -8, seabed down to -70, a 3-stud beach, region height 1 = 300 studs, mountain peaks up to 1.15 of that, Map ground 0.2.
- **Pads**: rectangles in studs around the origin, one per Map zone (village core, dev yard, fields, orchard, goblin camp), held flat at the Map ground and dry, fading out over `pads.blend`. They count as Verdant Greens.
- **Bay**: a circle of sea south of the village, so the Harbor has water for its docks on every seed.

- **Regions**: id, name, biome, owner faction, base `height`, noise `relief` and `anchors` `{ u, v, r }`. Several anchors shape a region (the Tundra band has three). `scatter` adds islets around the first anchor (Archipelago). `sky` marks floating isles that roads do not reach (Sky Isles). Each region asks for a number of `towns`, `pois` and `dungeons`.
- **Ridges**: region pairs whose shared border is a mountain range.
- **Lakes**: `{ u, v, r }`.
- **Sites**: named sites with a kind (`capital`, `city`, `town`, `harbor`, `poi`, `dungeon`, `portal`), region, owner and rough spot. `coastal` moves a site to the coast. Names are placeholders until the content pass.

| Region | Biome | Owner |
|---|---|---|
| Land of Dragons (NW) | volcanic | Dragons |
| Tundras (N band), Triad Canyon (NE), Wastelands (E), Magma Wastelands (E) | tundra, canyon, wasteland, magma | Dragon Empire (capital in the Tundras) |
| The Highlands (centre), Sky Isles, Swamps (W), Verdant Greens (SW) | highland, sky, swamp, plains | Holy Kingdom (Highland Capital) |
| Deep Forests (S centre) | forest | Elves (Eldergrove) |
| Undead Fields, Undead Kingdom (SE) | undead | Undead (Niflheim Gate on the coast) |
| The Coasts (S), Archipelago (NE) | coast, isles | unclaimed |

The Central Capital stands in the Highlands and the Harbor on the Verdant Greens coast; both belong to the Adventurers. The Harbor is the starter village (scope 01 slice: village, fields, orchard, goblin camp inland to the north); it is `fixed` at the origin, and a small Verdant anchor keeps it on the mainland for every seed.

## Generator (`Gen/Continent.luau`)

`Continent.generate(template, seed?, res?)` is a pure function on a `res` x `res` grid (256 by default; tests use 128). Every random stream is seeded by name (`Hash.named`), so a seed gives the same continent in Lune and Studio. Stages 1 and 2 are the point query `Continent.sampler(template, seed)(u, v)`, which the grid and the Studio terrain writer both call, so regions built at different times meet exactly.

1. **Land and regions**: anchors are jittered per seed. A cell belongs to the region with the smallest distance / `r` to one of its anchors, measured on domain-warped coordinates so borders curve. It is land while that distance stays under `coast.reach` plus coastline noise (1 for scattered islets); this closes the gaps between anchors and draws the coast. A `margin` of open sea surrounds the map.
2. **Height, mountains, lakes**: base height plus noise and per-biome detail relief, lower near the shore. Neighbouring regions blend across a `blend` band, so borders are slopes, not steps. Points near a `ridges` border (noisy `ridge.width`) rise into ridged mountains. Template lakes are carved with a noisy shore at their own water level. Pads and the bay override land and height last.
3. **Shore and mainland**: coast cells touch the sea; the mainland is the largest land mass.
4. **Sites**: each named site takes the dry, non-mountain cell of its region nearest to its jittered spot (a coast cell when `coastal`). Then each region places its towns, points of interest and dungeons on random cells, `spacing` apart from every site; dungeons may sit on mountains. Towns belong to the region's owner.
5. **Roads**: a minimum spanning tree over the mainland settlements (capital, city, town, harbor; not the Sky Isles), plus a link to a node's second-nearest neighbour when that is under `roads.extra` times the nearest distance. Shortest links are routed first, by A* over 8 neighbours: cost grows with slope, mountains cost `roads.mountain` times more and existing road costs `roads.reuse` times less, so roads merge into trunks.

The result (`Map`) holds per-cell region, height and mountain, coast, mainland and road flags, the placed sites and the roads as cell paths.

## Preview

`lune run tools/worldgen/continent [seed]` writes `build/continent-<seed>.png` in about 2 seconds: biomes with hillshade, mountains, lakes, coast, territory borders in faction colours, roads, site markers and labels. Other seeds keep the sketch layout and change the coast, borders, mountain lines, minor sites and roads.

## Tests

`Continent.spec` runs eight seeds and checks:
- the same seed gives the same continent, and different seeds differ;
- every region exists, and its largest piece holds at least 80% of it;
- the Adventurers hold exactly the central capital and a coastal harbor in the south-west;
- each empire has one capital inside its own territory;
- sites stand on dry ground in their own region, settlements off mountains;
- named settlements (capitals, city, harbor) are on the mainland;
- roads reach every mainland settlement from the central capital.

## Region builds

Each region is built and approved on its own (owner, 2026-10-29). Approved: **Verdant Greens** (terrain, roads, props and goblin camps; 2026-10-29).

- **Ownership**: a region owns every 4-stud column whose sample names it as `owner`: its land, its lakes and the sea out to `offshore` anchor reaches from its coast. Sea farther out is not built yet.
- **Columns** (`Region.column`): ground and water from the sample; material from the biome: beach sand near the coastline, rock on mountains and slopes over 4.5 studs per column (snow above 250 studs), bare ground on roads (7 studs either side of the smoothed road line) and in large noise patches, grass elsewhere; sand and mud under water.
- **Props** (`Region.props`): trees on a jittered lattice at the biome density inside groves (noise mask covering `groves` of the ground), a few loners, bushes around trees, boulders on a coarser lattice. Kept off water, beaches, mountains, roads, pads and uneven ground. Each is a clone of a `ServerStorage.WorldProps` variant.
- **Goblin camps** (owner, 2026-10-29: dress with a few goblin camps): `camp` sites owned by Goblins. Verdant Greens has the starter slice's camp, fixed on the Map's GoblinCamp zone 660 studs north of the Harbor, plus `camps = 2` placed by the generator (`spacing.camp` from any site). `Region.point` levels the ground to the camp centre's height inside the palisade and eases it back over `camp.flatten` studs; the ground there is mud and no props grow. `Gen/Camp.luau` lays each camp out from village-kit models: a palisade ring of `camp.radius` studs whose gate faces the nearest settlement, two gate towers, tents on an inner ring opening to the centre, the brazier (its bowl gets the `Kindleable` tag from the template's `WorldTag` attribute) and the dais opposite the gate, crates and a wagon. Camps have no goblins yet.
- **Sites**: other sites are neon placeholder pillars until they are dressed.
- **Studio** (`Regions.luau`): `Regions.Build(id)` runs in the background; it reads each 256-stud terrain block near the region, replaces only owned columns and writes it back, then places props and markers under `Workspace.World/<id>`. `Regions.Status(id)` reports progress; Verdant Greens takes about 50 seconds. `Regions.View(id, k)` frames the region from the N/E/S/W edge or above.
- **Report**: `lune run tools/worldgen/region <id>` prints bounds, prop count, sites and the fingerprint, and writes `build/region-<id>.png` (8 studs per pixel).

### Approval

Terrain lives only in the place file, so approval is a fingerprint: `Region.fingerprint` hashes the owned ground, water and material on a 32-stud lattice, the props and the markers. When the owner approves a region, its fingerprint goes into `Continent.approved`. `Region.spec` fails if a change would alter an approved region, and `Regions.Build` refuses an approved region unless forced.

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

`python tools/worldgen/props.py upload --creator-user 82401475 --library village` uploads it and writes the asset id, materials and asset metadata to `content/world/village.json`, which Rojo maps to `WorldGen.VillageManifest`. The Studio importer went with the zone graph; the region builder brings it back.

## Harbor mock (owner, 2026-10-30)

`WorldGen/Harbor.luau` is a Studio builder, run in Edit mode with `require(game.ServerStorage.WorldGen.Harbor).Build()`. It rebuilds `Workspace.Harbor` from `ServerStorage.VillageKit` models and plain parts, and removes the region builder's placeholder pillar for the Harbor site. It does not touch the approved Verdant Greens build (terrain, props, `Region.fingerprint`); the ground there is the existing village pads and bay.

- **Inn** (kit House06) east of the plaza, door facing west; the innkeeper (the Map's vendor, `TrainerType = "Vendor"`) stands at its door and `InnSpawn` (`RespawnPoint`) is beside it.
- **Guild hall** (kit Barn01) west of the plaza, door facing east; the **quest board** (`QuestBoard` tag) stands in front of it.
- **Pylon** (`Pylon` tag, with an `Arrival` part) south of the plaza on a stone dais with a glowing core.
- **Dock**: a 12-stud pier from z 150 to 330 on piles with rails, a 44-stud head with crates and a wagon, and `DockSpawn` (`ArrivalSpawn`) on the head.
- **Dressing**: houses around the plaza and road, a well, a warehouse.

The gameplay behind each tag is in [economy](economy.md). Positions are code constants; art can be replaced as long as the tags and the `Arrival` part stay. Not done: Fantasy Props MegaKit dressing (barrels, banners, benches), Poly Haven props, signage, lamps and boats.

## Props: procedural low-poly at low cost

- **Few, large props.** Broadleaf trees about 58 studs and pines about 72 at scale 1, scaled 0.8 to 1.4.
- **Variant library.** `tools/blender/world_props.py` (headless Blender 5.2) builds 49 seeded variants: 8 Broadleaf, 8 Pine, 6 Snag, 6 Bush, 6 Boulder, and for settlements 4 Wheat, 3 Sprout, 6 Fruit (orchard trees) and 2 Hay. Each part has at most about 450 triangles. Canopies are convex hulls of a few random points; pines are stacked low-sided cones.
- **Upload.** `python tools/worldgen/props.py upload --creator-user 82401475` uploads the FBX through Open Cloud and records the asset id and a geometry hash in `content/world/props.json`, which Rojo maps to `WorldGen.PropsManifest`. Every placed prop is to be a clone of a variant, so identical meshes render as one instanced batch.
- **Two instances per tree at most.** The trunk collides; the canopy has collision, query and touch off. Parts are placed bare, without a Model.
- Rejected: trees built from 6 to 12 Parts each, which would be about 10 times the instances.

## Not built yet

- **Settlements**: towns and other sites are placeholder pillars; only goblin camps and the Harbor mock are dressed.
- **Camp population**: camps hold no stationed goblins yet; roaming squads come from the nests in `ContentServerOnly/Population`.
- **Open sea**: sea beyond each region's offshore band is not built.
- **Population**: `ContentServerOnly/Population` is empty. Garrisons, patrols, caravans and nests come back per site and road once regions are built.
- **The Map**: `Workspace.Map` (inn and dock spawns, trainers, the innkeeper, dev yard, creation stage) stands on the Harbor village pads at the origin. The `harbor_dock` safe zone (z 80 to 360, in `Map.DockZones`, outside `Map.Zones` because the pads end at the shore) covers the pier.
- **Per-region mood**: the atmosphere still blends by the old region bands (`tools/terrain/lib/Config.luau`).

## Old pipeline (to be removed)

`tools/terrain/` (eroded heightfield generator), `src/ServerStorage/WorldGen/Apply.luau`, the generated `WorldGen/Data/` (about 16 MB), their `worldgen:*` register rows and `tests/specs/WorldGen.spec.luau` describe an older replaced world.
- The place no longer uses them; their props are parked in `ServerStorage.RetiredNature`.
- `Atmosphere` still reads the region bands from `tools/terrain/lib/Config.luau`, so removal goes together with per-region moods.
