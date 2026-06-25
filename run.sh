#!/usr/bin/env bash
#
# Run llama-server from a profile.
#
# Binary backends (--cpu, --rocm, --rocm-nightly, --vulkan) download a
# llama.cpp release tarball on first use and cache it under bin/.
#
# Container backends (--cuda, --cuda12) pull an upstream ghcr.io image
# via podman or docker — no binary download needed.
#
# Usage:
#   ./run.sh --cpu           --profile NAME [--dry-run] [-- extra llama-server flags]
#   ./run.sh --rocm          --profile NAME [--dry-run] [-- extra llama-server flags]
#   ./run.sh --rocm-nightly  --profile NAME [--dry-run] [-- extra llama-server flags]
#   ./run.sh --vulkan        --profile NAME [--dry-run] [-- extra llama-server flags]
#   ./run.sh --cuda          --profile NAME [--dry-run] [-- extra llama-server flags]
#   ./run.sh --cuda12        --profile NAME [--dry-run] [-- extra llama-server flags]
#
# Binary backends:
#   --cpu           Ubuntu x64 CPU-only build (upstream llama.cpp release)
#   --rocm          Ubuntu x64 ROCm build     (upstream llama.cpp release)
#   --rocm-nightly  Ubuntu x64 ROCm build     (lemonade-sdk/llamacpp-rocm nightly)
#   --vulkan        Ubuntu x64 Vulkan build   (upstream llama.cpp release)
#
# Container backends:
#   --cuda          NVIDIA CUDA 13 (ghcr.io/ggml-org/llama.cpp:server-cuda13)
#   --cuda12        NVIDIA CUDA 12 (ghcr.io/ggml-org/llama.cpp:server-cuda)
#
# Environment:
#   LLAMA_RELEASE       llama.cpp release tag (binary backends; default: latest from GitHub)
#                       for --rocm-nightly this is the lemonade-sdk build tag
#   ROCM_VERSION        ROCm version in the asset name (default: 7.2)
#   ROCM_NIGHTLY_REPO   GitHub repo for nightly ROCm builds
#                       (default: lemonade-sdk/llamacpp-rocm)
#   ROCM_GFX            GPU target for nightly builds (default: gfx120X)
#   ARCH                CPU architecture override (default: x64)
#   HF_HUB              HuggingFace cache directory (default: ~/.cache/huggingface/hub)
#   HOST                Bind address (default: 0.0.0.0)
#   PORT                Bind port    (default: 8080)
#   IMAGE               Override container image (container backends only)
#   ENGINE              Container engine: podman or docker (auto-detected)
#
# Binary cache layout:
#   bin/<backend>/<tag>/           — cpu, rocm, vulkan
#   bin/rocm-nightly/<tag>-<gfx>/  — rocm-nightly
#   Delete the relevant subdirectory to force a fresh download.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

ROCM_VERSION="${ROCM_VERSION:-7.2}"
ROCM_NIGHTLY_REPO="${ROCM_NIGHTLY_REPO:-lemonade-sdk/llamacpp-rocm}"
ROCM_GFX="${ROCM_GFX:-gfx120X}"
ARCH="${ARCH:-x64}"
HF_HUB="${HF_HUB:-$HOME/.cache/huggingface/hub}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8080}"
ENGINE="${ENGINE:-}"

BACKEND=""
PROFILE=""
DRY_RUN=false
EXTRA_ARGS=()

# Track whether LLAMA_RELEASE was explicitly pinned so the rocm-nightly
# backend can auto-resolve from its own repo when it wasn't.
LLAMA_RELEASE_EXPLICIT=false
if [[ -n "${LLAMA_RELEASE:-}" ]]; then
    LLAMA_RELEASE_EXPLICIT=true
fi

# ── Path resolution ───────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILES_DIR="$SCRIPT_DIR/profiles"
BIN_DIR="$SCRIPT_DIR/bin"
DEFAULT_TEMPLATE_DIR="$SCRIPT_DIR/templates"
TEMPLATE_DIR=""

# ── Helpers ───────────────────────────────────────────────────────────────────

die()  { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# Resolve the latest release tag from a GitHub repo.
# $1 = repo in "owner/name" form. Prints the tag or empty string on failure.
_resolve_latest_release() {
    local repo="$1"
    curl -fsSL --max-time 5 \
        "https://api.github.com/repos/${repo}/releases/latest" \
        2>/dev/null | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/'
}

# Is this a container backend?
_is_container() {
    [[ "$1" == "cuda" || "$1" == "cuda12" ]]
}

# ── Argument parsing ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu)          BACKEND="cpu";          shift ;;
        --rocm)         BACKEND="rocm";         shift ;;
        --rocm-nightly) BACKEND="rocm-nightly"; shift ;;
        --vulkan)       BACKEND="vulkan";       shift ;;
        --cuda)         BACKEND="cuda";         shift ;;
        --cuda12)       BACKEND="cuda12";       shift ;;
        --profile)
            [[ -z "${2:-}" ]] && die "--profile requires a name"
            PROFILE="$2"
            shift 2
            ;;
        --release)
            [[ -z "${2:-}" ]] && die "--release requires a tag (e.g. --release b9785)"
            LLAMA_RELEASE="$2"
            LLAMA_RELEASE_EXPLICIT=true
            shift 2
            ;;
        --template-dir)
            [[ -z "${2:-}" ]] && die "--template-dir requires a path"
            TEMPLATE_DIR="$2"
            shift 2
            ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h)
            echo "Usage: ./run.sh --BACKEND --profile NAME [--dry-run] [-- LLAMA_ARGS...]"
            echo ""
            echo "Binary backends (download llama.cpp release binary):"
            echo "  --cpu           Ubuntu x64 CPU-only"
            echo "  --rocm          Ubuntu x64 ROCm (upstream release)"
            echo "  --rocm-nightly  Ubuntu x64 ROCm (lemonade-sdk nightly)"
            echo "  --vulkan        Ubuntu x64 Vulkan"
            echo ""
            echo "Container backends (pull ghcr.io image via podman/docker):"
            echo "  --cuda          NVIDIA CUDA 13"
            echo "  --cuda12        NVIDIA CUDA 12"
            echo ""
            echo "Options:"
            echo "  --profile NAME      Source profiles/<NAME>.sh (required)"
            echo "  --release TAG       Pin the release tag (binary backends)"
            echo "  --template-dir DIR  Mount DIR at /templates (container backends;"
            echo "                      defaults to templates/ if present)"
            echo "  --dry-run           Print the command without executing it"
            echo "  -- ARGS             Forward remaining args to llama-server"
            echo ""
            echo "Environment:"
            echo "  LLAMA_RELEASE       Release tag (default: latest from GitHub)"
            echo "  ROCM_VERSION        ROCm version in asset name (default: ${ROCM_VERSION})"
            echo "  ROCM_NIGHTLY_REPO   Nightly ROCm repo (default: ${ROCM_NIGHTLY_REPO})"
            echo "  ROCM_GFX            Nightly GPU target (default: ${ROCM_GFX})"
            echo "  ARCH                CPU arch (default: ${ARCH})"
            echo "  HF_HUB              HuggingFace cache (default: ~/.cache/huggingface/hub)"
            echo "  HOST                Bind address (default: ${HOST})"
            echo "  PORT                Bind port (default: ${PORT})"
            echo "  IMAGE               Override container image (container backends)"
            echo "  ENGINE              Container engine: podman or docker (auto-detected)"
            exit 0
            ;;
        --)
            shift
            EXTRA_ARGS=("$@")
            break
            ;;
        -*)  die "unknown option: $1 (try --help)" ;;
        *)   die "unexpected argument: $1 (try --help)" ;;
    esac
done

# ── Validate ──────────────────────────────────────────────────────────────────

[[ -z "$BACKEND" ]] && die "a backend is required (try --help)"

# ── Profile selection ─────────────────────────────────────────────────────────
# If --profile was not given, list available profiles and prompt for one.

if [[ -z "$PROFILE" ]]; then
    mapfile -t profile_files < <(ls "$PROFILES_DIR"/*.sh 2>/dev/null | sort)
    [[ ${#profile_files[@]} -eq 0 ]] && die "no profiles found in $PROFILES_DIR"

    echo "Available profiles:"
    echo ""
    PS3=$'\nSelect a profile: '
    select profile_file in "${profile_files[@]##*/}"; do
        [[ -n "$profile_file" ]] && break
        echo "Invalid selection, try again."
    done
    PROFILE="${profile_file%.sh}"
    profile_file="$PROFILES_DIR/$profile_file"
    echo ""
else
    profile_file="$PROFILES_DIR/${PROFILE}.sh"
    [[ ! -f "$profile_file" ]] && die "profile not found: $profile_file"
fi

# ── Source profile ────────────────────────────────────────────────────────────

REPO=""
FILES=()
DEFAULTS=()
TEMPLATE=""

# shellcheck source=/dev/null
source "$profile_file"

[[ -z "$REPO" ]]         && die "profile $PROFILE did not set REPO"
[[ ${#FILES[@]} -eq 0 ]] && die "profile $PROFILE did not set FILES"

# Pick the first non-mmproj entry as the primary model file.
HF_FILE=""
for f in "${FILES[@]}"; do
    if [[ "$f" != mmproj* && "$f" != mtp-* ]]; then
        HF_FILE="$f"
        break
    fi
done
[[ -z "$HF_FILE" ]] && die "could not find a primary model file in FILES for profile $PROFILE"

# ── Resolve profile template ──────────────────────────────────────────────────

template_args=()
if [[ -n "$TEMPLATE" ]]; then
    if _is_container "$BACKEND"; then
        # Container: verify the file exists on the host and inject container path.
        [[ -z "$TEMPLATE_DIR" && -d "$DEFAULT_TEMPLATE_DIR" ]] && TEMPLATE_DIR="$DEFAULT_TEMPLATE_DIR"
        [[ -z "$TEMPLATE_DIR" ]] && die "profile sets TEMPLATE=$TEMPLATE but no templates directory found"
        [[ ! -f "$TEMPLATE_DIR/$TEMPLATE" ]] && die "template not found: $TEMPLATE_DIR/$TEMPLATE"
        template_args=(--jinja --chat-template-file "/templates/$TEMPLATE")
    else
        # Binary: resolve against local templates dir.
        template_file="$SCRIPT_DIR/templates/$TEMPLATE"
        [[ ! -f "$template_file" ]] && die "template not found: $template_file"
        template_args=(--jinja --chat-template-file "$template_file")
    fi
fi

# ── Build llama-server args ───────────────────────────────────────────────────

server_args=(
    -hf "$REPO"
    --hf-file "$HF_FILE"
    --host "$HOST"
    --port "$PORT"
    --metrics
)
[[ ${#template_args[@]} -gt 0 ]] && server_args+=("${template_args[@]}")
[[ ${#DEFAULTS[@]}      -gt 0 ]] && server_args+=("${DEFAULTS[@]}")
[[ ${#EXTRA_ARGS[@]}    -gt 0 ]] && server_args+=("${EXTRA_ARGS[@]}")

# ── Container backend ─────────────────────────────────────────────────────────

if _is_container "$BACKEND"; then

    # Detect container engine.
    if [[ -z "$ENGINE" ]]; then
        if command -v podman &>/dev/null; then
            ENGINE="podman"
        elif command -v docker &>/dev/null; then
            ENGINE="docker"
        else
            die "neither podman nor docker found"
        fi
    fi

    # Select image.
    default_image() {
        case "$1" in
            cuda)   echo "ghcr.io/ggml-org/llama.cpp:server-cuda13" ;;
            cuda12) echo "ghcr.io/ggml-org/llama.cpp:server-cuda"   ;;
        esac
    }
    IMAGE="${IMAGE:-$(default_image "$BACKEND")}"

    # Device + security flags.
    mapfile -t dev_flags < <(
        case "$BACKEND" in
            cuda|cuda12)
                printf '%s\n' "--device" "nvidia.com/gpu=all" "--security-opt" "label=disable"
                ;;
        esac
    )

    # Template volume.
    if [[ -z "$TEMPLATE_DIR" && -d "$DEFAULT_TEMPLATE_DIR" ]]; then
        TEMPLATE_DIR="$DEFAULT_TEMPLATE_DIR"
    fi
    if [[ -n "$TEMPLATE_DIR" ]]; then
        [[ ! -d "$TEMPLATE_DIR" ]] && die "template directory not found: $TEMPLATE_DIR"
        TEMPLATE_DIR="$(cd "$TEMPLATE_DIR" && pwd)"
    fi

    [[ ! -d "$HF_HUB" ]] && die "HuggingFace cache not found at $HF_HUB (set HF_HUB to override)"

    # Summary.
    info "profile:  $PROFILE"
    info "model:    $REPO / $HF_FILE"
    info "backend:  $( [[ "$BACKEND" == cuda ]] && echo "NVIDIA CUDA 13" || echo "NVIDIA CUDA 12" ) (container)"
    info "image:    $IMAGE"
    info "cache:    $HF_HUB"
    [[ -n "$TEMPLATE_DIR" ]] && info "templates: $TEMPLATE_DIR → /templates"
    [[ -n "$TEMPLATE"     ]] && info "template:  $TEMPLATE"
    info "endpoint: http://localhost:${PORT}"
    echo ""

    if $DRY_RUN; then
        info "dry-run: command that would be executed:"
        echo ""
        echo "$ENGINE run --rm -it \\"
        echo "    --network host \\"
        i=0
        while (( i < ${#dev_flags[@]} )); do
            flag="${dev_flags[$i]}"
            if [[ "$flag" == --device || "$flag" == --security-opt ]]; then
                echo "    $flag ${dev_flags[$((i+1))]} \\"
                i=$(( i + 2 ))
            else
                echo "    $flag \\"
                i=$(( i + 1 ))
            fi
        done
        echo "    -v \"$HF_HUB:/root/.cache/huggingface/hub\" \\"
        [[ -n "$TEMPLATE_DIR" ]] && echo "    -v \"$TEMPLATE_DIR:/templates:ro\" \\"
        echo "    \"$IMAGE\" \\"
        last=$(( ${#server_args[@]} - 1 ))
        for (( j=0; j<${#server_args[@]}; j++ )); do
            arg="${server_args[$j]}"
            [[ "$arg" == *' '* || "$arg" == *$'\n'* ]] && arg="$(printf '%q' "$arg")"
            (( j < last )) && echo "    $arg \\" || echo "    $arg"
        done
        exit 0
    fi

    template_vol=()
    [[ -n "$TEMPLATE_DIR" ]] && template_vol=(-v "$TEMPLATE_DIR:/templates:ro")

    exec "$ENGINE" run --rm -it \
        --network host \
        "${dev_flags[@]}" \
        -v "$HF_HUB:/root/.cache/huggingface/hub" \
        "${template_vol[@]}" \
        "$IMAGE" \
        "${server_args[@]}"
fi

# ── Binary backend ────────────────────────────────────────────────────────────

# Resolve release tag.
if [[ -z "${LLAMA_RELEASE:-}" ]]; then
    LLAMA_RELEASE="$(_resolve_latest_release "ggml-org/llama.cpp")"
fi
if [[ "$BACKEND" == "rocm-nightly" && "$LLAMA_RELEASE_EXPLICIT" == false ]]; then
    LLAMA_RELEASE="$(_resolve_latest_release "$ROCM_NIGHTLY_REPO")"
fi
[[ -z "$LLAMA_RELEASE" ]] && die "could not resolve release tag from GitHub API — check your network or pin a tag with --release"

# Asset filename on GitHub releases.
asset_name() {
    case "$1" in
        cpu)          echo "llama-${LLAMA_RELEASE}-bin-ubuntu-${ARCH}.tar.gz" ;;
        vulkan)       echo "llama-${LLAMA_RELEASE}-bin-ubuntu-vulkan-${ARCH}.tar.gz" ;;
        rocm)         echo "llama-${LLAMA_RELEASE}-bin-ubuntu-rocm-${ROCM_VERSION}-${ARCH}.tar.gz" ;;
        rocm-nightly) echo "llama-${LLAMA_RELEASE}-ubuntu-rocm-${ROCM_GFX}-${ARCH}.zip" ;;
    esac
}

backend_label() {
    case "$1" in
        cpu)          echo "CPU (Ubuntu x64)" ;;
        rocm)         echo "AMD ROCm ${ROCM_VERSION}" ;;
        rocm-nightly) echo "AMD ROCm nightly (${ROCM_GFX})" ;;
        vulkan)       echo "Vulkan" ;;
    esac
}

backend_repo() {
    [[ "$1" == "rocm-nightly" ]] && echo "${ROCM_NIGHTLY_REPO}" || echo "ggml-org/llama.cpp"
}

ASSET="$(asset_name "$BACKEND")"
GH_REPO="$(backend_repo "$BACKEND")"

# Cache layout: bin/<backend>/<tag>/
# rocm-nightly appends the GPU target to the tag to distinguish per-GPU builds.
if [[ "$BACKEND" == "rocm-nightly" ]]; then
    CACHE_DIR="$BIN_DIR/rocm-nightly/${LLAMA_RELEASE}-${ROCM_GFX}"
else
    CACHE_DIR="$BIN_DIR/${BACKEND}/${LLAMA_RELEASE}"
fi

SERVER_BIN="$CACHE_DIR/llama-server"
DOWNLOAD_URL="https://github.com/${GH_REPO}/releases/download/${LLAMA_RELEASE}/${ASSET}"

# Check tools.
command -v curl &>/dev/null || die "curl is required"
command -v tar  &>/dev/null || die "tar is required"
[[ "$BACKEND" == "rocm-nightly" ]] && { command -v unzip &>/dev/null || die "unzip is required for --rocm-nightly"; }

# Download if not cached.
if [[ ! -x "$SERVER_BIN" ]]; then
    info "binary not cached — downloading ${LLAMA_RELEASE} ${BACKEND} build"
    info "source: $DOWNLOAD_URL"
    echo ""

    mkdir -p "$CACHE_DIR"

    case "$BACKEND" in
        rocm-nightly) TMPFILE="$(mktemp --suffix=.zip)" ;;
        *)            TMPFILE="$(mktemp --suffix=.tar.gz)" ;;
    esac
    trap 'rm -f "$TMPFILE"' EXIT

    if ! curl -fL --progress-bar -o "$TMPFILE" "$DOWNLOAD_URL"; then
        rm -rf "$CACHE_DIR"
        die "download failed: $DOWNLOAD_URL"
    fi

    info "extracting to $CACHE_DIR"
    case "$BACKEND" in
        rocm-nightly)
            unzip -q -o "$TMPFILE" -d "$CACHE_DIR"
            for bin in "$CACHE_DIR"/llama-*; do
                [[ -f "$bin" ]] && chmod +x "$bin"
            done
            ;;
        *)
            tar -xzf "$TMPFILE" -C "$CACHE_DIR" --strip-components=1
            ;;
    esac

    [[ ! -x "$SERVER_BIN" ]] && die "extraction succeeded but llama-server not found at $SERVER_BIN"
    echo ""
    info "cached at $CACHE_DIR"
    echo ""
else
    info "using cached binary: $SERVER_BIN"
fi

# Summary.
info "profile:  $PROFILE"
info "model:    $REPO / $HF_FILE"
info "backend:  $(backend_label "$BACKEND")"
info "release:  $LLAMA_RELEASE"
info "source:   github.com/${GH_REPO}"
info "binary:   $SERVER_BIN"
[[ -n "$TEMPLATE" ]] && info "template: $SCRIPT_DIR/templates/$TEMPLATE"
info "endpoint: http://localhost:${PORT}"
echo ""

if $DRY_RUN; then
    info "dry-run: command that would be executed:"
    echo ""
    echo "\"$SERVER_BIN\" \\"
    last=$(( ${#server_args[@]} - 1 ))
    for (( j=0; j<${#server_args[@]}; j++ )); do
        arg="${server_args[$j]}"
        [[ "$arg" == *' '* || "$arg" == *$'\n'* ]] && arg="$(printf '%q' "$arg")"
        (( j < last )) && echo "    $arg \\" || echo "    $arg"
    done
    exit 0
fi

exec "$SERVER_BIN" "${server_args[@]}"
