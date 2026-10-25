# Atmosphere and large-world performance

Code: `src/Lighting/` (authored effects), `src/ReplicatedStorage/Content/Atmosphere.luau` (moods, light keys, day length), `Shared/AtmosphereBlend.luau` and `Shared/DayCycle.luau` (pure math), `Client/Controllers/AtmosphereController.luau`. Streaming settings: `default.project.json` (Workspace). Prop detail: `WorldGen/Apply.luau`. Tests: `tests/specs/Atmosphere.spec.luau`.

## Look

- **Lighting** (`default.project.json`): `ShadowMap` technology (Future is too costly over about 117k props), global shadows, latitude 52 for a northern sun path.
- **Effects** (`src/Lighting`): `Atmosphere`, default `Sky` (no uploaded skybox; tuned sun, moon and 3,000 stars), `Bloom`, `ColorCorrection`, `SunRays`. The client creates terrain `Clouds` if the place has none. If the saved place already has other Lighting effects, delete them so only these remain.
- **Region moods** (`Atmosphere.Moods`): valley, highland, mountain, alpine (camera above about 240 to 420 studs), swamp, plains and coast. Each sets atmosphere density, offset, haze, glare, colour and decay, the colour grade, and cloud cover. Weights use the generator's region bands (`tools/terrain/lib/Config.luau` `world`, kept equal by a test) without its noise warp, so moods cross over the same 1,000-stud borders as the biomes.
- **Day and night** (owner choice, 2026-10-25): a 24-minute day with a 6-minute night. Night is moonlit and readable without torches. `DayCycle.ClockAt(workspace:GetServerTimeNow())` gives every client and server the same clock with nothing replicated. The server never writes Lighting at runtime.
- **Light keys** (`Atmosphere.Lights`): night, before dawn, sunrise, morning, afternoon, sunset and twilight. Each key sets brightness, exposure, ambient light, sun colour, a sky tint that multiplies the region colours, a haze scale, bloom and sun rays.
- The controller re-blends 8 times a second and eases the region mood over about a second, so walking across a border fades instead of snapping.

## Performance

The inverse-sphere fog trick hides the world edge with geometry. Here three engine features replace it:

1. **Instance streaming** (`default.project.json`): target radius 1,024 and minimum 64 (the defaults Roblox recommends), `Opportunistic` stream-out so clients drop far regions without waiting for memory pressure, `Improved` model streaming, and `PauseOutsideLoadedArea` integrity.
2. **Haze as the far plane** (owner choice: medium fog): atmosphere density hides detail by about 1,000 studs, right where streamed content ends. Mountains still show as silhouettes through the haze.
3. **SLIM imposters for trees**: `Apply.luau` sets `LevelOfDetail = SLIM` on tree models, so forests beyond the streaming radius render as light composite meshes instead of disappearing. Rocks, understory, cover and pebbles are `Disabled` and stream out under the haze. Run `require(game.ServerStorage.WorldGen.Apply).ApplyStreaming()` in edit mode to update props that are already placed, then save. The command bar caches `require` for the whole Studio session, so after Rojo syncs a new `Apply` use `require(game.ServerStorage.WorldGen.Apply:Clone())` or restart Studio. Roblox generates the SLIM meshes on its servers after the place is saved or published; until then, play sessions log `RuntimePropertySet ... being generated`.

## Not yet verified in Studio

These were written while no place was open in Studio:

- Visual tuning of every mood and light key.
- Whether SLIM imposters show the Nature pack trees well. Imposters are untextured, and canopy trees at twice pack size exceed the roughly 64-stud model size Roblox recommends.
- How SLIM interacts with the props' default `ModelStreamingMode`.
- Frame time and memory on low-end devices.

Next step if the MicroProfiler shows draw-call cost from near props: client-side distance culling of small-prop chunks. It was skipped for now because hiding streamed instances on the client competes with the engine's stream-out.
