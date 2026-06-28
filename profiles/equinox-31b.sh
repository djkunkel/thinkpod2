# profiles/equinox-31b.sh — Equinox 31B (Q4_K_M)
#
# Roleplay / text adventure model by Latitude Games, fine-tuned from Gemma 4
# 31B Instruct on a balanced blend of Wayfarer 2's dark adventures and
# Hearthfire's slice-of-life storytelling. No vision (no mmproj in the GGUF
# repo), no reasoning (thinking mode suppressed, no reasoning training data).
# Architecture: gemma4 | Max context: 262144 | Reasoning: no | Vision: no

REPO="LatitudeGames/Equinox-31B-GGUF"
FILES=("Equinox-31B-Q4_K_M.gguf")

# Runtime defaults — native llama-server flags.
# Passed directly to llama-server; overridable at run time via -- args.
# Sampling values from model card recommendations.
#
# No --ctx-size set: llama-server auto-fits to available VRAM (native max is
# 262144). With a container backend (--cuda/--cuda12), pass `-- --ctx-size N`
# since the container cannot see host VRAM.
DEFAULTS=(
    --n-predict 4096
    --n-gpu-layers 999
    --flash-attn on
    --temperature 0.8
    --repeat-penalty 1.05
    --min-p 0.025
    --reasoning off
)
