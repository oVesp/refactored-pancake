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
FIRE_HOT = (255, 240, 170)
FIRE = (255, 150, 40)
FIRE_D = (200, 50, 15)
SMOKE = (80, 60, 50)
SMOKE_D = (40, 35, 35)
ICE_HOT = (240, 252, 255)
ICE = (150, 220, 255)
ICE_D = (70, 140, 230)
MIST = (225, 245, 255)
# Flames tint toward orange and glow only partly, so they stay orange instead of washing out in daylight.
FLAME = ((255, 200, 90), (255, 120, 30), FIRE_D)
EMBER_CORE = ((255, 225, 140), (255, 140, 40))

FLIP = {"FlipbookLayout": "Grid4x4", "FlipbookMode": "OneShot"}
# VelocityParallel lays a texture's x axis along the velocity; IceShard points up its frame,
# so this turn makes a shard lead with its tip.
SHARD_ALONG = -90
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


def stream(name, key, rate, attrs=None, **props):
    """A continuous emitter for Effects.Attach and Effects.Charge, which stop it when the part is released."""
    properties = {"Rate": rate, "LightEmission": 1, "LightInfluence": 0, "Rotation": nr(0, 360), "Speed": nr(0)}
    properties.update(props)
    return {
        "name": name,
        "className": "ParticleEmitter",
        "properties": properties,
        "attributes": {"TextureKey": key, **(attrs or {})},
    }


def inward(name, key, rate, size, colors, transparency=(1, 0.2, 0), **props):
    """Charge-up particles that spawn on a shell around the hand and pull inward."""
    return stream(
        name,
        key,
        rate,
        Shape="Sphere",
        ShapeStyle="Surface",
        ShapeInOut="Inward",
        Speed=nr(4, 6),
        Lifetime=nr(0.35, 0.45),
        Size=ns(*size),
        Transparency=ns(*transparency),
        Color=cs(*colors),
        RotSpeed=nr(-90, 90),
        **props,
    )


def anchor(children, size=(1, 1, 1), attrs=None):
    """The invisible root part a template is played from."""
    part = {
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
    if attrs:
        part["attributes"] = attrs
    return part


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


def glow(tint, brightness, reach):
    """A steady point light that travels with an attached template and dims when it is released."""
    return {
        "name": "Light",
        "className": "PointLight",
        "properties": {"Color": {"Color3": color(tint)}, "Brightness": brightness, "Range": reach, "Shadows": False},
    }


def trail(colors, lifetime, width):
    """A ribbon behind a moving part, between two attachments its From and To attributes name."""
    return [
        attachment("TrailTop", [], (0, width / 2, 0)),
        attachment("TrailBottom", [], (0, -width / 2, 0)),
        {
            "name": "Trail",
            "className": "Trail",
            "properties": {
                "Lifetime": lifetime,
                "Color": cs(*colors),
                "Transparency": ns(0.1, 1),
                "LightEmission": 1,
                "LightInfluence": 0,
                "FaceCamera": True,
                "MinLength": 0,
            },
            "attributes": {"TextureKey": "TrailStreak", "From": "TrailTop", "To": "TrailBottom"},
        },
    ]


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

# Charge-ups (Effects.Charge): held at the casting hand, their emitters speeding up until the cast ends.
HAND = {"Offset": {"Vector3": [0.8, 0.4, -1.6]}}

fire_charge = anchor(
    [
        inward("Gather", "FlameTongue", 55, (1.8, 0.6), FLAME, LightEmission=0.35, Brightness=2.5, **FLIP),
        stream(
            "Core",
            "FireCore",
            20,
            LockedToPart=True,
            LightEmission=0.7,
            Size=ns(1.1),
            Lifetime=nr(0.1),
            Color=cs(*EMBER_CORE),
            Brightness=2,
            RotSpeed=nr(-300, 300),
        ),
        stream(
            "Embers",
            "SparkStreak",
            15,
            Orientation="VelocityParallel",
            Speed=nr(2, 5),
            SpreadAngle=[180, 180],
            Acceleration=[0, 6, 0],
            Lifetime=nr(0.3, 0.5),
            Size=ns(0.6, 0),
            Color=cs(FIRE_HOT, FIRE),
            Brightness=2,
            Rotation=nr(0),
        ),
        glow(FIRE, 1.5, 8),
    ],
    size=(3, 3, 3),
    attrs=HAND,
)

frost_charge = anchor(
    [
        inward("Gather", "Glint", 35, (0.7, 0.2), (ICE_HOT, ICE)),
        inward("Splinters", "IceShard", 14, (0.8, 0.3), (ICE_HOT, ICE_D)),
        inward("Mist", "Smoke", 10, (1.2, 0.4), (MIST,), (1, 0.6, 0.5), LightEmission=0.3),
        stream(
            "Core",
            "SoftGlow",
            15,
            LockedToPart=True,
            Size=ns(1.6),
            Lifetime=nr(0.1),
            Color=cs(ICE),
            Transparency=ns(0.3),
        ),
        glow(ICE, 1.5, 8),
    ],
    size=(3, 3, 3),
    attrs=HAND,
)

# Firebolt in flight (Effects.Attach): a ragged fireball head shedding flame tongues, embers and smoke.
firebolt_body = anchor(
    [
        stream(
            "Core",
            "FireCore",
            30,
            LockedToPart=True,
            LightEmission=0.6,
            Size=ns(2),
            Lifetime=nr(0.08, 0.12),
            Color=cs(*EMBER_CORE),
            Brightness=1.2,
            RotSpeed=nr(-300, 300),
            ZOffset=1,
        ),
        stream(
            "Glow",
            "SoftGlow",
            20,
            LockedToPart=True,
            Size=ns(4.2),
            Lifetime=nr(0.1),
            Color=cs((255, 140, 50)),
            Transparency=ns(0.75),
            Brightness=1,
        ),
        stream(
            "Tongues",
            "FlameTongue",
            90,
            LightEmission=0.35,
            Speed=nr(0.5, 2.5),
            SpreadAngle=[180, 180],
            Acceleration=[0, 4, 0],
            Lifetime=nr(0.25, 0.4),
            Size=ns(2.2, 0.6),
            Color=cs(*FLAME),
            Brightness=1.2,
            RotSpeed=nr(-90, 90),
            **FLIP,
        ),
        stream(
            "Embers",
            "SparkStreak",
            25,
            Orientation="VelocityParallel",
            Speed=nr(4, 9),
            SpreadAngle=[180, 180],
            Drag=2,
            Acceleration=[0, 6, 0],
            Lifetime=nr(0.2, 0.4),
            Size=ns(0.9, 0),
            Color=cs((255, 220, 140), FIRE),
            Brightness=2,
            Rotation=nr(0),
        ),
        stream(
            "Smoke",
            "Smoke",
            12,
            LightEmission=0,
            Acceleration=[0, 3, 0],
            Lifetime=nr(0.6, 1),
            Size=ns(1.2, 3.2),
            Transparency=ns(0.55, 1),
            Color=cs(SMOKE, SMOKE_D),
            RotSpeed=nr(-40, 40),
        ),
        *trail((FIRE_HOT, FIRE, FIRE_D), 0.2, 0.9),
        glow((255, 140, 50), 2, 12),
    ]
)

# Firebolt hit: a hot flash, the core blooming out, flame tongues and embers flung wide, dark smoke.
firebolt_burst = anchor(
    [
        flash_star((8, 12), tint=FIRE_HOT, lifetime=0.1),
        emitter(
            "Core",
            "FireCore",
            Size=ns(3, 8),
            Lifetime=nr(0.25),
            Transparency=ns(0, 1),
            Color=cs((255, 225, 140), (255, 120, 30)),
            LightEmission=0.7,
            Brightness=1.5,
            ZOffset=1.5,
        ),
        emitter(
            "Tongues",
            "FlameTongue",
            {"EmitCount": 12},
            Speed=nr(8, 16),
            SpreadAngle=[180, 180],
            Drag=5,
            Acceleration=[0, 6, 0],
            Lifetime=nr(0.35, 0.55),
            Size=ns(2.8, 1),
            Color=cs(*FLAME),
            LightEmission=0.35,
            Brightness=1.2,
            **FLIP,
        ),
        sparks(14, 20, 34, 180, (FIRE_HOT, FIRE)),
        emitter(
            "Smoke",
            "Smoke",
            {"EmitCount": 6},
            Speed=nr(2, 5),
            SpreadAngle=[180, 180],
            Drag=2,
            Acceleration=[0, 2, 0],
            Lifetime=nr(1, 1.4),
            Size=ns(2.5, 5.5),
            Transparency=ns(0.5, 1),
            Color=cs(SMOKE, SMOKE_D),
            LightEmission=0,
        ),
        light(FIRE, 6, 18, 0.35),
    ]
)

# A scorch mark that glows like embers, cools and fades within a second.
scorch = anchor(
    [
        surface(
            "Burn",
            [
                label("Char", "FireCore", (70, 45, 30), 0.3),
                label("Embers", "FireCore", (255, 120, 40), 0.2, 2, 0.6, 0, fade_to((80, 30, 10))),
            ],
            {"FlipbookGrid": 1, "Lifetime": 1, "Fade": 0.6, "Grow": 1.05},
        )
    ],
    size=(6, 0.05, 6),
)

# Frost Shard in flight: a cluster of turning ice splinters in a cold glow, shedding glints and mist.
frost_shard_body = anchor(
    [
        stream(
            "Core",
            "IceShard",
            24,
            LockedToPart=True,
            LightEmission=0.4,
            Size=ns(2.6),
            Lifetime=nr(0.08, 0.12),
            Color=cs((190, 235, 255), (120, 190, 250)),
            Brightness=1,
            ZOffset=1,
        ),
        stream(
            "Glow",
            "SoftGlow",
            20,
            LockedToPart=True,
            Size=ns(3.4),
            Lifetime=nr(0.1),
            Color=cs(ICE),
            Transparency=ns(0.75),
            Brightness=1,
        ),
        stream(
            "Glints",
            "Glint",
            40,
            Speed=nr(0.5, 2),
            SpreadAngle=[180, 180],
            Lifetime=nr(0.3, 0.5),
            Size=ns(0.7, 0),
            Color=cs(ICE_HOT, ICE),
        ),
        stream(
            "Splinters",
            "IceShard",
            18,
            Speed=nr(1, 3),
            SpreadAngle=[180, 180],
            Lifetime=nr(0.3, 0.5),
            Size=ns(0.7, 0.2),
            Color=cs(ICE_HOT, ICE_D),
            Brightness=1,
            RotSpeed=nr(-200, 200),
        ),
        stream(
            "Mist",
            "Smoke",
            16,
            LightEmission=0,
            Lifetime=nr(0.5, 0.8),
            Size=ns(1, 2.4),
            Transparency=ns(0.7, 1),
            Color=cs(MIST),
            RotSpeed=nr(-30, 30),
        ),
        *trail((ICE_HOT, ICE), 0.25, 0.6),
        glow(ICE, 1.5, 10),
    ]
)

# Frost Shard hit: a cold flash and ring, splinters flung along their flight, glints and mist.
frost_burst = anchor(
    [
        flash_star((7, 10), brightness=4, tint=ICE_HOT, lifetime=0.1),
        emitter(
            "Shards",
            "IceShard",
            {"EmitCount": 10},
            Orientation="VelocityParallel",
            Speed=nr(18, 30),
            SpreadAngle=[180, 180],
            Drag=5,
            Acceleration=[0, -20, 0],
            Lifetime=nr(0.3, 0.5),
            Size=ns(1.8, 0.3),
            Color=cs(ICE_HOT, ICE),
            LightEmission=1,
            Brightness=2,
            Rotation=nr(SHARD_ALONG),
            ZOffset=1,
        ),
        emitter(
            "Glints",
            "Glint",
            {"EmitCount": 10},
            Speed=nr(4, 10),
            SpreadAngle=[180, 180],
            Drag=3,
            Lifetime=nr(0.4, 0.7),
            Size=ns(1, 0),
            Color=cs(ICE_HOT, ICE),
            LightEmission=1,
        ),
        emitter(
            "Ring",
            "RingThin",
            Size=ns((0, 1), (1, 10)),
            Lifetime=nr(0.2),
            Transparency=ns(0, 1),
            Color=cs(ICE),
            LightEmission=1,
            Brightness=2,
            ZOffset=1.8,
        ),
        emitter(
            "Mist",
            "Smoke",
            {"EmitCount": 6},
            Speed=nr(1, 3),
            SpreadAngle=[180, 180],
            Lifetime=nr(0.8, 1.2),
            Size=ns(2, 4.5),
            Transparency=ns(0.5, 1),
            Color=cs(MIST),
            LightEmission=0.3,
        ),
        light(ICE, 5, 16, 0.3),
    ]
)

# A small patch of rime left where a frost spell lands.
frost_splash = anchor(
    [
        surface(
            "Rime",
            [label("Rime", "FrostFloor", (200, 235, 255), 0.1)],
            {"FlipbookGrid": 1, "Lifetime": 1.2, "Fade": 0.5, "Grow": 1.12},
        )
    ],
    size=(7, 0.05, 7),
)

# Ice Patch area: rime spreads over the ground under a cold shock ring and a low snow puff.
ice_patch_floor = anchor(
    [
        surface(
            "Rime",
            [label("Rime", "FrostFloor", (200, 235, 255), 0.05)],
            {"FlipbookGrid": 1, "Lifetime": 1.8, "Fade": 0.4, "Grow": 1.1},
        ),
        surface(
            "Ring",
            [label("Ring", "ShockRing", (220, 240, 255), attrs=fade_to((90, 160, 235)))],
            {**SHEET, "Lifetime": 0.45, "Grow": 1.2},
            1,
        ),
        attachment("Burst", [dust(8, (3, 6), (3, 6), MIST, 0.45), light(ICE, 5, 22, 0.6)], (0, 1, 0)),
    ],
    size=(16, 0.05, 16),
)

# One eruption point of Ice Patch: splinters stab up out of the ground, chips fly and fall.
ice_spike = anchor(
    [
        emitter(
            "Spikes",
            "IceShard",
            {"EmitCount": 3},
            Orientation="VelocityParallel",
            Speed=nr(14, 22),
            SpreadAngle=[18, 18],
            Drag=9,
            Lifetime=nr(0.6, 0.8),
            Size=ns((0, 0.5), (0.12, 3.4), (0.75, 3.1), (1, 0)),
            Transparency=ns((0, 0), (0.7, 0.05), (1, 1)),
            Color=cs((220, 245, 255), (130, 200, 255), ICE_D),
            LightEmission=0.2,
            Brightness=1,
            Rotation=nr(SHARD_ALONG),
        ),
        emitter(
            "Chips",
            "IceShard",
            {"EmitCount": 4},
            Speed=nr(8, 14),
            SpreadAngle=[60, 60],
            Acceleration=[0, -40, 0],
            Lifetime=nr(0.5, 0.7),
            Size=ns(0.6, 0.3),
            Color=cs(ICE_HOT, ICE),
            LightEmission=0.3,
            RotSpeed=nr(-300, 300),
        ),
        emitter(
            "Glints",
            "Glint",
            {"EmitCount": 3},
            Speed=nr(5, 10),
            SpreadAngle=[70, 70],
            Drag=3,
            Acceleration=[0, -12, 0],
            Lifetime=nr(0.4, 0.7),
            Size=ns(1.1, 0),
            Color=cs(ICE_HOT, ICE),
            LightEmission=1,
        ),
    ]
)

# Flame Fan jet (Effects.Attach on a nozzle): each emitter's Reach attribute is its share of the range
# (speed = range / 0.45 * Reach) and its Arc attribute its share of the cone angle; the recipe applies them.
flame_fan_jet = anchor(
    [
        stream(
            "Tongues",
            "FlameTongue",
            140,
            {"Reach": 1, "Arc": 0.5},
            EmissionDirection="Front",
            SpreadAngle=[8, 30],
            Drag=1.2,
            Lifetime=nr(0.45, 0.6),
            Size=ns(0.8, 3, 4.5),
            Transparency=ns(0.1, 0.3, 1),
            Color=cs(*FLAME),
            LightEmission=0.35,
            Brightness=1.5,
            RotSpeed=nr(-120, 120),
            **FLIP,
        ),
        stream(
            "Core",
            "FireCore",
            60,
            {"Reach": 0.7, "Arc": 0.33},
            EmissionDirection="Front",
            SpreadAngle=[5, 20],
            Lifetime=nr(0.15, 0.25),
            Size=ns(1.2, 2.8),
            Transparency=ns(0, 1),
            Color=cs(*EMBER_CORE),
            LightEmission=0.7,
            Brightness=1.5,
        ),
        stream(
            "Embers",
            "SparkStreak",
            40,
            {"Reach": 1.1, "Arc": 0.5},
            EmissionDirection="Front",
            Orientation="VelocityParallel",
            SpreadAngle=[10, 30],
            Acceleration=[0, 8, 0],
            Lifetime=nr(0.3, 0.5),
            Size=ns(0.9, 0),
            Color=cs(FIRE_HOT, FIRE),
            Brightness=2,
            Rotation=nr(0),
        ),
        stream(
            "Smoke",
            "Smoke",
            25,
            {"Reach": 0.5, "Arc": 0.5},
            EmissionDirection="Front",
            LightEmission=0,
            SpreadAngle=[10, 30],
            Drag=3,
            Acceleration=[0, 4, 0],
            Lifetime=nr(0.8, 1.2),
            Size=ns(2, 5),
            Transparency=ns(0.6, 1),
            Color=cs(SMOKE, SMOKE_D),
        ),
        glow((255, 140, 50), 2.5, 16),
    ]
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
    "FireCharge": fire_charge,
    "FrostCharge": frost_charge,
    "FireboltBody": firebolt_body,
    "FireboltBurst": firebolt_burst,
    "Scorch": scorch,
    "FrostShardBody": frost_shard_body,
    "FrostBurst": frost_burst,
    "FrostSplash": frost_splash,
    "IcePatchFloor": ice_patch_floor,
    "IceSpike": ice_spike,
    "FlameFanJet": flame_fan_jet,
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
