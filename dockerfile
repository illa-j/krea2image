FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG HF_TOKEN=""

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/src

# System deps (use nodesource for recent Node.js)
RUN apt-get update && apt-get install -y \
    git python3 python3-pip dos2unix wget curl \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender-dev \
    libffi-dev libssl-dev \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Symlinks
RUN ln -sf /usr/bin/python3 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# Install ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /comfyui
WORKDIR /comfyui
RUN pip install --no-cache-dir -r requirements.txt

# PyTorch with CUDA 12.4 support (AFTER ComfyUI requirements to override if needed)
RUN pip install --no-cache-dir \
    torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# Install comfy-cli
RUN pip install --no-cache-dir comfy-cli

# Set ComfyUI path for comfy commands
ENV COMFYUI_PATH=/comfyui

# Install ComfyUI-Manager (required by comfy CLI)
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git /comfyui/custom_nodes/ComfyUI-Manager
RUN cd /comfyui/custom_nodes/ComfyUI-Manager && pip install --no-cache-dir -r requirements.txt

# Custom nodes
RUN comfy node install --exit-on-fail comfyui-krea2edit --mode remote

# Models (download into the image)
RUN set -eux; \
    BACKOFFS="10 20 30 60 90"; \
    download() { \
      url="$1"; rel="$2"; fname="$3"; \
      for i in 1 2 3 4 5; do \
        HF_TOKEN="$HF_TOKEN" comfy model download --url "$url" --relative-path "$rel" --filename "$fname" && break; \
        if [ "$i" -eq 5 ]; then echo "model-download failed after 5 attempts: $url" >&2; exit 1; fi; \
        SLEEP=$(echo "$BACKOFFS" | cut -d ' ' -f "$i"); \
        echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; \
        sleep "$SLEEP"; \
      done; \
    }; \
    download "https://huggingface.co/artsyww/KREA2REALVAE/resolve/main/krea2RealVae_v10.safetensors" \
             "models/vae" "krea2RealVae_v10.safetensors"; \
    download "https://huggingface.co/alienmafio/my-krea2-loras/resolve/main/qwen3VL4BAbliteratedComfyui_v10.safetensors" \
             "models/text_encoders" "qwen3VL4BAbliteratedComfyui_v10.safetensors"; \
    download "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_turbo_bf16.safetensors" \
             "models/checkpoints" "krea2TurboOfficialComfy_krea2TurboBf16.safetensors"; \
    download "https://huggingface.co/conradlocke/krea2-identity-edit/resolve/main/krea2_identity_edit_v1_2.safetensors" \
             "models/loras" "krea2_identity_edit_v1_2.safetensors"; \
    download "https://huggingface.co/Kutches/Kr3a/resolve/main/krea2_thickness.safetensors" \
             "models/loras" "krea2_thickness.safetensors"; \
    download "https://huggingface.co/yufusoft/realism_engine_krea2_v3.1/resolve/main/realism_engine_krea2_v3.1.safetensors" \
             "models/loras" "realism_engine_krea2_v3.1.safetensors"

# Install runpod serverless worker
RUN pip install --no-cache-dir "runpod[all]"

# Copy worker source
COPY src/ /src/

# Copy model paths config to ComfyUI root (where it looks for it)
COPY volume/extra_model_paths.yaml /comfyui/extra_model_paths.yaml
COPY custom/ /custom/

# Install python deps for handler
RUN pip install --no-cache-dir -r /src/requirements.txt

# Fix line endings + executable for scripts
RUN find /src -name '*.py' -exec dos2unix {} + && \
    dos2unix /src/start.sh && chmod +x /src/start.sh

EXPOSE 8188

CMD ["/src/start.sh"]
