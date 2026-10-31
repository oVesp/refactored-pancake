"""Contact sheets of the VFX Studio texture library (docs/art/vfx-library.md, "VFX Studio library").

The library is a registry of Roblox asset ids on GitHub, with no image files. This tool reads the
registry, fetches Roblox thumbnails and composes them into numbered sheets, so textures can be seen
while planning effects. Everything it writes stays in the git-ignored .cache/vfxstudio/: the license
forbids sharing the dataset or assets, so never commit, publish or upload its output. Sheets are
previews only and never a texture source.

Usage:
  python tools/vfxlib/vfxlib.py sync                  fetch the registry and all thumbnails (resumable)
  python tools/vfxlib/vfxlib.py sheets                write sheets/<Group>_NN.png and sheets/INDEX.md
  python tools/vfxlib/vfxlib.py show <Group> <n>      write a 700 px preview of one sheet cell
  python tools/vfxlib/vfxlib.py show <assetId>        same, by asset id

A group is a keyword and kind, such as Fire_static or Fire_flipbook.
  python tools/vfxlib/vfxlib.py search <text>         find entries by name
"""

import json
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REGISTRY_URL = "https://raw.githubusercontent.com/Sytranom/VFXStudio/main/"
THUMBNAIL_URL = "https://thumbnails.roblox.com/v1/assets?assetIds={}&size={}&format=Png&isCircular=false"

CACHE = Path(__file__).resolve().parents[2] / ".cache" / "vfxstudio"
THUMBS = CACHE / "thumbs"
SHEETS = CACHE / "sheets"
PREVIEWS = CACHE / "show"
INDEX = CACHE / "index.json"
STATES = CACHE / "states.json"

BATCH = 100
WORKERS = 8
PENDING_PASSES = 4
COLUMNS = 8
ROWS = 8
TILE = 160
LABEL = 18
# Mid-dark, so white-on-alpha textures show and dark ones do not vanish entirely.
BACKGROUND = (48, 48, 56)


def fetch(url, attempts=6):
    """GET a URL, backing off on rate limits and transient server errors."""
    request = urllib.request.Request(url, headers={"User-Agent": "yggdrasil-vfxlib"})
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except (urllib.error.URLError, TimeoutError) as err:
            status = getattr(err, "code", None)
            if status is not None and status != 429 and status < 500:
                raise
            if attempt == attempts - 1:
                raise
            time.sleep(2**attempt)
    raise AssertionError("unreachable")


def parse_lua(text):
    """Read texturedata.lua as data with regexes; the file is never executed."""
    templates = {}
    for match in re.finditer(r'^\s*\[(\d+)\] = \{(?:(\d+), )?"(\w+)"\},?\s*$', text, re.M):
        templates[match[1]] = (int(match[2]) if match[2] else None, match[3])
    entries = {}
    pattern = r'^\s*\["(\d+)"\] = \{t\[(\d+)\](?:, (\d+))?(?:, \{(.*)\})?\},?\s*$'
    for match in re.finditer(pattern, text, re.M):
        grid, keyword = templates[match[2]]
        name = re.search(r'Name = "((?:[^"\\]|\\.)*)"', match[4] or "")
        entries[match[1]] = {
            "Keywords": [keyword],
            "Name": name[1] if name else "",
            "Grid": grid,
            "Resolution": int(match[3]) if match[3] else (1024 if grid else None),
        }
    return entries


def build_index():
    """Union of both registry files; VFXData.json wins and texturedata.lua fills the gaps."""
    data = json.loads(fetch(REGISTRY_URL + "VFXData.json"))
    lua = parse_lua(fetch(REGISTRY_URL + "texturedata.lua").decode("utf-8"))
    index = {}
    for asset_id in sorted(set(data) | set(lua), key=int):
        entry = dict(lua.get(asset_id, {}))
        entry.update(data.get(asset_id, {}))
        entry["Source"] = "both" if asset_id in data and asset_id in lua else ("json" if asset_id in data else "lua")
        index[asset_id] = entry
    return index


def thumb_size(entry):
    # Flipbook frames are unreadable at the small size.
    return "420x420" if entry.get("Grid") else "150x150"


def save_thumb(asset_id, url):
    path = THUMBS / f"{asset_id}.png"
    temporary = path.with_suffix(".part")
    temporary.write_bytes(fetch(url))
    temporary.replace(path)


def fetch_batch(ids, size, states):
    """Download one batch, recording each id's state. Returns the ids still pending."""
    result = json.loads(fetch(THUMBNAIL_URL.format(",".join(ids), size)))
    pending = []
    downloads = []
    for item in result["data"]:
        asset_id = str(item["targetId"])
        state = item["state"]
        if state == "Completed" and item.get("imageUrl"):
            downloads.append((asset_id, item["imageUrl"]))
        elif state == "Pending":
            pending.append(asset_id)
        states[asset_id] = state
    with ThreadPoolExecutor(WORKERS) as pool:
        list(pool.map(lambda job: save_thumb(*job), downloads))
    return pending


def sync():
    THUMBS.mkdir(parents=True, exist_ok=True)
    index = build_index()
    INDEX.write_text(json.dumps(index, indent=1), encoding="utf-8")
    states = json.loads(STATES.read_text(encoding="utf-8")) if STATES.exists() else {}
    todo = {}
    for asset_id, entry in index.items():
        if not (THUMBS / f"{asset_id}.png").exists() and states.get(asset_id) != "Blocked":
            todo.setdefault(thumb_size(entry), []).append(asset_id)
    print(f"{len(index)} entries, {sum(map(len, todo.values()))} thumbnails to fetch", flush=True)
    for size, ids in todo.items():
        for pass_number in range(PENDING_PASSES):
            pending = []
            for start in range(0, len(ids), BATCH):
                pending += fetch_batch(ids[start : start + BATCH], size, states)
                STATES.write_text(json.dumps(states), encoding="utf-8")
                print(f"{size} pass {pass_number + 1}: {min(start + BATCH, len(ids))}/{len(ids)}", flush=True)
            ids = pending
            if not ids:
                break
            time.sleep(10)
    counts = {}
    for state in states.values():
        counts[state] = counts.get(state, 0) + 1
    print("states:", counts)


def load_index():
    if not INDEX.exists():
        sys.exit("no index: run sync first")
    return json.loads(INDEX.read_text(encoding="utf-8"))


def by_group(index):
    """Group to ids in numeric order, so a cell number stays put when newer ids are added."""
    groups = {}
    for asset_id in sorted(index, key=int):
        kind = "flipbook" if index[asset_id].get("Grid") else "static"
        for keyword in index[asset_id].get("Keywords", ["Other"]):
            groups.setdefault(f"{keyword}_{kind}", []).append(asset_id)
    return groups


def open_on_background(path, size):
    image = Image.open(path).convert("RGBA")
    image.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), BACKGROUND + (255,))
    canvas.alpha_composite(image, ((size - image.width) // 2, (size - image.height) // 2))
    return canvas


def draw_sheet(cells, index, font):
    rows = (len(cells) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGB", (COLUMNS * TILE, rows * (TILE + LABEL)), (0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    for position, (number, asset_id) in enumerate(cells):
        x = position % COLUMNS * TILE
        y = position // COLUMNS * (TILE + LABEL)
        grid = index[asset_id].get("Grid")
        draw.text((x + 3, y + 1), f"{number}  {grid}x{grid}" if grid else str(number), fill="white", font=font)
        path = THUMBS / f"{asset_id}.png"
        if path.exists():
            try:
                sheet.paste(open_on_background(path, TILE - 2).convert("RGB"), (x + 1, y + LABEL))
                continue
            except OSError:
                pass
        draw.text((x + 3, y + LABEL + 4), "no thumbnail", fill=(255, 110, 110), font=font)
    return sheet


def sheets():
    index = load_index()
    SHEETS.mkdir(parents=True, exist_ok=True)
    font = ImageFont.load_default(size=14)
    per_sheet = COLUMNS * ROWS
    summary = ["# VFX Studio contact sheets", "", "| Group | Textures | Sheets |", "| --- | --- | --- |"]
    for group, ids in sorted(by_group(index).items()):
        pages = (len(ids) + per_sheet - 1) // per_sheet
        for page in range(pages):
            first = page * per_sheet
            cells = [(first + offset, asset_id) for offset, asset_id in enumerate(ids[first : first + per_sheet])]
            draw_sheet(cells, index, font).save(SHEETS / f"{group}_{page + 1:02d}.png", optimize=True)
            sidecar = {str(number): {"id": asset_id, **index[asset_id]} for number, asset_id in cells}
            (SHEETS / f"{group}_{page + 1:02d}.json").write_text(json.dumps(sidecar, indent=1), encoding="utf-8")
        summary.append(f"| {group} | {len(ids)} | {pages} |")
        print(f"{group}: {len(ids)} textures, {pages} sheets", flush=True)
    (SHEETS / "INDEX.md").write_text("\n".join(summary) + "\n", encoding="utf-8")


def show(args):
    index = load_index()
    if len(args) == 2:
        asset_id = by_group(index)[args[0]][int(args[1])]
    else:
        asset_id = args[0]
    entry = index.get(asset_id, {})
    result = json.loads(fetch(THUMBNAIL_URL.format(asset_id, "700x700")))["data"][0]
    if result["state"] != "Completed":
        sys.exit(f"{asset_id}: thumbnail state {result['state']}")
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    raw = PREVIEWS / f"{asset_id}.raw.png"
    raw.write_bytes(fetch(result["imageUrl"]))
    path = PREVIEWS / f"{asset_id}.png"
    open_on_background(raw, 700).convert("RGB").save(path)
    raw.unlink()
    print(json.dumps({"id": asset_id, **entry}))
    print(path)


def search(text):
    index = load_index()
    for group, ids in sorted(by_group(index).items()):
        for number, asset_id in enumerate(ids):
            if text.lower() in index[asset_id].get("Name", "").lower():
                print(f"{group} {number}\t{asset_id}\t{index[asset_id]['Name']}")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    args = sys.argv[2:]
    if command == "sync":
        sync()
    elif command == "sheets":
        sheets()
    elif command == "show" and len(args) in (1, 2):
        show(args)
    elif command == "search" and len(args) == 1:
        search(args[0])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
