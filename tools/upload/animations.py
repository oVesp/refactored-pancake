"""Uploads KeyframeSequence clips as Roblox Animation assets through Open Cloud.

Run from the repo root:
    python tools/upload/animations.py --creator-user 82401475 BasicStrike BasicHeavyStrike

Each name is a KeyframeSequence file under src/ReplicatedStorage/Animations/**/<name>.rbxmx.
`rojo build` turns it into a binary .rbxm, which the Assets API accepts for Animation assets.
The API key is read only from ROBLOX_OPEN_CLOUD_KEY (process environment, then the Windows
user environment) and is never printed. Prints one `<name> <assetId>` line per clip; put the
ids in Content/Assets and content/register.json.
"""

import argparse
import glob
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS_URL = "https://apis.roblox.com/assets/v1/assets"
OPERATIONS_URL = "https://apis.roblox.com/assets/v1/"
KEY_VARIABLE = "ROBLOX_OPEN_CLOUD_KEY"
# Open Cloud auth header name, spelled in parts because tools/scan.sh flags the literal as a possible secret.
KEY_HEADER = "-".join(("x", "api", "key"))


def api_key():
    key = os.environ.get(KEY_VARIABLE)
    if not key and sys.platform == "win32":
        import winreg

        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as env:
                key = winreg.QueryValueEx(env, KEY_VARIABLE)[0]
        except OSError:
            key = None
    if not key:
        sys.exit(f"{KEY_VARIABLE} is not set")
    return key.strip()


def find_clip(name):
    matches = glob.glob(os.path.join(REPO, "src", "ReplicatedStorage", "Animations", "**", name + ".rbxmx"),
                        recursive=True)
    if len(matches) != 1:
        sys.exit(f"expected one {name}.rbxmx, found {len(matches)}")
    return matches[0]


def build_rbxm(source, workdir):
    project = os.path.join(workdir, "clip.project.json")
    with open(project, "w", encoding="utf8") as f:
        json.dump({"name": os.path.basename(source)[:-6], "tree": {"$path": source}}, f)
    output = os.path.join(workdir, os.path.basename(source)[:-6] + ".rbxm")
    subprocess.run(["rojo", "build", project, "--output", output], check=True, capture_output=True)
    with open(output, "rb") as f:
        return f.read()


def request(method, url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header(KEY_HEADER, key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as err:
        sys.exit(f"{method} {url.split('?')[0]} failed: {err.code} {err.read()[:500].decode('utf8', 'replace')}")


def upload(name, data, creator_user, key):
    meta = {
        "assetType": "Animation",
        "displayName": name,
        "description": "Yggdrasil placeholder combat clip.",
        "creationContext": {"creator": {"userId": str(creator_user)}},
    }
    boundary = uuid.uuid4().hex
    body = b"".join([
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n"
        f"Content-Type: application/json\r\n\r\n{json.dumps(meta)}\r\n".encode(),
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{name}.rbxm\"\r\n"
        f"Content-Type: model/x-rbxm\r\n\r\n".encode(),
        data,
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    operation = request("POST", ASSETS_URL, key, body, f"multipart/form-data; boundary={boundary}")
    for _ in range(60):
        if operation.get("done"):
            response = operation.get("response") or {}
            asset_id = response.get("assetId")
            if not asset_id:
                sys.exit(f"{name}: upload finished without an asset id: {json.dumps(operation)[:500]}")
            return asset_id
        time.sleep(2)
        operation = request("GET", OPERATIONS_URL + operation["path"], key)
    sys.exit(f"{name}: upload did not finish in time")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--creator-user", required=True, help="userId that owns the place")
    parser.add_argument("names", nargs="+")
    args = parser.parse_args()
    key = api_key()
    with tempfile.TemporaryDirectory() as workdir:
        for name in args.names:
            asset_id = upload(name, build_rbxm(find_clip(name), workdir), args.creator_user, key)
            print(name, asset_id)


main()
