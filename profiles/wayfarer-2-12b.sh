# profiles/wayfarer-2-12b.sh — Wayfarer 2 12B (Q4_K_M)
#
# Roleplay / text adventure model by Latitude Games, fine-tuned from
# Mistral Nemo 12B. No vision, no reasoning. Nemo architecture is
# sensitive to high temperatures — sampling defaults from the model card.
# Architecture: llama | Max context: 131072 | Reasoning: no | Vision: no

REPO="LatitudeGames/Wayfarer-2-12B-GGUF"
FILES=("Wayfarer-2-12B-Q4_K_M.gguf")

# Runtime defaults — native llama-server flags.
# Passed directly to llama-server; overridable at run time via -- args.
# Sampling values from model card recommendations.
#
# No --ctx-size set: llama-server auto-fits to available VRAM (native max is
# 131072). With a container backend (--cuda/--cuda12), pass `-- --ctx-size N`
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
