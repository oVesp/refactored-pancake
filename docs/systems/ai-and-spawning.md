# AI and spawning

Code: `Server/Services/AIService.luau`, `SpawnService.luau`, `Client/Controllers/EnemyAnimationController.luau`; template `src/ServerStorage/Templates/Goblin.rbxmx`.

Template: skinned `Body` MeshPart (bones from `tools/world/goblin_rig.json`) driven by a Humanoid and `HumanoidRootPart`, plus an invisible `Head` anchor for nameplates. Spawn scales it by `def.scale × BaseScale` (1.5) and tints `Body`; the SurfaceAppearance leaves the skin transparent so the colour shows. The model streams atomically.

Animation: AIService sets `AnimCue = "<clip>:<seq>"` on attack (melee, dash and self-area skills) or throw (everything else), hit and death. The client plays locomotion from root speed (idle, walk, run above 10 studs/s) and one-shots from the cue. Clip ids come from `Assets.Animations`; entries without an uploaded id fall back to the KeyframeSequence in `ReplicatedStorage.Animations`, which only resolves in Studio.

- **Spawners** are invisible parts tagged `Spawner` (`EnemyId`, `Count`, `LevelMin`, `LevelMax`, `RespawnSeconds`, `Radius`). Active cap per zone: `Tuning.Npc.ActivePerZone`. Dead goblins despawn after 3 s; their spawner refills after its timer.
- **Brains** think every 0.25 s with jitter: Idle → Patrol (random point near home) → Aggro (taunt, then threat, then the nearest player in aggro radius) → Attack (first ready skill in data order whose conditions hold) → Return (beyond the leash: clear threat, walk home, regenerate, reset). Players in safe zones are never targeted. Damage alerts nearby idle goblins.
- **Behaviors** come from data: `keepDistance` makes ranged units kite; Ally skills heal the most wounded goblin; Dash skills open from range. The Chieftain enters phase 2 at 50% HP (Rally plus two Raiders).
- **Movement** uses `Humanoid:MoveTo` on clear lines and `PathfindingService` (pcall, staggered recompute) when blocked.
- `AiState` is replicated as an attribute for the debug overlay.
