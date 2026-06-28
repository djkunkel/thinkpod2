# profiles/vibethinker-3b.sh — VibeThinker 3B (Q8_0)
#
# WeiboAI's 3B reasoning model, fine-tuned from Qwen2.5-Coder-3B via the
# Spectrum-to-Signal Principle (SSP) pipeline. Specialized in verifiable
# reasoning: competitive math (AIME/HMMT/IMO-AnswerBench), coding contests
# (LiveCodeBench, LeetCode), and STEM. Punches well above its weight on
# answer-checkable tasks. Not intended for tool-calling/agents or broad
# open-domain knowledge.
# Architecture: qwen2 | Max context: 131072 | Reasoning: yes | Vision: no

REPO="mradermacher/VibeThinker-3B-GGUF"
FILES=("VibeThinker-3B.Q8_0.gguf")
TEMPLATE="qwen-fixed-chat-template.jinja"

# Runtime defaults — native llama-server flags.
# Passed directly to llama-server; overridable at run time via -- args.
#
# No --ctx-size set: llama-server auto-fits to available VRAM (native max is
# 131072). Q8_0 is only 3.29 GB so context headroom is plentiful on any GPU.
# With a container backend (--cuda/--cuda12), pass `-- --ctx-size N` since the
# container cannot see host VRAM.
#
# Sampling params per model card (vLLM benchmark config):
#   temperature=1.0, top_p=0.95, top_k=-1 (disabled), no presence penalty.
# For Qwen3-style focused chat, try `-- --top-k 20 --presence-penalty 1.5`.
#
# Template: the GGUF's built-in Qwen2.5 ChatML template has no  tag in
# the generation prompt, so llama.cpp's auto-detection fails to split reasoning
# into a separate reasoning_content stream (a known issue with models whose
# templates lack think-tag markers — see llama.cpp #23852, #20008). The
# qwen-fixed-chat-template.jinja injects  at the assistant turn, enabling
# proper reasoning/content separation. To disable thinking at run time:
#   -- --chat-template-kwargs '{"enable_thinking":false}'
#
# --n-predict 32768 is a sensible general cap; the model can reason for up to
# ~102K tokens. For hardest problems (e.g. AMO-Bench) raise it at run time:
#   `-- --n-predict 65536` (or higher, up to ~102400).
DEFAULTS=(
    --n-predict 32768
    --n-gpu-layers 999
    --flash-attn on
    --temperature 1.0
    --top-k -1
    --top-p 0.95
    --min-p 0.0
    --reasoning on
    --jinja
)
