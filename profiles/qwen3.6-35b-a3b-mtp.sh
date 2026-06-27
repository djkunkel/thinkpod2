# profiles/qwen3.6-35b-a3b-mtp.sh — Qwen 3.6 35B-A3B MTP (UD-Q4_K_M + vision)
#
# MoE model: 35B total parameters, only 3B activated per token.
# Decode speed is comparable to a ~4B dense model despite 35B-level quality.
# MTP weights are baked into the main GGUFs (no separate drafter file needed).
# Focused on agentic coding, improved thinking preservation, and vision.
# Architecture: qwen3_5_moe | Max context: 262144 | Reasoning: yes | Vision: yes

REPO="unsloth/Qwen3.6-35B-A3B-MTP-GGUF"
FILES=("Qwen3.6-35B-A3B-UD-Q4_K_M.gguf" "mmproj-F16.gguf")

# Runtime defaults — native llama-server flags.
# Passed directly to llama-server; overridable at run time via -- args.
#
# Context capped at 131072: native max is 262144 but 32GB VRAM leaves ~10GB
# for KV cache at UD-Q4_K_M; 131072 keeps that budget comfortable.
#
# Sampling params per official model card (thinking mode, general tasks):
#   temperature=1.0, top_p=0.95, top_k=20, presence_penalty=1.5
#
# MTP: --spec-type draft-mtp activates multi-token prediction speculative
# decoding. MTP weights are embedded in the main GGUF (no separate drafter).
# --spec-draft-n-max 2 is the Unsloth-recommended starting point; try 1-6
# and pick the fastest for your hardware. MTP adds ~2 GB RAM/VRAM overhead.
# (llama.cpp renamed --spec-type mtp → draft-mtp on 2026-05-13; requires a
# recent build or release binary.)
DEFAULTS=(
    --n-predict 32768
    --n-gpu-layers 999
    --flash-attn on
    --temperature 1.0
    --top-k 20
    --top-p 0.95
    --presence-penalty 1.5
    --reasoning on
    --spec-type draft-mtp
    --spec-draft-n-max 2
    --jinja
)
