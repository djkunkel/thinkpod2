# thinkpod2

Lightweight llama-server launcher using profiles.  No baked-in model images —
models are loaded directly from the local HuggingFace cache.

## Concepts

A **profile** (`profiles/<name>.sh`) describes a model and its runtime
defaults: the HuggingFace repo, the GGUF file(s) to load, and the
llama-server flags to pass.

Two launchers are provided:

| Script | How it works |
|--------|--------------|
| `serve.sh` | Runs the upstream `ghcr.io/ggml-org/llama.cpp` container with the HF cache mounted read-only. Best for NVIDIA (CUDA) and when you want a hermetic runtime. |
| `local.sh` | Downloads a pinned llama.cpp release binary and runs it directly. No container needed. Best for ROCm, Vulkan, or CPU workloads. |

## Quick start

### Container (serve.sh)

```bash
# NVIDIA GPU
./serve.sh --cuda --profile qwen3.5-4b

# AMD discrete GPU
./serve.sh --rocm --profile qwen3.5-4b

# Vulkan (AMD iGPU, Intel, etc.)
./serve.sh --vulkan --profile qwen3.5-4b
```

### Local binary (local.sh)

```bash
# AMD ROCm (downloads release binary on first run, cached under bin/)
./local.sh --rocm --profile qwen3.5-4b

# Vulkan
./local.sh --vulkan --profile qwen3.5-4b

# CPU-only
./local.sh --cpu --profile qwen3.5-4b
```

After starting, the server is available at `http://localhost:8080`.

### Override profile defaults at run time

Append extra llama-server flags after `--`:

```bash
./serve.sh --rocm --profile qwen3.5-4b -- --ctx-size 65536 --n-predict 8192
```

### Dry run

Print the full command without executing it:

```bash
./serve.sh --rocm --profile qwen3.5-4b --dry-run
./local.sh --rocm --profile qwen3.5-4b --dry-run
```

## Available profiles

| Profile | Model | Quant | Vision | Reasoning | Context |
|---------|-------|-------|--------|-----------|---------|
| `qwen3.5-0.8` | Qwen 3.5 0.8B | Q8_0 | yes | yes (1024) | 8192 |
| `qwen3.5-4b` | Qwen 3.5 4B | Q4_K_M | yes | yes (4096) | 131072 |
| `qwen3.5-9b` | Qwen 3.5 9B | Q6_K | yes | yes (4096) | 131072 |
| `qwen3.5-9b-q4` | Qwen 3.5 9B | Q4_K_M | yes | yes (4096) | 131072 |
| `qwen3.5-35b-a3b` | Qwen 3.5 35B-A3B (MoE) | Q4_K_M | yes | yes (4096) | 131072 |
| `qwen3.6-27b` | Qwen 3.6 27B | UD-Q4_K_XL | yes | yes | 150000 |
| `qwen3.6-27b-mtp` | Qwen 3.6 27B MTP | UD-Q4_K_XL | no | yes + MTP | — |
| `qwen3.6-35b-a3b` | Qwen 3.6 35B-A3B (MoE) | UD-Q4_K_M | yes | yes (4096) | 131072 |
| `qwopus3.6-35b-a3b-v1` | Qwopus 3.6 35B-A3B v1 | Q4_K_M | yes | yes (6000) | — |
| `wayfarer-2-12b` | Wayfarer 2 12B | Q4_K_M | no | no | 32768 |

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HF_HUB` | `~/.cache/huggingface/hub` | HuggingFace cache directory |
| `HOST` | `0.0.0.0` | Bind address |
| `PORT` | `8080` | Bind port |
| `ENGINE` | auto-detected | Container engine (`podman` or `docker`) |
| `LLAMA_RELEASE` | `b9351` | llama.cpp release tag (local.sh only) |
| `ROCM_VERSION` | `7.2` | ROCm version in asset name (local.sh only) |
| `IMAGE` | per-backend ghcr.io tag | Override container image (serve.sh only) |

## Test the context window

```bash
./scripts/test-context.sh                    # test localhost:8080 at 75% fill
./scripts/test-context.sh 9090              # different port
./scripts/test-context.sh localhost:8080 0.9  # push to 90% fill
```

## Creating a new profile

Use the `new-profile` opencode skill — it guides you through finding a model
on HuggingFace, researching the correct settings, and writing the profile file.

Alternatively, copy an existing profile and adjust the three variables:

```bash
REPO="org/Model-GGUF"
FILES=("Model-Q4_K_M.gguf")   # bash array; add "mmproj-F16.gguf" for vision
DEFAULTS=(
    --ctx-size 131072
    --n-predict 32768
    --n-gpu-layers 999
    --flash-attn on
    --temperature 1.0
    --top-k 20
    --top-p 0.95
    --presence-penalty 1.5
    --reasoning on
    --reasoning-budget 4096
    --reasoning-budget-message $'\n\nOkay, I need to stop thinking and give my response now.\n'
)
```

## Directory layout

```
thinkpod2/
├── serve.sh           # Container-based launcher
├── local.sh           # Direct binary launcher
├── profiles/          # Model profiles (one .sh file per model variant)
├── scripts/
│   └── test-context.sh    # Context window stress test
├── bin/               # Cached llama.cpp release binaries (gitignored)
└── .opencode/
    └── skills/
        └── new-profile/
            └── SKILL.md   # AI skill for creating new profiles
```
