#!/usr/bin/env python3
"""用 GitHub Contents API 逐文件推送（iSH 上 git push 常被中断，走 API 最稳）。"""
import base64
import json
import os
import subprocess
import sys

REPO = "xiaofeifei996/PlayStar"
BRANCH = "main"
ROOT = "/var/minis/workspace/PlayStar"
SKIP_DIRS = {".git", "packages", ".theos", "theos", "theos-roothide", "obj"}


def token():
    return os.environ["GITHUB_MCP_TOKEN"]


def api(method, path, payload=None):
    cmd = [
        "curl", "-s", "-m", "40", "-X", method,
        "-H", f"Authorization: Bearer {token()}",
        "-H", "Accept: application/vnd.github+json",
        f"https://api.github.com{path}",
    ]
    if payload is not None:
        cmd += ["-d", json.dumps(payload)]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    try:
        return json.loads(out) if out.strip() else {}
    except json.JSONDecodeError:
        return {"raw": out}


def remote_sha(path):
    r = api("GET", f"/repos/{REPO}/contents/{path}?ref={BRANCH}")
    if isinstance(r, dict) and r.get("sha"):
        return r["sha"]
    return None


def main():
    files = []
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in names:
            if name.endswith(".deb") or name.endswith(".log"):
                continue
            full = os.path.join(base, name)
            files.append(os.path.relpath(full, ROOT))
    files.sort()

    ok, fail = 0, []
    for path in files:
        with open(os.path.join(ROOT, path), "rb") as handle:
            content = base64.b64encode(handle.read()).decode()
        payload = {"message": f"update {path}", "content": content, "branch": BRANCH}
        sha = remote_sha(path)
        if sha:
            payload["sha"] = sha
        result = api("PUT", f"/repos/{REPO}/contents/{path}", payload)
        if isinstance(result, dict) and result.get("content"):
            ok += 1
            print(f"ok   {path}")
        else:
            fail.append((path, str(result)[:180]))
            print(f"FAIL {path}: {str(result)[:180]}")
    print(f"\n{ok} uploaded, {len(fail)} failed")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
