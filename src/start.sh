#!/usr/bin/env bash
set -e

# Detect volume mount path (Pods often use /workspace, Serverless often uses /runpod-volume)
if [ -d /runpod-volume/checkpoints ]; then
  VOLUME=/runpod-volume
elif [ -d /workspace/checkpoints ]; then
  VOLUME=/workspace
else
  echo "ERROR: network volume not mounted (no checkpoints in /runpod-volume or /workspace)"
  exit 1
fi

echo "Using volume at: $VOLUME"
find "$VOLUME" -mindepth 1 -maxdepth 2 -exec ls -d {} \; || true

# Link models into ComfyUI standard paths
mkdir -p /comfyui/models
rm -rf /comfyui/models/checkpoints /comfyui/models/clip /comfyui/models/loras /comfyui/models/vae

ln -s "$VOLUME/checkpoints" /comfyui/models/checkpoints
ln -s "$VOLUME/clip"        /comfyui/models/clip
ln -s "$VOLUME/loras"       /comfyui/models/loras
ln -s "$VOLUME/vae"         /comfyui/models/vae

echo "runpod-worker-comfy: Starting ComfyUI"
python3 /comfyui/main.py --disable-auto-launch --disable-metadata &

echo "runpod-worker-comfy: Starting RunPod Handler"
python3 -u /rp_handler.py
