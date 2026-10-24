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

## Spell visuals

Code: client `Vfx/Particles.luau` (emitter, trail, light and ground-wave helpers) and `Vfx/SpellEffects.luau` (one recipe per skill id), dispatched by `VfxController`.

- Every visible shape comes from a texture on a ParticleEmitter or Trail attached to an invisible anchor. No neon spheres, cylinders or blocks. Visuals do not have to match the server hit volume.
- Recipes so far: Cleave, War Cry (Warrior); Firebolt, Frost Shard, Spark (Mage); Mend, Smite, Rebuke (Healer). Other skills keep the neon placeholders until they get a recipe.
- Textures are keys in `Assets.Textures`, copied from Kenney Particle Pack 1.1 into `assets/third_party/kenney/particle_pack/` and uploaded (ids in the manifest and register). An entry without `id` uses `fallback`, a particle texture that ships with the Roblox client, so a new texture can be tried before its upload.
- After uploading, set `id` in `Assets.Textures` and `assetId` in the register row; `Register.spec` checks they match.
