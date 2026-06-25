# profiles/gemma-4-12b-hauhaucs-balanced.sh — Gemma 4 12B QAT Uncensored HauhauCS Balanced (Q4_K_M + MTP + vision)
#
# HauhauCS's uncensored QAT fine-tune of Gemma 4 12B. Built from official QAT
# weights (4-bit quantisation-aware-trained), so Q4_K_M stays close to
# full-precision quality. Balanced variant: optimised for agentic coding,
# reasoning, creative writing, and reliability-critical tasks. 0/465 refusals.
# Ships with an MTP draft head (~60% faster generation) and a vision projector.
# Architecture: gemma4 | Max context: 262144 | Reasoning: yes | Vision: yes
#
# Note: MTP + vision (--mmproj) may not work together depending on your llama.cpp
# build. If you encounter errors, remove the mmproj from FILES or drop MTP flags.

REPO="HauhauCS/Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced"
FILES=("Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced-Q4_K_M.gguf" "mmproj-Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced-BF16.gguf" "mtp-gemma-4-12B-it.gguf")

# Runtime defaults — native llama-server flags.
# Passed directly to llama-server; overridable at run time via -- args.
#
# Sampling params per HauhauCS model card (tuned specifically for this build):
#   temperature=0.6, top_k=64, top_p=0.9, min_p=0.05, repeat_penalty=1.1
#
# MTP: --spec-type draft-mtp activates multi-token prediction speculative
# decoding using mtp-gemma-4-12B-it.gguf as the drafter. --spec-draft-n-max 2
# is the recommended starting point; try 1-6 and pick the fastest for your
# hardware. MTP adds ~242 MB overhead.
# (llama.cpp renamed --spec-type mtp → draft-mtp on 2026-05-13; requires a
# recent build or release binary.)
DEFAULTS=(
    --n-predict 32768
    --n-gpu-layers 999
    --flash-attn on
    --temperature 0.6
    --top-k 64
    --top-p 0.9
    --min-p 0.05
    --repeat-penalty 1.1
    --reasoning on
    --spec-type draft-mtp
    --spec-draft-n-max 2
    --jinja
)
