# profiles/gemma-4-31b.sh — Gemma 4 31B (UD-Q4_K_XL + vision)
#
# Google DeepMind's strongest Gemma 4 dense model. Multimodal (text + image),
# hybrid reasoning with configurable thinking mode via <|think|> system token.
# Architecture: gemma4 | Max context: 262144 | Reasoning: yes | Vision: yes

REPO="unsloth/gemma-4-31B-it-GGUF"
FILES=("gemma-4-31B-it-UD-Q4_K_XL.gguf" "mmproj-BF16.gguf")

# Runtime defaults — native llama-server flags.
# Passed directly to llama-server; overridable at run time via -- args.
#
# Sampling params per Google DeepMind / Unsloth docs:
#   temperature=1.0, top_p=0.95, top_k=64
# Presence/repetition penalty left at 0.0 per model card recommendation.
#
# Thinking mode: enabled by placing <|think|> at the start of the system
# prompt. To disable at run time: -- --chat-template-kwargs '{"enable_thinking":false}'
DEFAULTS=(
    --n-predict 32768
    --n-gpu-layers 999
    --flash-attn on
    --temperature 1.0
    --top-k 64
    --top-p 0.95
    --presence-penalty 0.0
    --reasoning on
)
