"""Animation workflow: one manifest per animation set drives the Animation instances and the register.

Run from the repo root (docs/art/animation-pipeline.md):
    python tools/anim/anim.py status
    python tools/anim/anim.py sync

Animations are authored and uploaded in Studio (Animation Editor, Publish to Roblox); the manifest
records each clip's uploaded `assetId`. `sync` writes one `Animation` instance per clip as
src/ReplicatedStorage/Animations/<Key>.model.json, drops stale ones, and rewrites the animation
rows of content/register.json. `status` lists clips without an id. A clip with `alias` copies the
asset id of the clip it names.
"""

import argparse
import glob
import json
import os
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MANIFESTS = os.path.join(REPO, "content", "animations")
OUT = os.path.join(REPO, "src", "ReplicatedStorage", "Animations")
REGISTER = os.path.join(REPO, "content", "register.json")

TIERS = ("placeholder", "final")
MARKERS = ("Hit", "Release", "Step")


def rel(path):
    return os.path.relpath(path, REPO).replace("\\", "/")


def manifests():
    out = []
    for path in sorted(glob.glob(os.path.join(MANIFESTS, "*.json"))):
        with open(path, encoding="utf8") as f:
            out.append(json.load(f))
    return out


def resolved():
    """(manifest, key, clip, assetId) for every clip, aliases resolved, with the format checked."""
    clips = {}
    for manifest in manifests():
        for key, clip in manifest["clips"].items():
            if key in clips:
                sys.exit(f"{key} is in two manifests")
            if clip["tier"] not in TIERS:
                sys.exit(f"{key}: tier must be one of {TIERS}")
            for marker in clip.get("markers", {}):
                if marker not in MARKERS:
                    sys.exit(f"{key}: marker {marker} is not one of {MARKERS}")
            clips[key] = (manifest, clip)
    rows = []
    for key, (manifest, clip) in clips.items():
        asset = clip.get("assetId")
        if not asset and clip.get("alias"):
            target = clips.get(clip["alias"])
            if not target:
                sys.exit(f"{key}: alias {clip['alias']} does not exist")
            asset = target[1].get("assetId")
        rows.append((manifest, key, clip, asset))
    return rows


def cmd_status():
    for manifest, key, clip, asset in resolved():
        if not asset:
            print(f"{manifest['set']}/{key}: no assetId")
    print("ok")


def sync():
    rows = resolved()
    os.makedirs(OUT, exist_ok=True)
    wanted = set()
    register = {}
    for manifest, key, clip, asset in rows:
        if not asset:
            continue
        name = key + ".model.json"
        wanted.add(name)
        model = {
            "className": "Animation",
            "properties": {"AnimationId": f"rbxassetid://{asset}"},
            "attributes": {"Looped": bool(clip.get("looped", False))},
        }
        with open(os.path.join(OUT, name), "w", encoding="utf8", newline="\n") as f:
            f.write(json.dumps(model, indent="\t") + "\n")
        defaults = manifest.get("defaults", {})
        register["animation:" + key] = {
            "id": "animation:" + key,
            "type": "animation",
            "name": key,
            "path": rel(os.path.join(OUT, name)),
            "set": manifest["set"],
            "tier": clip["tier"],
            "origin": clip.get("origin", defaults.get("origin")),
            "license": clip.get("license", defaults.get("license")),
            "owner": "dev",
            "notes": clip.get("notes", ""),
            "assetId": asset,
        }
    for name in os.listdir(OUT):
        if name.endswith(".model.json") and name not in wanted:
            os.remove(os.path.join(OUT, name))

    with open(REGISTER, encoding="utf8") as f:
        data = json.load(f)
    entries = []
    for entry in data["entries"]:
        if entry["id"] in register:
            row = register.pop(entry["id"])
            row["status"] = entry["status"]
            entries.append(row)
        elif not entry["id"].startswith("animation:"):
            entries.append(entry)
    for row in register.values():
        row["status"] = "draft"
        entries.append(row)
    data["entries"] = entries
    with open(REGISTER, "w", encoding="utf8", newline="\n") as f:
        f.write(json.dumps(data, indent="\t", ensure_ascii=False) + "\n")
    print(f"{len(wanted)} animations and register.json synced")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=("status", "sync"))
    args = parser.parse_args()
    cmd_status() if args.command == "status" else sync()


if __name__ == "__main__":
    main()
