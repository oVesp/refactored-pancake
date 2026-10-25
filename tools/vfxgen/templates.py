"""Effect template generator (docs/systems/vfx.md, "Templates").

Writes the Rojo .model.json templates under src/ReplicatedStorage/Vfx. Emitters and image labels
name their texture with a TextureKey attribute (an Assets.Textures key); Effects.Init resolves it.
Edit an effect here, regenerate, then fine-tune in Studio with VFX Forge and copy the values back.

Usage: python tools/vfxgen/templates.py [output_dir]
"""

import json
import sys
from pathlib import Path

WHITE = (255, 255, 255)
STEEL = (205, 220, 250)
STEEL_D = (105, 135, 205)
BLADE = (150, 185, 255)
BLADE_D = (60, 85, 170)
INK = (16, 18, 28)
DUST = (150, 135, 115)
DUST_D = (40, 34, 30)
EARTH = (95, 80, 65)
RAGE_HOT = (255, 190, 120)
RAGE = (255, 90, 40)
RAGE_D = (120, 20, 10)

FLIP = {"FlipbookLayout": "Grid4x4", "FlipbookMode": "OneShot"}
SHEET = {"FlipbookGrid": 4, "FramePixels": 256}


def ns(*points):
    """NumberSequence from evenly spaced values, or from (time, value) pairs."""
    if len(points) == 1:
        points = (points[0], points[0])
    if not isinstance(points[0], tuple):
        points = tuple((i / (len(points) - 1), v) for i, v in enumerate(points))
    return {"NumberSequence": {"keypoints": [{"time": t, "value": v, "envelope": 0} for t, v in points]}}


def color(c):
    return [round(x / 255, 4) for x in c]


def cs(*colors):
    if len(colors) == 1:
        colors = (colors[0], colors[0])
    n = len(colors) - 1
    return {"ColorSequence": {"keypoints": [{"time": i / n, "color": color(c)} for i, c in enumerate(colors)]}}


def nr(low, high=None):
    return {"NumberRange": [low, low if high is None else high]}


def emitter(name, key, attrs=None, **props):
    """A burst emitter for Forge: disabled, rate 0, fired by its EmitCount attribute."""
    properties = {"Enabled": False, "Rate": 0, "LightInfluence": 0, "Rotation": nr(0, 360), "Speed": nr(0)}
    properties.update(props)
    return {
        "name": name,
        "className": "ParticleEmitter",
        "properties": properties,
        "attributes": {"TextureKey": key, "EmitCount": 1, **(attrs or {})},
    }


def anchor(children, size=(1, 1, 1)):
    """The invisible root part a template is played from."""
    return {
        "className": "Part",
        "properties": {
            "Anchored": True,
            "CanCollide": False,
            "CanQuery": False,
            "CanTouch": False,
            "CastShadow": False,
            "Transparency": 1,
            "Size": list(size),
        },
        "children": children,
    }


def attachment(name, children, position=(0, 0, 0)):
    return {
        "name": name,
        "className": "Attachment",
        "properties": {"CFrame": {"CFrame": {"position": list(position), "orientation": [[1, 0, 0], [0, 1, 0], [0, 0, 1]]}}},
        "children": children,
    }


def surface(name, labels, attrs, z_offset=0, brightness=2):
    """A sprite-sheet layer lying flat on the root's top face; Effects.Play animates it from its attributes."""
    return {
        "name": name,
        "className": "SurfaceGui",
        "properties": {
            "Face": "Top",
            "SizingMode": "FixedSize",
            "CanvasSize": [256, 256],
            "LightInfluence": 0,
            "Brightness": brightness,
            "ClipsDescendants": False,
            "ZOffset": z_offset,
        },
        "attributes": attrs,
        "children": labels,
    }


def label(name, key, tint, transparency=0, z=1, scale=1, rotation=0, attrs=None):
    """One image layer of a surface; rotation 90 points a crescent's bulge forward."""
    return {
        "name": name,
        "className": "ImageLabel",
        "properties": {
            "BackgroundTransparency": 1,
            "AnchorPoint": [0.5, 0.5],
            "Position": {"UDim2": [[0.5, 0], [0.5, 0]]},
            "Size": {"UDim2": [[scale, 0], [scale, 0]]},
            "Rotation": rotation,
            "ImageRectSize": [256, 256],
            "ImageColor3": {"Color3": color(tint)},
            "ImageTransparency": transparency,
            "ZIndex": z,
        },
        "attributes": {"TextureKey": key, **(attrs or {})},
    }


def fade_to(tint):
    return {"ColorTo": {"Color3": color(tint)}}


def light(tint, brightness, reach, time):
    """A point light that flashes at full brightness and dims out over FlashTime."""
    return {
        "name": "Light",
        "className": "PointLight",
        "properties": {"Color": {"Color3": color(tint)}, "Brightness": brightness, "Range": reach, "Shadows": False},
        "attributes": {"FlashTime": time},
    }


def sparks(count, low, high, spread, colors=(WHITE, STEEL)):
    return emitter(
        "Sparks",
        "SparkStreak",
        {"EmitCount": count},
        Orientation="VelocityParallel",
        Speed=nr(low, high),
        SpreadAngle=[spread, spread],
        Drag=6,
        Acceleration=[0, -30, 0],
        Lifetime=nr(0.18, 0.34),
        Size=ns(1.8, 0),
        Color=cs(*colors),
        LightEmission=1,
        Brightness=3,
        Rotation=nr(0),
        ZOffset=1,
    )


def dust(count, size, speed, tint, transparency, **props):
    return emitter(
        "Dust",
        "DustPuff",
        {"EmitCount": count},
        Size=ns(*size),
        Lifetime=nr(0.5, 0.8),
        Speed=nr(*speed),
        SpreadAngle=[80, 80],
        Drag=4,
        Color=cs(tint),
        LightEmission=0,
        Transparency=ns(transparency),
        **FLIP,
        **props,
    )


def flash_star(size, brightness=5, tint=WHITE, lifetime=0.1):
    return emitter(
        "Flash",
        "ImpactStar",
        Size=ns(*size),
        Lifetime=nr(lifetime),
        Transparency=ns(0, 1),
        Color=cs(tint),
        LightEmission=1,
        Brightness=brightness,
        ZOffset=2,
    )


def blade_surface(name, lifetime, grow, extra=None):
    return surface(
        name,
        [
            label("Body", "SlashArc", BLADE, 0, 2, 1, 90, fade_to(BLADE_D)),
            label("Core", "SlashArc", WHITE, 0.3, 3, 0.97, 90),
        ],
        {**SHEET, "Lifetime": lifetime, "Grow": grow, **(extra or {})},
    )


# Light attack: a level crescent (a surface, since particle quads always face the camera).
strike_swipe = anchor(
    [
        blade_surface("Blade", 0.3, 1.12),
        attachment(
            "Center",
            [
                emitter(
                    "Strands",
                    "EnergyStrands",
                    {"EmitCount": 3},
                    Size=ns(3.5, 5),
                    Lifetime=nr(0.1, 0.18),
                    Color=cs(WHITE, STEEL),
                    LightEmission=1,
                    Brightness=3,
                    FlipbookLayout="Grid4x4",
                    FlipbookMode="Random",
                    ZOffset=0.5,
                ),
                emitter(
                    "Sparks",
                    "SparkStreak",
                    {"EmitCount": 8, "EmitDelay": 0.04},
                    Orientation="VelocityParallel",
                    EmissionDirection="Front",
                    Speed=nr(20, 34),
                    SpreadAngle=[35, 35],
                    Drag=6,
                    Lifetime=nr(0.15, 0.28),
                    Size=ns(1.8, 0),
                    Color=cs(WHITE, STEEL),
                    LightEmission=1,
                    Brightness=3,
                    Rotation=nr(0),
                ),
            ],
        ),
    ],
    size=(11, 0.05, 11),
)

# Melee hit: starburst, ring, sparks, filaments and a puff of dust.
hit_impact = anchor(
    [
        flash_star((9, 12), brightness=6, lifetime=0.09),
        emitter(
            "Ring",
            "RingThin",
            Size=ns((0, 1), (1, 14)),
            Lifetime=nr(0.18),
            Transparency=ns(0, 1),
            Color=cs(STEEL),
            LightEmission=1,
            Brightness=3,
            ZOffset=1.8,
        ),
        emitter(
            "Sparks",
            "SparkStreak",
            {"EmitCount": 14},
            Orientation="VelocityParallel",
            Speed=nr(30, 55),
            SpreadAngle=[180, 180],
            Drag=7,
            Acceleration=[0, -25, 0],
            Lifetime=nr(0.18, 0.35),
            Size=ns(2, 0),
            Color=cs(WHITE, STEEL_D),
            LightEmission=1,
            Brightness=4,
            Rotation=nr(0),
            ZOffset=1.6,
        ),
        emitter(
            "Strands",
            "EnergyStrands",
            {"EmitCount": 2},
            Size=ns(7, 9),
            Lifetime=nr(0.12, 0.18),
            Color=cs(WHITE, STEEL),
            LightEmission=1,
            Brightness=3,
            FlipbookLayout="Grid4x4",
            FlipbookMode="Random",
            ZOffset=1.7,
        ),
        emitter(
            "Dust",
            "Smoke",
            {"EmitCount": 4},
            Size=ns(2, 4.5),
            Lifetime=nr(0.5, 0.7),
            Speed=nr(4, 8),
            SpreadAngle=[180, 180],
            Drag=3,
            Color=cs((210, 210, 215), (150, 150, 160)),
            LightEmission=0,
            Transparency=ns(0.55, 1),
            ZOffset=0.5,
        ),
    ]
)

hit_shake = anchor(
    [
        {
            "name": "Shake",
            "className": "RayValue",
            "properties": {"Tags": {"Tags": ["CameraShake"]}},
            "attributes": {
                "Amplitude": 0.6,
                "Frequency": 0.08,
                "FadeInTime": 0,
                "SustainTime": 0,
                "FadeOutTime": 0.22,
                "Falloff": 60,
                "PositionInfluence": {"Vector3": [0.35, 0.35, 0.35]},
                "RotationInfluence": {"Vector3": [0.12, 0.12, 0.12]},
            },
        }
    ]
)


def arc(name, big, **props):
    return emitter(
        name, "SlashArc", Lifetime=nr(0.26), Rotation=nr(28, 36), Size=ns(big, big * 1.15), **FLIP, **props
    )


# Overhead blow: a tall crescent arcs down in front of the warrior (it faces the camera, so it reads vertical).
heavy_swipe = anchor(
    [
        attachment(
            "Arc",
            [
                arc("Body", 8, Color=cs(BLADE, BLADE_D), LightEmission=0.35, Brightness=2),
                arc("Core", 7.8, Color=cs(WHITE), LightEmission=1, Brightness=3, Transparency=ns(0.6), ZOffset=0.2),
            ],
        )
    ]
)

# Ground hit: a crack web and a torn shock ring lie flat; rubble, dust and sparks burst up.
ground_slam = anchor(
    [
        surface(
            "Crack",
            [
                label("Shadow", "GroundCrack", EARTH, 0.25, 1, 1.04),
                label("Glow", "GroundCrack", (255, 210, 150), 0, 2, 1, 0, fade_to((76, 64, 51))),
            ],
            {"FlipbookGrid": 1, "Lifetime": 1.3, "Fade": 0.5, "Grow": 1.04},
        ),
        surface("Ring", [label("Ring", "ShockRing", (235, 225, 205))], {**SHEET, "Lifetime": 0.4, "Grow": 1.25}, 1),
        attachment(
            "Burst",
            [
                flash_star((8, 11), lifetime=0.09),
                emitter(
                    "Rubble",
                    "Rubble",
                    {"EmitCount": 10},
                    Size=ns(1.3, 0.9),
                    Lifetime=nr(0.6, 0.9),
                    Speed=nr(14, 24),
                    SpreadAngle=[35, 35],
                    Acceleration=[0, -60, 0],
                    RotSpeed=nr(-200, 200),
                    Color=cs(DUST),
                    LightEmission=0,
                    LightInfluence=1,
                ),
                dust(6, (4, 8), (5, 10), DUST, 0.35),
                sparks(10, 22, 36, 55),
                light((255, 225, 180), 5, 18, 0.3),
            ],
            (0, 1.5, 0),
        ),
    ],
    size=(14, 0.05, 14),
)

# Wide sweep: two level blades, the second a beat later and wider, with a heavy spark spray.
cleave_swipe = anchor(
    [
        blade_surface("Blade", 0.3, 1.1),
        surface(
            "Echo",
            [label("Body", "SlashArc", (110, 140, 220), 0.35, 1, 1.15, 90)],
            {**SHEET, "Lifetime": 0.3, "Grow": 1.12, "Delay": 0.05},
            -1,
        ),
        attachment("Center", [sparks(14, 24, 40, 60)]),
    ],
    size=(16, 0.05, 16),
)

# High tier (a screen-effect skill), so it keeps the near-black ink layers.
# Charge arrival: a starburst, sparks, a short crack under the target and a puff of dust.
charge_burst = anchor(
    [
        surface("Crack", [label("Ink", "GroundCrack", DUST_D, 0.15)], {"FlipbookGrid": 1, "Lifetime": 0.9, "Fade": 0.6}),
        attachment(
            "Burst",
            [
                flash_star((7, 10)),
                emitter(
                    "InkStar",
                    "ImpactStar",
                    Size=ns(6, 7.5),
                    Lifetime=nr(0.13),
                    Transparency=ns(0.35, 1),
                    Color=cs(INK),
                    LightEmission=0,
                    ZOffset=1.5,
                ),
                sparks(12, 26, 42, 180),
                dust(4, (3, 6), (4, 8), DUST_D, 0.25),
                light((235, 240, 255), 4, 14, 0.25),
            ],
            (0, 2, 0),
        ),
    ],
    size=(9, 0.05, 9),
)

# Plain charge hit (monsters): the same crunch in earth tones, without the ink layers.
charge_hit = anchor(
    [
        surface("Crack", [label("Shadow", "GroundCrack", EARTH, 0.3)], {"FlipbookGrid": 1, "Lifetime": 0.8, "Fade": 0.6}),
        attachment(
            "Burst",
            [
                flash_star((5, 7.5), brightness=4, tint=(255, 240, 215), lifetime=0.09),
                sparks(8, 20, 34, 180, ((255, 235, 200), (170, 140, 100))),
                dust(5, (3, 6), (4, 8), DUST, 0.3),
            ],
            (0, 1.5, 0),
        ),
    ],
    size=(8, 0.05, 8),
)

# Charge take-off: dust kicked back from the feet.
charge_dust = anchor([attachment("Feet", [dust(6, (3, 6.5), (6, 11), DUST, 0.3, EmissionDirection="Back")])])

# High tier (a screen-effect skill), so it keeps the near-black ink layers.
# War cry: two torn rage rings race out across the ground, embers lift and the air shakes.
war_cry_wave = anchor(
    [
        surface(
            "Ring",
            [label("Ring", "ShockRing", RAGE_HOT, attrs=fade_to(RAGE))],
            {**SHEET, "Lifetime": 0.45, "Grow": 1.15},
            brightness=3,
        ),
        surface(
            "Echo",
            [label("Ring", "ShockRing", RAGE, 0.2, 1, 0.8, attrs=fade_to(RAGE_D))],
            {**SHEET, "Lifetime": 0.5, "Grow": 1.15, "Delay": 0.12},
            1,
            3,
        ),
        attachment(
            "Body",
            [
                emitter(
                    "Embers",
                    "FlameTongue",
                    {"EmitCount": 14},
                    Size=ns(1.6, 0.4),
                    Lifetime=nr(0.5, 0.9),
                    Speed=nr(6, 12),
                    SpreadAngle=[60, 60],
                    Acceleration=[0, 8, 0],
                    Drag=2,
                    Color=cs(RAGE_HOT, RAGE),
                    LightEmission=1,
                    Brightness=3,
                    **FLIP,
                ),
                dust(8, (3, 6), (10, 16), DUST_D, 0.35),
                light((255, 110, 50), 5, 22, 0.5),
            ],
            (0, 1, 0),
        ),
    ],
    size=(26, 0.05, 26),
)

# Screen effects (Effects.Screen), for the caster of a high-tier skill.
speed_lines = {
    "className": "ScreenGui",
    "properties": {"IgnoreGuiInset": True, "ResetOnSpawn": False, "DisplayOrder": -1},
    "attributes": {**SHEET, "Lifetime": 0.35, "Fade": 0.4},
    "children": [
        {
            "name": "Lines",
            "className": "ImageLabel",
            "properties": {
                "BackgroundTransparency": 1,
                "Size": {"UDim2": [[1, 0], [1, 0]]},
                "ImageRectSize": [256, 256],
                "ImageTransparency": 0.35,
            },
            "attributes": {"TextureKey": "SpeedLines"},
        }
    ],
}

rage_tint = {
    "className": "ColorCorrectionEffect",
    "properties": {"TintColor": {"Color3": [1, 0.82, 0.78]}, "Brightness": 0.05, "Contrast": 0.15, "Saturation": 0.2},
    "attributes": {"Lifetime": 0.3},
}

TEMPLATES = {
    "StrikeSwipe": strike_swipe,
    "HitImpact": hit_impact,
    "HitShake": hit_shake,
    "HeavySwipe": heavy_swipe,
    "GroundSlam": ground_slam,
    "CleaveSwipe": cleave_swipe,
    "ChargeBurst": charge_burst,
    "ChargeHit": charge_hit,
    "ChargeDust": charge_dust,
    "WarCryWave": war_cry_wave,
    "SpeedLines": speed_lines,
    "RageTint": rage_tint,
}


def main():
    root = Path(__file__).resolve().parents[2] / "src/ReplicatedStorage/Vfx"
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else root
    out.mkdir(parents=True, exist_ok=True)
    for name, template in TEMPLATES.items():
        (out / f"{name}.model.json").write_text(json.dumps(template, indent="\t") + "\n", encoding="utf-8")
        print(f"wrote {name}")


if __name__ == "__main__":
    main()
