"""Uploads the low-poly prop library (build/world_props.fbx) to Roblox as a Model asset.

    python tools/worldgen/props.py upload --creator-user 82401475
    python tools/worldgen/props.py status

The FBX comes from tools/blender/world_props.py. The asset id and the FBX hash go to
content/world/props.json; an upload is skipped when the hash is unchanged. In Studio, import the
asset into ServerStorage.WorldProps with `require(game.ServerStorage.WorldGen.Sections).ImportProps()`
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

FBX = os.path.join("build", "world_props.fbx")
GEOMETRY_SHA = os.path.join("build", "world_props.sha")  # written by world_props.py
MANIFEST = os.path.join("content", "world", "props.json")


def geometry_sha():
    """Hash of the library's geometry; the FBX itself changes on every export (timestamps)."""
    with open(GEOMETRY_SHA, encoding="utf-8") as f:
        return f.read().strip()


def load():
    if not os.path.exists(MANIFEST):
        return {"source": "tools/blender/world_props.py", "history": []}
    with open(MANIFEST, encoding="utf-8") as f:
        return json.load(f)


def save(manifest):
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent="\t")
        f.write("\n")


def upload(data, creator_user, key):
    meta = {
        "assetType": "Model",
        "displayName": "Yggdrasil world props",
        "description": "Low-poly prop library for the Yggdrasil zone-graph world.",
        "creationContext": {"creator": {"userId": str(creator_user)}},
    }
    boundary = uuid.uuid4().hex
    body = b"".join([
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n"
        f"Content-Type: application/json\r\n\r\n{json.dumps(meta)}\r\n".encode(),
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"world_props.fbx\"\r\n"
        f"Content-Type: model/fbx\r\n\r\n".encode(),
        data,
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    operation = anim.request("POST", anim.ASSETS_URL, key, body, f"multipart/form-data; boundary={boundary}")
    for _ in range(90):
        if operation.get("done"):
            asset_id = (operation.get("response") or {}).get("assetId")
            if not asset_id:
                sys.exit(f"upload finished without an asset id: {json.dumps(operation)[:500]}")
            return asset_id
        time.sleep(2)
        operation = anim.request("GET", anim.OPERATIONS_URL + operation["path"], key)
    sys.exit("upload did not finish in time")


def cmd_status(_args):
    manifest = load()
    if not os.path.exists(FBX):
        print(f"{FBX} missing; run tools/blender/world_props.py")
        return
    state = "live" if manifest.get("sha") == geometry_sha() else "needs-upload"
    print(f"assetId {manifest.get('assetId', '-')}: {state}")


def cmd_upload(args):
    if not os.path.exists(FBX):
        sys.exit(f"{FBX} missing; run tools/blender/world_props.py")
    manifest = load()
    digest = geometry_sha()
    if manifest.get("sha") == digest:
        print(f"unchanged, assetId {manifest['assetId']}")
        return
    with open(FBX, "rb") as f:
        asset_id = upload(f.read(), args.creator_user, anim.api_key())
    if manifest.get("assetId"):
        manifest["history"].append({"assetId": manifest["assetId"], "sha": manifest["sha"],
                                    "retired": datetime.date.today().isoformat()})
    manifest["assetId"] = str(asset_id)
    manifest["sha"] = digest
    manifest["uploaded"] = datetime.date.today().isoformat()
    save(manifest)
    print(f"uploaded, assetId {asset_id}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    p = sub.add_parser("upload")
    p.add_argument("--creator-user", required=True, help="userId that owns the place")
    args = parser.parse_args()
    {"status": cmd_status, "upload": cmd_upload}[args.command](args)


if __name__ == "__main__":
    main()
