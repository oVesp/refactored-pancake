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

The inverse-sphere fog trick hides the world edge with geometry. Here engine streaming, haze and client culling replace it:

1. **Instance streaming** (`default.project.json`): target radius 1,024 and minimum 64 (the defaults Roblox recommends), `Opportunistic` stream-out so clients drop far regions without waiting for memory pressure, `Improved` model streaming, and `PauseOutsideLoadedArea` integrity.
2. **Haze as the far plane** (owner choice: medium fog): atmosphere density hides detail by about 1,000 studs, right where streamed content ends. Mountains still show as silhouettes through the haze.
3. **No SLIM imposters.** `LevelOfDetail` is `Disabled` on every prop. With SLIM on the trees, play ran at about 5 fps while Roblox had not generated the imposters yet, and the console filled with `RuntimePropertySet ... being generated`.
4. **Bare single-part props**: the applier puts props with one part straight into their chunk, without a Model around them (about 78k fewer instances).
5. **Client culling** (`PropDetailController`, distances in `Content/PropDetail`): understory and cover chunks hide past 450 studs and pebbles past 350. Past 600 studs only a stable 40% of trees stays. Hidden props move to a holder outside the DataModel, so they cost no rendering, and streaming still adds and removes them.

After Rojo syncs a new `Apply`, run `ApplyStreaming()` in edit mode to update placed props, then save. The command bar caches `require` for the whole Studio session, so restart Studio first or require a clone parented next to the original (`local c = Apply:Clone(); c.Parent = Apply.Parent; local WG = require(c); c:Destroy()`).

### Measurements (Studio play solo, 2026-10-25)

Start valley, Studio quality level 21. Server and client share one process in play solo, so both numbers move together.

| Pass | Client fps | Render CPU | Triangles | Notes |
|---|---|---|---|---|
| Baseline (SLIM on trees) | 5 | 140–200 ms | 7.5–8.4M | Same fps looking at the sky: not a rendering cost |
| No Nature props at all | 50 | | 1.1M | Reference ceiling |
| 1. SLIM off | 26 | 38 ms | 12.1M | Server heartbeat 6 → 25/s |
| 2. Single-part props unwrapped | 28 | 34 ms | 12.1M | Client instances 234k → 192k |
| 3. Shadows off on props (rejected) | 23 | 40 ms | 12.1M | No gain; shadows kept |
| 4. Client culling | 56 | 17 ms | 6.5M | Client instances 104k, server heartbeat 57/s |

Moving 1,400 studs and back restored props as expected, with no errors.

## Not yet verified

- Visual tuning of every mood and light key.
- Frame time and memory on low-end devices and on a live server (play solo shares one process).
- Generating props on demand near players is the last resort if a live server cannot hold the whole scatter.
