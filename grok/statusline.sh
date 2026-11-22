#!/usr/bin/env python3
"""Status line: project folder, diff size, model, context, weekly limit.

Network runs only when trigger is refresh_interval. Other runs read the cache.
Git diff is local and runs on every refresh.
"""

import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

CACHE = Path.home() / ".grok" / "statusline-weekly.json"
AUTH = Path.home() / ".grok" / "auth.json"
URL = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"


def load_payload():
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    return json.loads(raw)


def read_cache():
    try:
        return json.loads(CACHE.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def write_cache(data):
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    tmp = CACHE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data))
    tmp.replace(CACHE)


def fetch_weekly():
    auth = json.loads(AUTH.read_text())
    token = next(iter(auth.values()))["key"]
    version = "1.0.62"
    version_path = Path.home() / ".grok" / "version.json"
    try:
        version = json.loads(version_path.read_text()).get("version") or version
    except (OSError, json.JSONDecodeError, AttributeError):
        pass
    req = urllib.request.Request(
        URL,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "x-grok-client-version": version,
            "x-grok-client-identifier": "grok-shell",
        },
    )
    with urllib.request.urlopen(req, timeout=8) as resp:
        body = json.loads(resp.read().decode())
    config = body.get("config") or {}
    percent = config.get("creditUsagePercent")
    for item in config.get("productUsage") or []:
        if item.get("product") == "GrokBuild" and item.get("usagePercent") is not None:
            percent = item["usagePercent"]
            break
    write_cache(
        {
            "percent": percent,
            "period": (config.get("currentPeriod") or {}).get("type"),
            "fetched_at": time.time(),
        }
    )


def fmt_num(value):
    if isinstance(value, float) and abs(value - round(value)) < 0.05:
        return str(int(round(value)))
    if isinstance(value, float):
        return f"{value:.1f}".rstrip("0").rstrip(".")
    return str(value)


def location_label(workspace, payload):
    cwd = (workspace.get("current_dir") or payload.get("cwd") or "").rstrip("/")
    repo = (workspace.get("repo_root") or "").rstrip("/")
    if repo:
        project = os.path.basename(repo)
        if cwd and cwd != repo and cwd.startswith(repo + os.sep):
            return f"{project}/{os.path.relpath(cwd, repo)}"
        if project:
            return project
    if cwd:
        return os.path.basename(cwd)
    return ""


def git_root(workspace, payload):
    return (workspace.get("repo_root") or workspace.get("current_dir") or payload.get("cwd") or "").rstrip("/")


def parse_numstat(text):
    added = deleted = 0
    for line in text.splitlines():
        cols = line.split("\t")
        if len(cols) < 2:
            continue
        if cols[0].isdigit():
            added += int(cols[0])
        if cols[1].isdigit():
            deleted += int(cols[1])
    return added, deleted


def untracked_lines(repo, paths):
    added = 0
    for rel in paths[:200]:
        if not rel:
            continue
        path = os.path.join(repo, rel)
        try:
            if not os.path.isfile(path) or os.path.getsize(path) > 1_000_000:
                continue
            with open(path, "rb") as handle:
                data = handle.read()
        except OSError:
            continue
        if b"\0" in data:
            continue
        added += data.count(b"\n")
        if data and not data.endswith(b"\n"):
            added += 1
    return added


def diff_label(repo):
    if not repo or not os.path.isdir(repo):
        return None
    try:
        diff = subprocess.run(
            ["git", "-C", repo, "diff", "--numstat", "HEAD"],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
        untracked = subprocess.run(
            ["git", "-C", repo, "ls-files", "--others", "--exclude-standard", "-z"],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if diff.returncode != 0:
        return None
    added, deleted = parse_numstat(diff.stdout)
    if untracked.returncode == 0 and untracked.stdout:
        added += untracked_lines(repo, untracked.stdout.split("\0"))
    if added == 0 and deleted == 0:
        return None
    return f"\033[32m+{added}\033[0m \033[31m-{deleted}\033[0m"


def weekly_label(cache):
    if not cache or cache.get("percent") is None:
        return None
    used = cache["percent"]
    if not isinstance(used, (int, float)):
        return None
    remain = min(100, max(0, 100 - used))
    label = f"{fmt_num(remain)}% left"
    if remain <= 5:
        return f"\033[31m{label}\033[0m"
    if remain <= 20:
        return f"\033[33m{label}\033[0m"
    return label


def main():
    payload = load_payload()
    if payload.get("trigger") == "refresh_interval":
        try:
            fetch_weekly()
        except Exception:
            pass

    workspace = payload.get("workspace") or {}
    name = location_label(workspace, payload)
    model = (payload.get("model") or {}).get("display_name") or ""
    ctx = (payload.get("context_window") or {}).get("used_percentage")
    diff = diff_label(git_root(workspace, payload))

    parts = []
    if name:
        parts.append(name)
    if diff:
        parts.append(diff)
    if model:
        parts.append(model)
    if ctx is not None:
        parts.append(f"{fmt_num(ctx)}% ctx")
    label = weekly_label(read_cache())
    if label:
        parts.append(label)
    if parts:
        sys.stdout.write(" │ ".join(parts) + "\n")


if __name__ == "__main__":
    main()
