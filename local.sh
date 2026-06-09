#!/usr/bin/env bash
#
# Run llama-server directly from a pinned llama.cpp GitHub release binary,
# using settings derived from a thinkpod2 profile.
#
# Downloads the release tarball on first use and caches it under bin/ in the
# project root.  Subsequent runs use the cached binary without re-downloading.
#
# Usage:
#   ./local.sh --cpu    --profile NAME
#   ./local.sh --rocm   --profile NAME [--dry-run]
#   ./local.sh --vulkan --profile NAME [-- extra llama-server flags]
#
# Backends:
#   --cpu       Ubuntu x64 CPU-only build
#   --rocm      Ubuntu x64 ROCm build
#   --vulkan    Ubuntu x64 Vulkan build
#
# Note: There is no Ubuntu CUDA release binary. Use scripts/serve-profile.sh
#       (container-based) for NVIDIA GPU workloads.
#
# Flags after -- are forwarded to llama-server and override profile defaults.
#
# Environment:
#   LLAMA_RELEASE    llama.cpp release tag to use  (default: latest from GitHub)
#   ROCM_VERSION     ROCm version in the asset name (default: 7.2)
#   ARCH             CPU architecture override      (default: x64)
#   HF_HUB           HuggingFace cache directory   (default: ~/.cache/huggingface/hub)
#   HOST             Bind address                   (default: 0.0.0.0)
#   PORT             Bind port                      (default: 8080)
#
# Binary cache:
#   Downloaded tarballs are extracted to bin/<tag>/<backend>/ inside the
#   project root and reused on subsequent runs.  To force a re-download,
#   delete the relevant subdirectory under bin/.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

# Resolve the latest llama.cpp release tag from GitHub if no override is set.
_resolve_llama_release() {
    local fallback="b9536"
    if [[ -n "${LLAMA_RELEASE:-}" ]]; then
        echo "$LLAMA_RELEASE"
        return
    fi
    local tag
    tag="$(curl -fsSL --max-time 5 \
        "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest" \
        2>/dev/null | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
    if [[ -n "$tag" ]]; then
        echo "$tag"
    else
        echo "$fallback"
    fi
}

LLAMA_RELEASE="$(_resolve_llama_release)"
ROCM_VERSION="${ROCM_VERSION:-7.2}"
ARCH="${ARCH:-x64}"
HF_HUB="${HF_HUB:-$HOME/.cache/huggingface/hub}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"

BACKEND=""
PROFILE=""
DRY_RUN=false
EXTRA_ARGS=()

# ── Path resolution ───────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_DIR="$SCRIPT_DIR/profiles"
BIN_DIR="$SCRIPT_DIR/bin"

# ── Helpers ───────────────────────────────────────────────────────────────────

die()  { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# Return the GitHub release asset filename for the given backend.
asset_name() {
    local backend="$1"
    case "$backend" in
        cpu)    echo "llama-${LLAMA_RELEASE}-bin-ubuntu-${ARCH}.tar.gz" ;;
        vulkan) echo "llama-${LLAMA_RELEASE}-bin-ubuntu-vulkan-${ARCH}.tar.gz" ;;
        rocm)   echo "llama-${LLAMA_RELEASE}-bin-ubuntu-rocm-${ROCM_VERSION}-${ARCH}.tar.gz" ;;
    esac
}

# Human-readable backend description
backend_label() {
    case "$1" in
        cpu)    echo "CPU (Ubuntu x64)" ;;
        rocm)   echo "AMD ROCm ${ROCM_VERSION}" ;;
        vulkan) echo "Vulkan" ;;
    esac
}

# ── Argument parsing ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu)    BACKEND="cpu";    shift ;;
        --rocm)   BACKEND="rocm";   shift ;;
        --vulkan) BACKEND="vulkan"; shift ;;
        --profile)
            [[ -z "${2:-}" ]] && die "--profile requires a name (e.g. --profile qwen3.5-4b)"
            PROFILE="$2"
            shift 2
            ;;
        --release)
            [[ -z "${2:-}" ]] && die "--release requires a tag (e.g. --release b9190)"
            LLAMA_RELEASE="$2"
            shift 2
            ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h)
            echo "Usage: ./local.sh --BACKEND --profile NAME [--dry-run] [-- LLAMA_ARGS...]"
            echo ""
            echo "Run llama-server from a pinned llama.cpp release binary (no container needed)."
            echo ""
            echo "Backends:  --cpu  --rocm  --vulkan"
            echo ""
            echo "Options:"
            echo "  --profile NAME    Source profiles/<NAME>.sh for model + defaults (required)"
            echo "  --release TAG     llama.cpp release tag (default: ${LLAMA_RELEASE})"
            echo "  --dry-run         Print the command without executing it"
            echo "  -- ARGS           Forward remaining args to llama-server (override defaults)"
            echo ""
            echo "Environment:"
            echo "  LLAMA_RELEASE    Release tag          (default: latest from GitHub, resolved to ${LLAMA_RELEASE})"
            echo "  ROCM_VERSION     ROCm version in asset name (default: ${ROCM_VERSION})"
            echo "  ARCH             CPU arch             (default: ${ARCH})"
            echo "  HF_HUB           HuggingFace cache    (default: ~/.cache/huggingface/hub)"
            echo "  HOST             Bind address          (default: ${HOST})"
            echo "  PORT             Bind port             (default: ${PORT})"
            echo ""
            echo "Binary cache:"
            echo "  Binaries are cached in bin/<tag>/<backend>/ under the project root."
            echo "  Delete that directory to force a fresh download."
            echo ""
            echo "Note: No Ubuntu CUDA release binary exists upstream."
            echo "      Use serve.sh for NVIDIA GPU workloads."
            exit 0
            ;;
        --)
            shift
            EXTRA_ARGS=("$@")
            break
            ;;
        -*)
            die "unknown option: $1 (try --help)"
            ;;
        *)
            die "unexpected argument: $1 (try --help)"
            ;;
    esac
done

# ── Validate required args ────────────────────────────────────────────────────

[[ -z "$BACKEND" ]]  && die "a backend is required: --cpu, --rocm, or --vulkan"
[[ -z "$PROFILE" ]]  && die "--profile NAME is required"

profile_file="$PROFILES_DIR/${PROFILE}.sh"
[[ ! -f "$profile_file" ]] && die "profile not found: $profile_file"

# ── Source profile ────────────────────────────────────────────────────────────

REPO=""
FILES=()
DEFAULTS=()
TEMPLATE=""

# shellcheck source=/dev/null
source "$profile_file"

[[ -z "$REPO" ]]         && die "profile $PROFILE did not set REPO"
[[ ${#FILES[@]} -eq 0 ]] && die "profile $PROFILE did not set FILES"

# ── Derive HF_FILE ────────────────────────────────────────────────────────────
# Pick the first entry in FILES that isn't an mmproj file.

HF_FILE=""
for f in "${FILES[@]}"; do
    if [[ "$f" != mmproj* ]]; then
        HF_FILE="$f"
        break
    fi
done

[[ -z "$HF_FILE" ]] && die "could not find a non-mmproj model file in FILES for profile $PROFILE"

# ── Check tools ───────────────────────────────────────────────────────────────

command -v curl &>/dev/null || die "curl is required (install with: sudo apt install curl)"
command -v tar  &>/dev/null || die "tar is required"

# ── Download + cache binary ───────────────────────────────────────────────────

ASSET="$(asset_name "$BACKEND")"
CACHE_DIR="$BIN_DIR/${LLAMA_RELEASE}/${BACKEND}"
SERVER_BIN="$CACHE_DIR/llama-server"
DOWNLOAD_URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_RELEASE}/${ASSET}"

if [[ ! -x "$SERVER_BIN" ]]; then
    info "binary not cached — downloading ${LLAMA_RELEASE} ${BACKEND} build"
    info "source: $DOWNLOAD_URL"
    echo ""

    mkdir -p "$CACHE_DIR"

    TMPFILE="$(mktemp --suffix=.tar.gz)"
    trap 'rm -f "$TMPFILE"' EXIT

    if ! curl -fL --progress-bar -o "$TMPFILE" "$DOWNLOAD_URL"; then
        rm -rf "$CACHE_DIR"
        die "download failed: $DOWNLOAD_URL
       Check that the release tag and ROCm version are correct (ROCM_VERSION=${ROCM_VERSION})."
    fi

    info "extracting to $CACHE_DIR"
    tar -xzf "$TMPFILE" -C "$CACHE_DIR" --strip-components=1

    [[ ! -x "$SERVER_BIN" ]] && die "extraction succeeded but llama-server not found at $SERVER_BIN"

    echo ""
    info "cached at $CACHE_DIR"
    echo ""
else
    info "using cached binary: $SERVER_BIN"
fi

# ── Resolve profile template ──────────────────────────────────────────────────

template_args=()
if [[ -n "$TEMPLATE" ]]; then
    template_file="$SCRIPT_DIR/templates/$TEMPLATE"
    [[ ! -f "$template_file" ]] && die "profile template not found: $template_file"
    template_args=(--jinja --chat-template-file "$template_file")
fi

# ── Build llama-server args from profile ──────────────────────────────────────

server_args=(
    -hf "$REPO"
    --hf-file "$HF_FILE"
    --host "$HOST"
    --port "$PORT"
    --metrics
)

if [[ ${#template_args[@]} -gt 0 ]]; then
    server_args+=("${template_args[@]}")
fi

if [[ ${#DEFAULTS[@]} -gt 0 ]]; then
    server_args+=("${DEFAULTS[@]}")
fi

if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    server_args+=("${EXTRA_ARGS[@]}")
fi

# ── Print summary ─────────────────────────────────────────────────────────────

info "profile:  $PROFILE"
info "model:    $REPO / $HF_FILE"
info "backend:  $(backend_label "$BACKEND")"
info "release:  $LLAMA_RELEASE"
info "binary:   $SERVER_BIN"
if [[ -n "$TEMPLATE" ]]; then
info "template: $template_file"
fi
info "endpoint: http://localhost:${PORT}"
echo ""

# ── Dry-run ───────────────────────────────────────────────────────────────────

if $DRY_RUN; then
    info "dry-run: command that would be executed:"
    echo ""

    echo "\"$SERVER_BIN\" \\"
    last_idx=$(( ${#server_args[@]} - 1 ))
    for (( j=0; j<${#server_args[@]}; j++ )); do
        arg="${server_args[$j]}"
        if [[ "$arg" == *' '* || "$arg" == *$'\n'* ]]; then
            printed="$(printf '%q' "$arg")"
        else
            printed="$arg"
        fi
        if (( j < last_idx )); then
            echo "    $printed \\"
        else
            echo "    $printed"
        fi
    done

    exit 0
fi

# ── Run ───────────────────────────────────────────────────────────────────────

exec "$SERVER_BIN" "${server_args[@]}"
