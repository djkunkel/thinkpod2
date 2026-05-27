# thinkpod2 — Agent Instructions

This repo is a lightweight llama-server launcher. It has no build system, no
tests, and no compiled code. Changes are almost always to shell scripts and
profile files.

## Repository layout

```
thinkpod2/
├── serve.sh               # Container-based launcher (podman/docker + ghcr.io image)
├── local.sh               # Direct binary launcher (downloads llama.cpp release binary)
├── profiles/              # Model profiles — one .sh file per model variant
│   └── README.md          # llama-server flag reference
├── templates/             # Custom Jinja chat templates (.jinja files)
├── scripts/
│   └── test-context.sh    # Needle-in-haystack context window stress test
├── bin/                   # Cached llama.cpp release binaries (gitignored)
└── .opencode/
    └── skills/
        └── new-profile/
            └── SKILL.md   # Skill for creating new profiles interactively
```

## Profile format

A profile is a bash file sourced by `serve.sh` and `local.sh`. It sets three
variables:

```bash
REPO="org/Model-GGUF"                      # HuggingFace repo
FILES=("Model-Q4_K_M.gguf")                # GGUF file(s); add mmproj for vision
TEMPLATE="my-chat-template.jinja"          # Optional: filename in templates/
DEFAULTS=(                                 # llama-server flags as a bash array
    --n-predict 32768
    --n-gpu-layers 999
    --flash-attn on
    --temperature 1.0
    --top-k 20
    --min-p 0.0
    --top-p 0.95
    --presence-penalty 1.5
    --reasoning on
)
```

Key rules:
- **Never include `--ctx-size`** in a profile. `local.sh` lets llama-server
  auto-fit context to available VRAM. For `serve.sh` (container) the user
  passes `-- --ctx-size <N>` at the command line since the container cannot
  introspect host VRAM.
- `FILES` and `DEFAULTS` are bash arrays — use parentheses and quoted elements.
- `TEMPLATE` is a bare filename (no path); the file must exist in `templates/`.
  Both launchers resolve it automatically and inject `--jinja --chat-template-file`.
- `--n-gpu-layers 999` and `--flash-attn on` should always be present.
- For MTP (Multi-Token Prediction) models add `--spec-type draft-mtp` and
  `--spec-draft-n-max 2`.
- For reasoning models add `--reasoning on`. Add `--reasoning-budget <N>` and
  `--reasoning-budget-message` only if a budget is needed to prevent think-block
  leakage.

## serve.sh and local.sh

Both scripts accept the same basic interface:

```bash
./serve.sh --<backend> --profile <name> [--dry-run] [-- extra llama-server flags]
./local.sh --<backend> --profile <name> [--dry-run] [-- extra llama-server flags]
```

`serve.sh` backends: `--cuda`, `--cuda12`, `--rocm`, `--vulkan`
`local.sh` backends: `--cpu`, `--rocm`, `--vulkan`

`serve.sh` also accepts `--template-dir <dir>` to mount a custom template
directory into the container at `/templates`. It defaults to `templates/` if
that directory exists.

The scripts do not exit on their own — they run llama-server in the foreground.

## Making changes

**Adding a profile:** create `profiles/<name>.sh`. Follow the format above.
Use an existing profile as a reference. Do not add `--ctx-size`.

**Adding a chat template:** place the `.jinja` file in `templates/` and set
`TEMPLATE="<filename>.jinja"` in the relevant profile(s).

**Modifying serve.sh or local.sh:** both scripts are plain bash with
`set -euo pipefail`. Always run `bash -n <script>` to syntax-check after
editing. The profile is sourced after argument parsing; variables set in the
profile (`REPO`, `FILES`, `DEFAULTS`, `TEMPLATE`) must be initialized to empty
defaults before the `source` call.

**Updating the skill:** the `new-profile` skill at
`.opencode/skills/new-profile/SKILL.md` is the authoritative guide for
creating profiles interactively. Keep it consistent with any changes to the
profile format or script behavior.

## What not to do

- Do not add a build system, Makefile, or CI pipeline unless explicitly asked.
- Do not add `--ctx-size` to profiles — llama-server auto-fits on bare metal.
- Do not hardcode VRAM budgets or context size guesses into profiles.
- Do not modify `bin/` contents (gitignored, managed by `local.sh` at runtime).
- Do not add dependencies beyond standard POSIX utilities (`bash`, `curl`, `tar`).
