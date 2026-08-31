FROM runpod/worker-comfyui:5.8.4-base

ARG HF_TOKEN=""
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/

# Optional but recommended to avoid bash\r issues if you edit scripts on Windows
RUN apt-get update && apt-get install -y dos2unix && rm -rf /var/lib/apt/lists/*

# Custom nodes
RUN comfy node install --exit-on-fail comfyui-krea2edit --mode remote

# Models
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
# Worker code + workflow
COPY rp_handler.py /rp_handler.py
COPY workflows/workflow_api.json /workflows/workflow_api.json
COPY requirements.txt /requirements.txt
COPY start.sh /start.sh
COPY comftroller.py uploader.py utils.py /

RUN pip install --no-cache-dir -r /requirements.txt

# Fix line endings + permissions
RUN dos2unix /start.sh && chmod +x /start.sh

CMD ["/start.sh"]
