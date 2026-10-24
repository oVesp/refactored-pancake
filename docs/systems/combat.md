# Combat

Code: `Server/Services/SkillService.luau`, `CombatService.luau`, `StatusService.luau`, `EntityService.luau`; `Shared/Formulas.luau`; client `CombatController`, `VfxController`.

- **Entities**: players, goblins and dummies register in `EntityService` with team, level, tags and pools. It records root positions at 20 Hz for lag compensation (rewind = player ping, capped at `Tuning.Combat.MaxRewind`) and runs the movement sanity check.
- **Use**: the client sends `UseSkill(skillId, aim, seq)`. The server checks alive, known, not disabled, not casting, cooldown, aim sanity and cost, then calls `SkillService.Cast`. Rejections return `RejectSkill(seq, reason)`; the client clears its predicted cooldown.
- **Cast**: windup or cast time (cast time scales with Agility; Heavy Strike windup with `HeavySpeed`) is broadcast as `ShowCast` (Cast or Telegraph) and is interrupted by stun, fear or knockback.
- **Deliveries**: Melee/Cone (arc against rewound positions), SelfArea, Ground (clamped to range), Projectile (server-stepped segment test that stops on walls), Ally (ally nearest the aim, else self), Self, Dash (to the enemy nearest the aim), Blink (wall-checked), Object (tagged world props).
- **Damage**: `CombatService.DealDamage` calls `Formulas.ResolveDamage` (type tags, crit, level gap, defense). Guarding while facing the attacker parries inside `ParryWindow` (attacker stunned), otherwise takes 40% damage and costs stamina. Dodge grants i-frames. Shields absorb first. Players in safe zones cannot be harmed; the same team never.
- **Statuses**: data in `Content/Statuses`. Dot/Hot ticks go through `CombatService`, so every HP change shares one path. Harmful durations shrink with Resistance; immune tags block statuses by id.
