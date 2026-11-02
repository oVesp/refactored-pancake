# SkillSmith — unified skill creation framework

A **non-monolithic** plugin for authoring skills in Yggdrasil. One Studio plugin hosts a set of
independent **modules** (hitboxes, animation timeline, sound placement, VFX Forge and Eclipse
Animator bridges). Every module reads the same parsed project data, edits through the same patcher,
and validates through the same gate. Nothing is hard-coded to skills: each content type registers
its own modules, so the same framework extends to Items, Enemies or Quests later.

```
tools/skillsmith/
├── README.md            this file
├── schema.json          field metadata generated from Content/Types.luau (auto-populates the editor)
├── core/                shared, game-independent logic (Luau; runs under Lune and in Studio)
│   ├── Types.luau       Module / Patch / Diagnostic contracts — the seam that keeps it non-monolith
│   ├── Parser.luau      lenient Luau table reader (no sourcemap needed)
│   ├── Schema.luau      extracts SkillDef field kinds + doc comments from Types.luau
│   ├── Registry.luau    maps source files -> logical datasets (Skills, SkillSounds, Animations…)
│   ├── Patcher.luau     surgical text patches: preserves tabs, comments, key order
│   ├── Validate.luau    mirrors the rules the tests/specs enforce (Content, Chain, SkillSounds, SpellEffects)
│   ├── Server.luau      HttpService bridge to tool servers (localhost only)
│   └── Modules/         one file per feature — Hitboxes, AnimTimeline, SoundPlacement, VfxForge, EclipseBridge
├── plugin/              Studio-side shell (drag folder into Studio as a Script, or build with rojo)
│   ├── project.luau     binds core to the real repo files; loads enabled modules from config
│   ├── model.luau       MVVM state, dirty tracking, commit pipeline
│   ├── view.luau        dock widget: skill list, form, timeline canvas, module panels
│   └── server.luau      Edit-mode HTTP server on 127.0.0.1:51789 (the "server connection")
└── lune/                headless CLI + offline validation
    ├── validate.luau    `lune run tools/skillsmith/lune/validate [skillId]`
    └── applypatch.luau  applies a JSON patch bundle written by the Studio plugin
```

## Data flow (everything auto-populates from the project)

| Source | Read by | Feeds |
|---|---|---|
| `src/ReplicatedStorage/Content/Skills.luau` | Registry → Parser | skill list, every scalar field |
| `src/ReplicatedStorage/Content/Types.luau` | Schema | field kinds, enums, tooltips, required flags |
| `content/animations/*.json` | AnimTimeline | clip length, `Hit`/`Release`/`Step` markers, assetIds |
| `src/ReplicatedStorage/Content/SkillSounds.luau` | SoundPlacement | phase → audio key overrides |
| `src/ReplicatedStorage/Content/Assets.luau` | SoundPlacement, VfxForge | Audio keys + volumes, Texture keys |
| `src/ReplicatedStorage/Vfx/*.model.json` | VfxForge | template names, emitters, `TextureKey`s |
| `Client/Vfx/SpellEffects.luau` | Validate | recipe-per-skill coverage rule |
| `Content/Classes.luau`, `Weapons.luau`, `Statuses.luau` | cross-references | dropdowns, grant lists |

No live `rojo` connection is needed to populate the editor — the repo *is* the database. The server
connection adds live Studio inspection on top (see below).

## Writing back

The plugin never rewrites whole files. It produces **patches** (`core/Patch`): find the entry block
by `id = "..."`, replace the value span of a key, insert new keys after an anchor, or append a new
entry before the closing brace of the list. Indentation, tabs, comments and key order survive because
only the matched span changes. In Studio (Edit mode) `plugin/server.luau` accepts patch bundles over
`http://127.0.0.1:51789`; outside Studio, write the bundle to `.cache/skillsmith/patches.json` and
run `lune run tools/skillsmith/lune/applypatch`. Both paths refuse to touch anything under `src/`
that isn't a registered dataset file, and every applied bundle must pass `sh tools/gate.sh` before commit.

## The five modules

1. **Hitboxes** (`core/Modules/Hitboxes.luau`) — derives the server hit volume from `range`, `angle`,
   `radius`, `delivery`, `maxTargets`, draws it on the viewport (arc/cone/cylinder/sphere), lets you
   reshape it by dragging, and writes the fields back. Also surfaces `telegraph` and the clip `Hit`
   marker so windup ↔ marker stay in sync (the convention `docs/systems/combat.md` relies on).
2. **Animation timeline** (`core/Modules/AnimTimeline.luau`) — a track for the skill's `animation`
   clip: bars for windup/recovery/cooldown, markers pulled from `content/animations`, lunge and
   telegraph events. Editing the windup line updates `windup`; snapping to a marker rounds to it.
3. **Sound placement** (`core/Modules/SoundPlacement.luau`) — places the six phases (`cast`,
   `launch`, `swing`, `impact`, `hit`, `resolve`) on the timeline, previews them from `Assets.Audio`,
   and writes explicit overrides into `SkillSounds.BY_SKILL` (leaving them implicit when they match
   the damage-type default, which is what the SkillSounds spec expects).
4. **VFX Forge integration** (`core/Modules/VfxForge.luau`) — *optional*. Detects the plugin via
   `shared.vfx` (the API `docs/systems/vfx.md` already uses from Studio MCP). Lists templates, opens
   one for tuning, enumerates their `TextureKey`s against `Assets.Textures`, and wires a skill's
   recipe `hit` template. If absent, the module reports `Available() == false` and the host hides its
   panel — no crash, no stub UI.
5. **Eclipse Animator bridge** (`core/Modules/EclipseBridge.luau`) — *optional*. Talks to Eclipse
   Animator over the local HTTP bridge (same transport as everything else, `core/Server.luau`).
   Pushes a clip's timing contract (length, markers) instead of assuming private method shapes, so a
   plugin update can't silently corrupt data; pulls edited clips back as `.rbxanim` for
   `tools/anim/anim.py` to upload. Degrades to "marker viewer only" when not installed.

Each module declares its **fields**, **actions**, **timeline items**, **diagnostics** and **patches**
against the skill draft. The shell renders whatever the loaded modules expose — adding a sixth module
is one file plus a name in `plugin/config.json`.

## Validation before every write

`core/Validate.luau` enforces, at edit time, exactly what the committed specs enforce at CI time:
required fields, enum membership, chain links exist and `chainWindow > cooldown`, GCD/castTime rules,
a `Recipe` exists in `SpellEffects` for every usable skill, and every sound phase resolves. The CLI
runs the same code offline; `sh tools/gate.sh` remains the final authority.

## Status

Core, all five modules, the Studio shell and the CLI are implemented here. Verified offline with
`lune run tools/skillsmith/lune/validate` (parses the real 100+ skill table). Not yet exercised
inside Studio — the plugin folder needs a manual drag-in (or a `rojo` build target) and the two
optional integrations need their plugins installed to test end to end.
