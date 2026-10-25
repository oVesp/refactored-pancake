# VFX texture library

Free particle, flipbook, noise and trail textures for VFX work (§7.5).

## Location

`D:\Projects\Games\VFX-Library` on the dev machine. It is **not in git** and nothing in the repo (tools, data, manifests) may reference that path.

- `INDEX.md` at the library root lists every pack: folder, source URL, license, attribution need, file count, size and whether it is Roblox OK. Read it before picking a texture.
- Each pack folder holds a `LICENSE.txt` with the source URL and the license checked on the source page.
- `_archives\` keeps the original downloads. `_unverified\` holds packs whose license is unknown.

## Rules

1. **Only CC0 textures may be uploaded to Roblox.** Use packs marked `Roblox OK: yes` in `INDEX.md`. Nothing under `_unverified\` is uploaded or shipped until its license is confirmed and the index is updated.
2. **A texture used by the game is copied into the repo**, never referenced from the library path. Copy it to `assets/third_party/<source>/<pack>/` with the pack's `LICENSE.txt`, renamed lower-snake (§7.3).
3. **Copied textures go through Git LFS** (§5.11). `.gitattributes` tracks `assets/**/*` `.png`, `.jpg`, `.tga`, `.tif`, `.tiff` and `.exr`; add a pattern before committing any other format.
4. **Each copied file gets an entry in `content/register.json`** with its origin (pack and source URL) and license. Uploaded asset ids go in the `Assets` manifest only.
5. Uploads still pass Roblox moderation. Flipbooks must fit Roblox's flipbook layouts and size limits; resize or re-pack them before upload.

## Original textures

`tools/vfxgen/vfxgen.py` (Python, numpy, Pillow) generates project-owned textures into `assets/original/vfx/`: `slash_arc_4x4` (crescent flipbook), `impact_star`, `spark_streak`, `ring_thin`, `energy_strands_4x4`, `ink_burst_4x4`, `ground_crack`, `shock_ring_4x4`, `dust_puff_4x4`, `speed_lines_4x4`, `flame_tongue_4x4`, `fire_core` (fireball head), `ice_shard` (ice splinter for `VelocityParallel` spikes), `frost_floor` (rime disc, laid flat), `lightning_fork_4x4` (forked lightning flipbook), `lightning_bolt` (1024x128 jagged beam strip), `arcane_swirl_4x4` (five-arm wispy arcane swirl flipbook), `ward_hex` (spherical honeycomb ward), `holy_rays` (uneven shafts of light from a bright point), `light_column` (a beam strip that tiles left to right, soft-edged with running streaks), `rune_circle` (a ground seal of two rings with made-up runic glyphs, not a real alphabet) `life_wisp_4x4` (a glowing leaf tumbling end over end) and `toxic_bubble_4x4` (a bubble that swells with a wobbling rim, then pops into a ring of droplets). Each texture draws from its own seed (`fire_core` to `toxic_bubble_4x4` use `SEED + 6` to `SEED + 17`), so on the same numpy and Pillow versions adding one never changes the earlier ones. Other versions can produce slightly different pixels, so the committed PNGs are the reference: after regenerating, keep only the new files and `git checkout` the committed ones. They are white on alpha, so particles tint them; flipbooks are Grid4x4 at 256 px per frame. Register rows use origin `original (tools/vfxgen/vfxgen.py)` and license `project`. Prefer adding a generator here over hunting for a pack when the shape is procedural (rings, bursts, streaks, crescents, filaments).

## Spell visuals

Code: authored templates played by `Vfx/Effects.luau` (see [../systems/vfx.md](../systems/vfx.md)), and the older code recipes in `Vfx/Particles.luau` (emitter, trail, light and motion helpers) and `Vfx/SpellEffects.luau` (one recipe per skill id), dispatched by `VfxController`.

- Shapes come from textures: on particles, trails and beams, and on textured curved MeshParts (slashes, swirls, spikes), which the owner allowed on 2026-10-25 together with full-screen effects for high-tier skills. No plain Neon spheres, cylinders, discs or blocks. Visuals do not have to match the server hit volume.
- Recipes so far: Cleave, War Cry, Heavy Strike, Charge (Warrior); Firebolt, Frost Shard, Spark, Flame Fan, Ice Patch, Arcane Shield, Blink, Overcharge (Mage); Mend, Smite, Rebuke, Lay on Hands, Renew, Shelter (Healer); enemy Brute Slam, Chief Stomp, Wolf Charge, Archer Volley, Poison Snare, Hex Bolt, Hex Curse, Shaman Heal. Other skills keep the neon placeholders until they get a recipe.
- Vary the delivery shape: projectiles, ground eruptions (Ice Patch, Poison Snare), falling strikes (Lay on Hands, Archer Volley), auras (Arcane Shield, Renew), beams and chains (Shelter, Overcharge), novas (Brute Slam), dashes (Charge, Blink) and cones (Flame Fan).
- Particles with `VelocityParallel` stretch the texture's horizontal axis along the velocity, so vertical streak textures need `rotation = 90`. Beams run the texture's vertical axis along their length: use vertical textures (`Arc`, `Streak`) or the radial `SoftGlow` for a soft column.
- Scenes are bright daylight. White additive (`emission = 1`) shapes vanish on pale ground and sky; give the shape that carries the read a saturated tint and `emission` of 0 to 0.4, and keep additive for glows on top.
- Textures are keys in `Assets.Textures`: 19 copied from Kenney Particle Pack 1.1 into `assets/third_party/kenney/particle_pack/` and 23 generated originals, all uploaded (ids in the manifest and register). An entry without `id` uses `fallback`, a particle texture that ships with the Roblox client, so a new texture can be tried before its upload.
- After uploading, set `id` in `Assets.Textures` and `assetId` in the register row; `Register.spec` checks they match.
