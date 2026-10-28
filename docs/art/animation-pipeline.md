# Animation pipeline

One workflow for every animation set: a manifest per set, one tool for export, upload and the asset
tables, and a spec that keeps them in step. Mechanics reference for `docs/game-design.md` §7.

## Pieces

| Piece | Role |
|---|---|
| `src/ReplicatedStorage/Content/AnimRoles.luau` | Enemy role contract: `Idle`, `Walk`, `Attack`, `Death` required; `Run`, `Throw`, `Hit` optional. Priority and looping per role. `EnemyAnimationController` loads every role a set has. |
| `content/animations/<set>.json` | Manifest per set: exporter, source folder, rig, and per clip its role, source file, looping, markers, tier, notes, hashes, live asset id and id history. Source of truth for everything below. |
| `tools/anim/anim.py` | `scan`, `status`, `export`, `upload`, `sync` (below). |
| `tools/anim/rig_from_import.luau` | Bone list with rest offsets from a raw Studio import (Rig import). |
| `tools/blender/export_clips.py` | Exporter `fbx`: one FBX per clip → KeyframeSequence, headless Blender 5.2. |
| `tools/blender/rbxanim_to_keyframes.py` | Exporter `rbxanim`: `.rbxanim` bakes of the R15 combat rig → KeyframeSequence. |
| Exporter `studio` | Clips animated and uploaded in Studio; the committed KeyframeSequence is an export of the uploaded clip (Skeleton). The tool only tracks them. |
| `Content/Assets.luau` generated block, `content/register.json` animation rows | Written by `sync`. Never edit by hand. |
| `tests/specs/Animations.spec.luau` | Fails the gate when a manifest, Assets and AnimRoles disagree, a required role is missing, or a tier is unknown. |

## Tiers

- **placeholder**: any clip not authored by the owner for this game. Action Forge (Quaternius, CC0) clips and agent-made clips are placeholders.
- **final**: an owner-authored replacement. A clip becomes final only when the owner says so when handing it over.

Replacing a placeholder with a final: point the clip's `source` at the new file, set `tier` to `final`, then `scan`, `export`, `upload`. The old asset id moves to the clip's `history` with the tier and source it was uploaded from; nothing else changes, so gameplay code never notices the swap.

## Clip states

`status` reports each clip from the manifest and the committed KeyframeSequence, so the result is the same on every machine:

| State | Meaning | Next step |
|---|---|---|
| `needs-scan` | Source hash not recorded | `scan` |
| `needs-export` | Source changed since the last export | `export` |
| `needs-upload` | KeyframeSequence differs from the uploaded one, or no id yet | `upload` |
| `live` | Uploaded id matches the committed KeyframeSequence | none |

`upload` only sends `needs-upload` clips of the named set (upload quota is limited). Unmapped files in the source folder are catalogued in the manifest's `library` and are never exported or uploaded.

## Commands

Run from the repo root. `BLENDER` points at the Blender 5.2 executable; the Open Cloud key comes from `ROBLOX_OPEN_CLOUD_KEY`.

```
python tools/anim/anim.py status [set ...]
python tools/anim/anim.py scan [set ...]
python tools/anim/anim.py export <set> [clip ...]
python tools/anim/anim.py upload --creator-user 82401475 <set> [clip ...]
python tools/anim/anim.py sync
```

`scan`, `export` and `upload` end with `sync`. Commit the manifest, the KeyframeSequences, `Assets.luau` and `register.json` together.

## Sources

Raw clip folders under `assets/original/characters/**/Export/Animations/` are git-ignored: each Auto-Rig Pro export carries the whole mesh (about 55 MB per clip). The manifest records each file's SHA-256, so a changed or missing source shows up in `scan`. The committed KeyframeSequences are what the game and the upload use.

## Adding a clip or a role

- **New clip for an existing role**: set the role's `source` in the manifest (or add the clip entry), then `scan`, `export`, `upload`.
- **New role** (for example a cast or taunt clip): add it to `AnimRoles.Enemy` with priority and looping, make the server cue it through `AnimCue`, then map it per set. Optional roles may stay unmapped; required roles fail the gate until every enemy set has one.
- **New set**: write `content/animations/<set>.json` (`kind` `enemy` for `AnimSet` rigs, `skill` for clips keyed by `SkillDef.animation`), import the rig (below), then `scan`, `export`, `upload`.

## Rig import (exporter `fbx`)

A set's rig block stays `pending-import` until the mesh is in Studio and the set's template uses it, and `export` refuses to run before that, because KeyframeSequence pose names must match the bones the importer keeps. Uploading clips for a new skeleton while the template still has the old one breaks every enemy of that set, so steps 2 to 5 land in one commit.

1. Import the character FBX (for the Goblin Scout, `Export/Goblin_Scout.fbx`) with the Studio 3D importer and save the raw import as `tools/world/<set>_import.rbxm`.
2. Rebuild the set's template from the raw import in `tools/world/build.luau` (the Skeleton path) and register the mesh ids in `Assets.Meshes`.
3. Write the bone list: `lune run tools/anim/rig_from_import tools/world/<set>_import.rbxm tools/world/<set>_bones.json`, and point `rig.bones` at it. Each bone records its rest offset in studs.
4. Keep `rig.studsPerMetre` at `"auto"` (the exporter compares those offsets with the FBX rest pose and prints the median ratio) or set a number; set `rig.poseRoot` to the pose wrappers above the root bone (empty for raw imports such as the Skeleton) and `rig.status` to `ready`.
5. `export` one clip, play it in Studio on the new template and check it against the Blender playback, then `export` and `upload` the rest.

## Sets

| Set | Exporter | Source | Rig |
|---|---|---|---|
| Goblin | fbx | Goblin Scout, `assets/original/characters/mobs/Goblin Scout/Export/Animations` (Action Forge clips remapped by the owner) | pending import; the template and live ids are the retired `goblin.blend` goblin until the Scout template and clips land together |
| Skeleton | studio | Uploaded from Studio by the owner | n/a |
| Combat | rbxanim | `assets/blender/combat_r15/*.rbxanim` | stock R15 |

Goblin Scout placeholder mapping: Idle `idle_loop`, Walk `walk_loop`, Run `jog_fwd_loop`, Attack `sword_regular_a`, Throw `overhandthrow`, Hit `hit_chest`, Death `death01`. Where a source has a `.001` duplicate, the file without the suffix is canonical. The Scout clips are in place: `root.x` carries the hip motion only.
