# profiles/qwopus3.6-27b-v2-mtp.sh — Qwopus 3.6 27B v2 MTP (Q5_K_M, text-only)
#
# Qwen3.6-27B fine-tune with reconstructed reasoning traces, focused on coding,
# DevOps, math, and structured output. MTP heads give ~1.66x generation speedup
# over the base model. Benchmarked at 10.46 T/s vs 6.29 T/s for Qwen3.6-27B.
# Architecture: qwen3_6 | Max context: 262144 | Reasoning: yes | Vision: no

REPO="Jackrong/Qwopus3.6-27B-v2-MTP-GGUF"
FILES=("Qwopus3.6-27B-v2-MTP-Q5_K_M.gguf")
TEMPLATE="qwen-fixed-chat-template.jinja"

# Runtime defaults — native llama-server flags.
# Passed directly to llama-server; overridable at run time via -- args.
#
# Q5_K_M weighs 19.5 GB, leaving ~12.5 GB on 32 GB VRAM for KV cache.
# --cache-type-k q8_0 halves K-cache memory vs fp16; empirically fits ~120k
# context on this hardware. No --ctx-size set: llama-server auto-fits to
# available VRAM. When running via serve.sh (container), pass
# `-- --ctx-size 110000` since the container cannot see host VRAM.
#
# Sampling params per model card benchmark (temp=1.0, top_p=0.95).
# For precise coding tasks use `-- --temperature 0.6 --presence-penalty 0.0`.
#
# MTP: --spec-type draft-mtp activates multi-token prediction speculative
# decoding. --spec-draft-n-max 2 is the recommended sweet spot.
DEFAULTS=(
    --n-predict 32768
    --n-gpu-layers 999
    --flash-attn on
    --cache-type-k q8_0
    --temperature 1.0
    --top-k 20
    --min-p 0.0
    --top-p 0.95
    --presence-penalty 1.5
    --reasoning on
    --spec-type draft-mtp
    --spec-draft-n-max 2
)
