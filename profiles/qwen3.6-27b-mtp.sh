# profiles/qwen3.6-27b-mtp.sh — Qwen 3.6 27B MTP (UD-Q4_K_XL, text-only)
#
# Dense 27B flagship with MTP (Multi-Token Prediction) support for ~1.4-2x
# faster speculative decoding. Top agentic-coding performance at its weight
# class. Hybrid reasoning model with thinking preservation.
# Architecture: qwen35 | Max context: 262144 | Reasoning: yes | Vision: no
#
# Vision (--mmproj) is intentionally excluded: the MTP PR branch for llama.cpp
# does not support --mmproj. Use profiles/qwen3.6-27b.sh for vision support.

REPO="unsloth/Qwen3.6-27B-MTP-GGUF"
FILES=("Qwen3.6-27B-UD-Q4_K_XL.gguf")

# Runtime defaults — native llama-server flags.
# Baked into the image; overridable at `podman run` time via -- args.
#
# Context capped at 131072: native max is 262144 but 32GB VRAM leaves ~10GB
# for KV cache at UD-Q4_K_XL; 131072 keeps that budget comfortable.
#
# Sampling params per Unsloth Qwen3.6 docs (thinking mode, general tasks):
#   temperature=1.0, top_p=0.95, top_k=20, min_p=0.0, presence_penalty=1.5
# For precise coding/WebDev use `-- --temperature 0.6 --presence-penalty 0.0`.
#
# MTP: --spec-type draft-mtp activates multi-token prediction speculative
# decoding. --spec-draft-n-max 2 is the Unsloth-recommended sweet spot:
# acceptance rate drops from ~83% to ~50% at 4 draft tokens, making 2 optimal.
# (llama.cpp renamed --spec-type mtp → draft-mtp on 2026-05-13; requires a
# recent build or release binary.)
DEFAULTS=(
    --n-predict 32768
    --n-gpu-layers 999
    --flash-attn on
    --temperature 1.0
    --top-k 20
    --min-p 0.0
    --top-p 0.95
    --presence-penalty 1.5
    --reasoning on
    --spec-type draft-mtp
    --spec-draft-n-max 2
)
