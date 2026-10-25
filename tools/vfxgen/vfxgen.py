"""Procedural VFX texture generator (docs/art/vfx-library.md, "Original textures").

Writes greyscale-on-alpha PNGs to assets/original/vfx/. White RGB marks the brightest part of a
shape; particles tint it through Color. Flipbooks are 4x4 grids of 256 px frames read left to
right, top to bottom (Roblox Grid4x4). Every texture is generated here, so the project owns it
outright. Deterministic: the same seed always writes the same files.

Usage: python tools/vfxgen/vfxgen.py [output_dir]
"""

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SEED = 7
FRAME = 256
GRID = 4


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def value_noise(size, cells, rng):
    """Tileable-enough smooth noise in [0, 1] from a bicubic-upsampled random grid."""
    grid = rng.random((cells + 1, cells + 1)).astype(np.float32)
    img = Image.fromarray((grid * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255.0


def fbm(size, rng, octaves=4, base=4):
    total = np.zeros((size, size), np.float32)
    amp, norm = 1.0, 0.0
    for i in range(octaves):
        total += value_noise(size, base * 2**i, rng) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def polar(size):
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    x = (xs + 0.5) / size - 0.5
    y = (ys + 0.5) / size - 0.5
    return np.hypot(x, y), np.arctan2(y, x)


def rgba(intensity, alpha):
    rgb = np.clip(intensity, 0, 1)
    a = np.clip(alpha, 0, 1)
    out = np.stack([rgb, rgb, rgb, a], axis=-1)
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA")


def sheet(frames):
    out = Image.new("RGBA", (FRAME * GRID, FRAME * GRID), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        out.paste(frame, ((i % GRID) * FRAME, (i // GRID) * FRAME))
    return out


def ease_out(t):
    return 1 - (1 - min(max(t, 0.0), 1.0)) ** 3


def slash_arc(rng):
    """Crescent swipe: snaps in over 3 frames, holds, then erodes from the tail with noise."""
    r, theta = polar(FRAME)
    start, span = math.radians(-205), math.radians(230)
    u = ((theta - start) % (2 * math.pi)) / span
    inside_span = u <= 1.0
    u = np.clip(u, 0, 1)
    outer = 0.45
    # Blade profile: fat in the middle, needle-thin at both tips, heavier toward the leading end.
    thickness = 0.2 * np.clip(np.sin(np.pi * u), 0, 1) ** 0.9 * (0.65 + 0.35 * u)
    depth = outer - r
    hard_edge = smoothstep(-0.004, 0.003, depth)
    soft_inner = 1 - smoothstep(thickness * 0.55, thickness + 0.004, depth)
    shape = hard_edge * soft_inner * inside_span
    across = np.clip(depth / np.maximum(thickness, 1e-3), 0, 1)
    # Brush fibres: noise stretched along the arc so streaks follow the swing.
    fibre = value_noise(FRAME * 4, 160, rng)[::4, ::4]
    fibre_r = np.interp(r, np.linspace(0, 0.71, FRAME), fibre[0])
    brush = 0.65 + 0.35 * fibre_r
    erosion_noise = fbm(FRAME, rng, octaves=4, base=6)
    frames = []
    for f in range(GRID * GRID):
        head = min(1.0, ((f + 1) / 3) ** 0.8)
        tail = max(0.0, (f - 3) / 12.0) ** 1.3
        reveal = smoothstep(head + 0.02, head - 0.08, u) if head < 1 else np.ones_like(u)
        hot = 1 + 0.6 * np.exp(-(((u - head) / 0.12) ** 2)) * (head < 1)
        cut = smoothstep(tail - 0.12, tail + 0.06, u) if tail > 0 else np.ones_like(u)
        dissolve = smoothstep(tail - 0.08, tail + 0.1, erosion_noise * 0.8 + 0.35 * u) if tail > 0 else 1.0
        alpha = shape * reveal * cut * dissolve
        intensity = (1.0 - 0.55 * across ** 1.5) * brush * hot
        frames.append(rgba(intensity, alpha))
    return sheet(frames)


def impact_star(rng, size=512):
    """Irregular starburst: long thin spikes of mixed length around a hot core."""
    r, theta = polar(size)
    reach = np.zeros_like(r)
    for _ in range(26):
        angle = rng.uniform(-math.pi, math.pi)
        length = rng.uniform(0.12, 0.49)
        width = rng.uniform(0.025, 0.09)
        delta = np.abs((theta - angle + math.pi) % (2 * math.pi) - math.pi)
        reach = np.maximum(reach, length * np.clip(1 - delta / width, 0, 1) ** 1.6)
    reach = np.maximum(reach, 0.045)
    alpha = smoothstep(reach + 0.004, reach - 0.006, r)
    glow = np.exp(-((r / 0.1) ** 2))
    intensity = np.clip(0.55 + 0.45 * glow + 0.4 * (1 - r / np.maximum(reach, 1e-3)), 0, 1)
    return rgba(intensity, np.maximum(alpha, glow * 0.6))


def spark_streak(size=256):
    """Horizontal streak, bright head on the right, long fading tail (VelocityParallel)."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    x = (xs + 0.5) / size * 2 - 1
    y = (ys + 0.5) / size * 2 - 1
    along = np.clip((x + 1) / 2, 0, 1)
    width = 0.02 + 0.07 * along**2
    body = np.exp(-((y / width) ** 2)) * smoothstep(0.0, 0.25, along) * smoothstep(1.0, 0.9, along)
    core = np.exp(-((y / (width * 0.4)) ** 2)) * along**1.5
    return rgba(np.clip(0.6 + 0.4 * core, 0, 1), np.clip(body, 0, 1))


def ring_thin(rng, size=512):
    """Crisp thin ring with a soft halo and slight breakup."""
    r, theta = polar(size)
    d = np.abs(r - 0.43)
    line = smoothstep(0.009, 0.003, d)
    halo = np.exp(-((d / 0.03) ** 2)) * 0.5
    breakup = 0.75 + 0.25 * value_noise(size, 24, rng)
    return rgba(0.7 + 0.3 * line, np.clip((line + halo) * breakup, 0, 1))


def energy_strands(rng):
    """Flickering jagged filaments for Random flipbook mode."""
    frames = []
    scale = 2
    big = FRAME * scale
    for _ in range(GRID * GRID):
        lines = Image.new("L", (big, big), 0)
        draw = ImageDraw.Draw(lines)
        for _ in range(rng.integers(2, 5)):
            angle = rng.uniform(0, 2 * math.pi)
            radius = rng.uniform(0.12, 0.38)
            sweep = rng.uniform(0.6, 1.8)
            points = []
            steps = 28
            drift = 0.0
            for i in range(steps + 1):
                a = angle + sweep * i / steps
                drift = drift * 0.6 + rng.normal(0, 0.012)
                rr = radius + drift
                points.append((big / 2 + math.cos(a) * rr * big, big / 2 + math.sin(a) * rr * big))
            draw.line(points, fill=255, width=int(rng.integers(2, 5)), joint="curve")
        glow = lines.filter(ImageFilter.GaussianBlur(6))
        crisp = np.asarray(lines.resize((FRAME, FRAME), Image.LANCZOS), np.float32) / 255
        soft = np.asarray(glow.resize((FRAME, FRAME), Image.LANCZOS), np.float32) / 255
        alpha = np.clip(crisp + soft * 1.6, 0, 1)
        frames.append(rgba(np.clip(0.55 + crisp, 0, 1), alpha))
    return sheet(frames)


def ink_burst(rng):
    """Splash of 'ink' that spreads fast, then breaks into holes and fades. Tint it dark."""
    r, theta = polar(FRAME)
    edge_noise = value_noise(FRAME, 10, rng)
    hole_noise = fbm(FRAME, rng, octaves=4, base=5)
    angular = np.zeros_like(r)
    for _ in range(9):
        angle = rng.uniform(-math.pi, math.pi)
        width = rng.uniform(0.15, 0.4)
        delta = np.abs((theta - angle + math.pi) % (2 * math.pi) - math.pi)
        angular = np.maximum(angular, rng.uniform(0.2, 0.5) * np.clip(1 - delta / width, 0, 1) ** 2)
    frames = []
    for f in range(GRID * GRID):
        t = f / (GRID * GRID - 1)
        radius = 0.12 + 0.3 * ease_out(t * 2.2)
        reach = radius * (1 + 0.35 * (edge_noise - 0.5) + angular * (0.6 + t))
        body = smoothstep(reach, reach - 0.02, r)
        holes = smoothstep(t * 1.05 - 0.1, t * 1.05 + 0.05, hole_noise + 0.3 * (1 - r / 0.5))
        alpha = body * holes * (1 - 0.3 * t)
        intensity = 0.75 + 0.25 * smoothstep(reach - 0.06, reach, r)
        frames.append(rgba(intensity, alpha))
    return sheet(frames)


def ground_crack(rng, size=512):
    """Radial crack web seen from above: jagged branching fissures with a dark-edged glow. Lay it flat."""
    big = size * 2
    lines = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(lines)

    def fissure(x, y, angle, length, width, depth):
        # Straight jagged runs with sharp kinks, tapering to a hairline.
        steps = max(4, int(length / 24))
        for i in range(steps):
            angle += rng.normal(0, 0.12) + (rng.choice([-1, 1]) * rng.uniform(0.3, 0.6) if rng.random() < 0.2 else 0)
            nx = x + math.cos(angle) * length / steps
            ny = y + math.sin(angle) * length / steps
            w = max(1, int(width * (1 - i / steps) ** 0.8))
            draw.line([(x, y), (nx, ny)], fill=255, width=w)
            x, y = nx, ny
            if depth < 1 and rng.random() < 0.15:
                fissure(x, y, angle + rng.choice([-1, 1]) * rng.uniform(0.5, 1.0), length * 0.4, w * 0.7, depth + 1)

    for i in range(9):
        angle = 2 * math.pi * i / 9 + rng.uniform(-0.25, 0.25)
        fissure(big / 2, big / 2, angle, big * rng.uniform(0.28, 0.46), rng.uniform(12, 20), 0)
    crisp = np.asarray(lines.resize((size, size), Image.LANCZOS), np.float32) / 255
    glow = np.asarray(lines.filter(ImageFilter.GaussianBlur(5)).resize((size, size), Image.LANCZOS), np.float32) / 255
    r, _ = polar(size)
    fade = smoothstep(0.5, 0.3, r)
    pit = np.exp(-((r / 0.07) ** 2))
    alpha = np.clip((crisp + glow * 0.5 + pit) * fade, 0, 1)
    intensity = np.clip(0.35 + 0.65 * (crisp + pit), 0, 1)
    return rgba(intensity, alpha)


def shock_ring(rng):
    """Thick ring that bursts outward, thins and tears apart. Lay it flat or face the camera."""
    r, theta = polar(FRAME)
    tear = fbm(FRAME, rng, octaves=3, base=6)
    streak = value_noise(FRAME * 2, 90, rng)[::2, ::2]
    streak_t = np.interp((theta + math.pi) / (2 * math.pi), np.linspace(0, 1, FRAME), streak[0])
    frames = []
    for f in range(GRID * GRID):
        t = f / (GRID * GRID - 1)
        radius = 0.08 + 0.37 * ease_out(t * 1.4)
        width = 0.09 * (1 - t) ** 1.2 + 0.006
        d = r - radius
        band = smoothstep(width, 0, np.abs(d)) * (0.6 + 0.4 * smoothstep(-width, 0, d))
        holes = smoothstep(t - 0.15, t + 0.1, tear * 0.9 + 0.1)
        alpha = band * holes * (0.7 + 0.3 * streak_t)
        intensity = 0.6 + 0.4 * smoothstep(-width * 0.2, width * 0.6, d)
        frames.append(rgba(intensity, alpha))
    return sheet(frames)


def dust_puff(rng):
    """Billowing cloud that swells and thins into wisps; particles tint it (dark only on high-tier effects)."""
    r, theta = polar(FRAME)
    lumps = fbm(FRAME, rng, octaves=5, base=3)
    detail = fbm(FRAME, rng, octaves=4, base=8)
    frames = []
    for f in range(GRID * GRID):
        t = f / (GRID * GRID - 1)
        radius = 0.16 + 0.24 * ease_out(t * 1.6)
        reach = radius * (0.75 + 0.5 * lumps)
        body = smoothstep(reach, reach - 0.12, r)
        thin = smoothstep(t * 0.9 - 0.05, t * 0.9 + 0.2, detail)
        alpha = body * thin * (1 - 0.35 * t)
        intensity = 0.55 + 0.45 * (1 - r / 0.5) * detail
        frames.append(rgba(intensity, alpha))
    return sheet(frames)


def speed_lines(rng):
    """Radial streaks toward the frame edge with an empty centre, for Random mode on screen."""
    r, theta = polar(FRAME)
    frames = []
    for _ in range(GRID * GRID):
        field = np.zeros_like(r)
        for _ in range(int(rng.integers(14, 24))):
            angle = rng.uniform(-math.pi, math.pi)
            width = rng.uniform(0.004, 0.014)
            inner = rng.uniform(0.28, 0.4)
            delta = np.abs((theta - angle + math.pi) % (2 * math.pi) - math.pi)
            line = np.clip(1 - delta / width, 0, 1) * smoothstep(inner, inner + 0.08, r)
            field = np.maximum(field, line)
        frames.append(rgba(np.ones_like(r), field * smoothstep(0.72, 0.6, r)))
    return sheet(frames)


def flame_tongue(rng):
    """Licking flame: a teardrop that stretches up into tongues, then burns out from the bottom."""
    ys, xs = np.mgrid[0:FRAME, 0:FRAME].astype(np.float32)
    x = (xs + 0.5) / FRAME - 0.5
    y = 1 - (ys + 0.5) / FRAME
    frames = []
    for f in range(GRID * GRID):
        t = f / (GRID * GRID - 1)
        warp = fbm(FRAME, np.random.default_rng(SEED * 100 + f), octaves=4, base=4) - 0.5
        base = 0.24 + 0.08 * t
        height = 0.4 + 0.3 * ease_out(t * 2.5)
        v = np.clip((y - base) / height, -1, 1.2)
        # Teardrop: round belly near the base, a long point on top, the point swaying sideways.
        belly = np.sqrt(np.clip(1 - (v / 0.35) ** 2, 0, 1))
        half = 0.2 * (1 - 0.3 * t) * np.where(v < 0, belly, (1 - np.clip(v, 0, 1)) ** 1.1)
        sway = (warp * 0.5 + 0.08 * math.sin(f * 0.9)) * np.clip(v, 0, 1) ** 1.5
        d = np.abs(x - sway) - half * (0.8 + 0.6 * (warp + 0.5))
        shape = smoothstep(0.012, -0.01, d) * (v > -0.34) * (v < 1)
        burn = smoothstep(t * 1.1 - 0.15, t * 1.1 + 0.1, 0.55 * np.clip(v + 0.4, 0, 2) + warp + 0.3)
        alpha = shape * burn
        intensity = np.clip(1.1 - 0.75 * np.clip(v, 0, 1) + 0.2 * warp, 0, 1)
        core = smoothstep(0.0, -0.06, d) * (1 - np.clip(v, 0, 1))
        frames.append(rgba(np.clip(intensity * 0.8 + core * 0.4, 0, 1), alpha))
    return sheet(frames)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "assets/original/vfx"
    out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(SEED)
    textures = {
        "slash_arc_4x4.png": slash_arc(rng),
        "impact_star.png": impact_star(rng),
        "spark_streak.png": spark_streak(),
        "ring_thin.png": ring_thin(rng),
        "energy_strands_4x4.png": energy_strands(rng),
        "ink_burst_4x4.png": ink_burst(rng),
    }
    # Later textures draw from their own seeds so adding one never changes the ones above.
    textures |= {
        "ground_crack.png": ground_crack(np.random.default_rng(SEED + 1)),
        "shock_ring_4x4.png": shock_ring(np.random.default_rng(SEED + 2)),
        "dust_puff_4x4.png": dust_puff(np.random.default_rng(SEED + 3)),
        "speed_lines_4x4.png": speed_lines(np.random.default_rng(SEED + 4)),
        "flame_tongue_4x4.png": flame_tongue(np.random.default_rng(SEED + 5)),
    }
    for name, image in textures.items():
        image.save(out / name, optimize=True)
        print(f"wrote {out / name} {image.size[0]}x{image.size[1]}")


if __name__ == "__main__":
    main()
