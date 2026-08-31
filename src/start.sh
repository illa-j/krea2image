#!/usr/bin/env bash
set -euo pipefail

# Start ComfyUI in background
# Base image usually has ComfyUI at /comfyui; if not, adjust.
python3 /comfyui/main.py --listen 127.0.0.1 --port 8188 --disable-metadata --disable-auto-launch &

# Wait until ComfyUI is ready
python3 - <<'PY'
import time, requests
url="http://127.0.0.1:8188/system_stats"
for _ in range(120):
    try:
        r=requests.get(url, timeout=1)
        if r.status_code == 200:
            print("ComfyUI ready")
            raise SystemExit(0)
    except Exception:
        time.sleep(1)
print("ComfyUI did not become ready")
raise SystemExit(1)
PY

# Start Runpod handler (foreground)
exec python3 -u /src/rp_handler.py
