# VFX

Target look: the owner's reference video (2026-10-25), anime-style hits with 4 to 7 layers each. Research and plan: https://claude.ai/artifact/RbbzA7CACbBRDF4nnc7YZr

## How a hit is built

- **Layers**: a white additive core, a tinted body, a near-black non-additive "ink" layer behind them for contrast (it is what keeps a bright shape readable on daylight ground), sparks, filaments, a light and debris.
- **Timing**: the peak lasts 2 to 4 frames (about 50 ms); the rest is dissipation. Shapes appear at full size, then erode. Nothing grows slowly.
- **Allowed shapes** (owner decision 2026-10-25): textured particles, trails and beams, textured curved MeshParts (slashes, swirls, spikes) and full-screen effects (tint, flash, speed lines) on high-tier skills only. Plain Neon parts, discs and spheres stay out.
- **Feedback on contact**: authored impact, a white body flash (`Highlight`), a short light, and for the local player's own hits (given or taken) hitstop and camera shake.

## Code and data

- **Templates**: `src/ReplicatedStorage/Vfx/*.model.json`, one anchored invisible Part per effect with its emitters, attachments and Forge objects. Emitters carry VFX Forge attributes (`EmitCount`, `EmitDelay`, `EmitDuration`) and a `TextureKey` attribute naming an `Assets.Textures` key; the `Texture` property stays empty in the file so asset ids live only in the manifest. A camera shake is a `RayValue` tagged `CameraShake` with Forge's shake attributes.
- **Runtime**: client `Vfx/Effects.luau` resolves template textures, starts the Forge emit module and plays a template with `Effects.Play(name, cframe)`; it also owns `Hitstop` and `BodyFlash`. Skill recipes in `Vfx/SpellEffects.luau` call it (`strike` so far); `VfxController` plays `HitImpact`, the flash, the light and, for the local player, `Hitstop` and `HitShake` when a `ShowDamage` carries a melee skill id.
- **ForgeVFX** (`vendor/ForgeVFX/ForgeVFX.rbxm`, synced to `ReplicatedStorage.ForgeVFX`): the emit module from the owner's VFX Forge 2.4.0-rc1 plugin, extracted with `lune run tools/vendor/extract_forge <plugin .rbxm>`. Its license (VFX-DL 1.1, `vendor/ForgeVFX/LICENSE.txt`) allows it only inside the game runtime: never require it from a plugin, the command bar for anything but viewing finished effects, Lune tests or other tools. Re-extract when the plugin updates.
- **Editing in Studio**: open a template under `ReplicatedStorage.Vfx`, tune it with VFX Forge (its plugin API is `shared.vfx`, reachable from Studio MCP `execute_luau`), then write the changes back into the `.model.json` file; Rojo does not sync Studio edits to disk.
- **Textures**: originals come from `tools/vfxgen/vfxgen.py` (deterministic, project-owned, so free to upload) into `assets/original/vfx/`; see [../art/vfx-library.md](../art/vfx-library.md).
- **Skills without a template** keep the older code recipes built from `Vfx/Particles.luau` helpers.
