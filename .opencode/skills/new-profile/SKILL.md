---
name: new-profile
description: Guide the user through finding a GGUF model on HuggingFace, researching recommended settings, and creating a profile for use with serve.sh or local.sh.
---

# New Profile Skill

You are helping the user create a thinkpod2 profile for a GGUF model.  This is
a multi-step interactive workflow.  Ask questions along the way — do not guess
or skip steps.

## High-level workflow

1. **Identify the model** — ask the user what they need or accept a HuggingFace
   repo name directly.
2. **Research the model** — fetch metadata from HuggingFace, inspect the model
   card, and determine recommended runtime settings.
3. **Create a profile** — write a `profiles/<name>.sh` file with the correct
   `REPO`, `FILES`, and `DEFAULTS` arrays.
4. **Show how to run it** — print the correct `serve.sh` or
   `local.sh` command for the user's hardware.

Each step is described in detail below.

---

## Step 1 — Identify the model

Ask the user one of:

- What kind of model are you looking for?  (e.g. "a small reasoning model",
  "a 70B coding model", "a roleplay model around 12B")
- Or provide a HuggingFace repo name directly (e.g. `unsloth/Qwen3-8B-GGUF`).

If the user describes what they want rather than naming a repo:

1. Search HuggingFace (via web search) for GGUF quantized models that match
   the description.  Prefer repos from well-known quantizers: **unsloth**,
   **bartowski**, **mradermacher**, **QuantFactory**.
2. Present 2-4 candidate repos with a brief description of each (parameter
   count, architecture, specialization, context length).
3. Ask the user to pick one.

Once a repo is selected, confirm it with the user before proceeding.

---

## Step 2 — Research the model

Gather the following information:

### 2a. Model metadata

Fetch the model page from HuggingFace and extract:

- **Architecture** (e.g. llama, qwen2, mistral, gemma2, phi3)
- **Parameter count**
- **Maximum context length** (from config.json or model card)
- **Chat template** — does it contain `<think>` or `enable_thinking`?
  If yes, the model supports reasoning.
- **Vision / multimodal** — are there `mmproj*.gguf` files in the repo?
- **Available quantizations** — list the GGUF files and their sizes.

### 2b. Available GGUF files

List every `.gguf` file in the repo.  Separate them into:

- **Quantization files** (the main model weights)
- **Vision projector files** (`mmproj*.gguf`)

### 2c. Recommended settings

Research the model card and any linked papers/docs for the recommended
sampling and runtime settings.  Look for:

- **Temperature** — many model cards specify a recommended temp.
- **Top-K, Top-P, Min-P** — use model card values if present.
- **Repetition / presence penalty**
- **Reasoning budget** — for reasoning models, a sensible thinking token limit.

If the model card does not specify sampling settings, use these sensible
defaults based on the model type:

| Model type      | temp | top-k | top-p | presence-penalty | reasoning |
|-----------------|------|-------|-------|------------------|-----------|
| General / chat  | 1.0  | 20    | 0.95  | 1.5              | on / 4096 |
| Code            | 0.6  | 40    | 0.95  | 0.0              | on / 4096 |
| Roleplay / RP   | 0.8  | —     | —     | 1.05 (repeat)    | off       |
| Embedding / tool | 0.0 | —     | —     | 0.0              | off       |

Present your findings to the user in a clear summary and ask them to confirm
or adjust before creating the profile.

---

## Step 3 — Create a profile

### 3a. Choose quantization and vision projector

Ask the user which quantization to use.  Recommend **Q4_K_M** as the default
for most use cases.  Mention trade-offs:

- Q4_K_M — best balance of quality and VRAM
- Q5_K_M — slightly better quality, ~20% more VRAM
- Q6_K — near-lossless, significantly more VRAM
- Q8_0 — highest quality GGUF quant, most VRAM

If the model has mmproj files, ask whether to include vision support.  If yes,
recommend **mmproj-F16.gguf** (or whatever F16 variant exists).

### 3b. Choose profile name

Auto-generate a name from the repo: strip the `-GGUF` suffix, lowercase it.
For example: `unsloth/Qwen3-8B-GGUF` becomes `qwen3-8b`.  Confirm with the
user.

### 3c. Write the profile file

Write the profile to `profiles/<name>.sh` using this exact format:

```bash
# profiles/<name>.sh — <Model Label> (<quant tag>[  + vision])
#
# <One-line description of the model.>
# Architecture: <arch> | Max context: <ctx> | Reasoning: yes/no | Vision: yes/no

REPO="<org>/<Model-GGUF>"
FILES=("<model-quant>.gguf"[ "<mmproj>.gguf"])

# Runtime defaults — native llama-server flags.
# Passed directly to llama-server; overridable at run time via -- args.
DEFAULTS=(
    --n-predict <max_predict>
    --n-gpu-layers 999
    --flash-attn on
    <sampling flags>
    --reasoning <on|off>
    [--reasoning-budget <N>]
    [--reasoning-budget-message $'\n\nOkay, I need to stop thinking and give my response now.\n']
)
```

Important rules for the profile:

- `FILES` is a **bash array** with parentheses and quoted elements.
- `DEFAULTS` is a **bash array**.  Flag-value pairs are adjacent elements
  (e.g. `--n-predict 32768` is two elements: `--n-predict` and `32768`).
- Do **not** include `--ctx-size` in profiles. `local.sh` runs let llama-server
  auto-fit context to available VRAM. For `serve.sh` (container) runs the user
  can pass `-- --ctx-size <N>` at the command line since the container cannot
  see host VRAM.
- `--n-gpu-layers 999` means "offload all layers to GPU" — always include this.
- `--flash-attn on` should always be included.
- Only include `--reasoning-budget` if reasoning is `on`.
- Include `--reasoning-budget-message` for any reasoning model that uses a
  budget — this prevents partial `<think>` block leakage when the budget is
  exhausted.  The canonical message is:
  `$'\n\nOkay, I need to stop thinking and give my response now.\n'`
- Use native llama-server flag names (e.g. `--ctx-size`, not `-c`).
- Values with embedded spaces or newlines must use `$'...'` quoting.

After writing the profile, show the user the file contents and ask for
confirmation.

---

## Step 4 — Show how to run it

Ask the user about their hardware to determine which runner to use:

- **Container + GPU (recommended for NVIDIA)** → `serve.sh`
- **Local binary (no container)** → `local.sh`

### 4a. Container runner (serve.sh)

Ask which GPU backend:

| Flag       | Backend                                  |
|------------|------------------------------------------|
| `--cuda`   | NVIDIA CUDA 13                           |
| `--cuda12` | NVIDIA CUDA 12                           |
| `--rocm`   | AMD discrete GPUs                        |
| `--vulkan` | Vulkan (AMD iGPU, Intel, broad compat)   |

Print the run command:

```bash
./serve.sh --<backend> --profile <name>
```

Mention that `--dry-run` prints the full underlying command, and that extra
llama-server flags can be passed after `--`:

```bash
./serve.sh --rocm --profile <name> -- --ctx-size 110000
```

Device flags reference (for manual `podman run` usage):

| Backend | Flags                                                                              |
|---------|------------------------------------------------------------------------------------|
| CUDA    | `--device nvidia.com/gpu=all --security-opt label=disable`                         |
| ROCm    | `--device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined --security-opt label=disable` |
| Vulkan  | `--device /dev/dri --security-opt label=disable`                                   |

All container run commands must include `--network host` (required due to a
podman rootless pasta bug with IPv6).

### 4b. Local binary runner (local.sh)

Ask which backend:

| Flag       | Backend                              |
|------------|--------------------------------------|
| `--cpu`    | CPU-only                             |
| `--rocm`   | AMD ROCm                             |
| `--vulkan` | Vulkan                               |

Note: there is no upstream Ubuntu CUDA release binary — use `serve.sh`
for NVIDIA GPU workloads.

Print the run command:

```bash
./local.sh --<backend> --profile <name>
```

The binary is downloaded automatically from the llama.cpp GitHub releases on
first use and cached under `bin/`.  The default release is `b9351`; override
with `--release TAG` or the `LLAMA_RELEASE` environment variable.

---

## Reference: existing profiles

Look at the existing profiles in `profiles/` for style and format reference.
Key files:

- `profiles/qwen3.5-4b.sh` — vision + reasoning model
- `profiles/qwen3.6-27b-mtp.sh` — MTP speculative decoding, reasoning, no vision
- `profiles/wayfarer-2-12b.sh` — roleplay model, no vision, no reasoning

## Reference: key scripts

- `serve.sh`               — run via upstream llama.cpp container, HF cache mounted
- `local.sh`               — run via downloaded llama.cpp release binary, no container
- `scripts/test-context.sh` — needle-in-haystack context window stress test
