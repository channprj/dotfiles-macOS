#!/usr/bin/env python3
"""Status line: cwd, model, context, and weekly limit remaining.

Network runs only when trigger is refresh_interval. Other runs read the cache.
"""

import json
import os
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
    cwd = workspace.get("current_dir") or payload.get("cwd") or ""
    name = os.path.basename(cwd.rstrip("/")) if cwd else ""
    model = (payload.get("model") or {}).get("display_name") or ""
    ctx = (payload.get("context_window") or {}).get("used_percentage")

    parts = []
    if name:
        parts.append(name)
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
