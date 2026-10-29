"""Uploads the world's mesh libraries to Roblox as Model assets.

    python tools/worldgen/props.py upload --creator-user 82401475 [--library props|village]
    python tools/worldgen/props.py status

Libraries:
    props    build/world_props.fbx from tools/blender/world_props.py (trees, crops, rocks)
    village  build/village_kit.glb from tools/blender/village_kit.py (MegaKit houses and props,
             kit-textured structures); its asset metadata (footprints, bounds, anchors) is copied
             into the manifest for the generator

Each library's asset id and geometry hash go to content/world/<library>.json; an upload is skipped
when the hash is unchanged. Rojo maps the manifests into WorldGen (PropsManifest, VillageManifest).
In Studio, import with `Sections.ImportProps()` and `Sections.ImportVillage()`
(docs/systems/world-generation.md). Uses the Open Cloud key from ROBLOX_OPEN_CLOUD_KEY, like
tools/anim/anim.py.
"""

import argparse
import datetime
import json
import os
import sys
import time
import uuid

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "anim"))
import anim  # noqa: E402  (shares the key lookup and request helpers)

LIBRARIES = {
    "props": {
        "file": os.path.join("build", "world_props.fbx"),
        "content_type": "model/fbx",
        "sha": os.path.join("build", "world_props.sha"),
        "manifest": os.path.join("content", "world", "props.json"),
        "source": "tools/blender/world_props.py",
        "display": "Yggdrasil world props",
        "description": "Low-poly prop library for the Yggdrasil zone-graph world.",
    },
    "village": {
        "file": os.path.join("build", "village_kit.glb"),
        "content_type": "model/gltf-binary",
        "sha": os.path.join("build", "village_kit.sha"),
        "meta": os.path.join("build", "village_kit.json"),
        "manifest": os.path.join("content", "world", "village.json"),
        "source": "tools/blender/village_kit.py",
        "display": "Yggdrasil village kit",
        "description": "MegaKit houses and props (CC0, Quaternius) and matching structures for Yggdrasil.",
    },
}


def geometry_sha(lib):
    """Hash of the library's geometry; the exported files change on every export (timestamps)."""
    with open(lib["sha"], encoding="utf-8") as f:
        return f.read().strip()


def load(lib):
    if not os.path.exists(lib["manifest"]):
        return {"source": lib["source"], "history": []}
    with open(lib["manifest"], encoding="utf-8") as f:
        return json.load(f)


def save(lib, manifest):
    os.makedirs(os.path.dirname(lib["manifest"]), exist_ok=True)
    with open(lib["manifest"], "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent="\t", sort_keys=True)
        f.write("\n")


def upload(lib, data, creator_user, key):
    meta = {
        "assetType": "Model",
        "displayName": lib["display"],
        "description": lib["description"],
        "creationContext": {"creator": {"userId": str(creator_user)}},
    }
    boundary = uuid.uuid4().hex
    filename = os.path.basename(lib["file"])
    body = b"".join([
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n"
        f"Content-Type: application/json\r\n\r\n{json.dumps(meta)}\r\n".encode(),
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{filename}\"\r\n"
        f"Content-Type: {lib['content_type']}\r\n\r\n".encode(),
        data,
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    operation = anim.request("POST", anim.ASSETS_URL, key, body, f"multipart/form-data; boundary={boundary}")
    for _ in range(120):
        if operation.get("done"):
            asset_id = (operation.get("response") or {}).get("assetId")
            if not asset_id:
                sys.exit(f"upload finished without an asset id: {json.dumps(operation)[:500]}")
            return asset_id
        time.sleep(3)
        operation = anim.request("GET", anim.OPERATIONS_URL + operation["path"], key)
    sys.exit("upload did not finish in time")


def cmd_status(_args):
    for name, lib in LIBRARIES.items():
        manifest = load(lib)
        if not os.path.exists(lib["sha"]):
            print(f"{name}: {lib['file']} not built; run {lib['source']}")
            continue
        state = "live" if manifest.get("sha") == geometry_sha(lib) else "needs-upload"
        print(f"{name}: assetId {manifest.get('assetId', '-')}: {state}")


def cmd_upload(args):
    lib = LIBRARIES[args.library]
    if not os.path.exists(lib["file"]) or not os.path.exists(lib["sha"]):
        sys.exit(f"{lib['file']} missing; run {lib['source']}")
    manifest = load(lib)
    digest = geometry_sha(lib)
    if manifest.get("sha") == digest:
        print(f"{args.library}: unchanged, assetId {manifest['assetId']}")
        return
    with open(lib["file"], "rb") as f:
        asset_id = upload(lib, f.read(), args.creator_user, anim.api_key())
    if manifest.get("assetId"):
        manifest.setdefault("history", []).append({"assetId": manifest["assetId"], "sha": manifest["sha"],
                                                   "retired": datetime.date.today().isoformat()})
    manifest["assetId"] = str(asset_id)
    manifest["sha"] = digest
    manifest["uploaded"] = datetime.date.today().isoformat()
    if "meta" in lib:
        with open(lib["meta"], encoding="utf-8") as f:
            meta = json.load(f)
        manifest["unit"] = meta["unit"]
        manifest["front"] = meta["front"]
        manifest["materials"] = meta["materials"]
        manifest["assets"] = meta["assets"]
    save(lib, manifest)
    print(f"{args.library}: uploaded, assetId {asset_id}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    p = sub.add_parser("upload")
    p.add_argument("--creator-user", required=True, help="userId that owns the place")
    p.add_argument("--library", choices=sorted(LIBRARIES), default="props")
    args = parser.parse_args()
    {"status": cmd_status, "upload": cmd_upload}[args.command](args)


if __name__ == "__main__":
    main()
