#!/usr/bin/env bash
#
# Run llama-server directly from a pinned llama.cpp GitHub release binary,
# using settings derived from a thinkpod2 profile.
#
# Downloads the release tarball on first use and caches it under bin/ in the
# project root.  Subsequent runs use the cached binary without re-downloading.
#
# Usage:
#   ./local.sh --cpu           --profile NAME
#   ./local.sh --rocm          --profile NAME [--dry-run]
#   ./local.sh --rocm-nightly  --profile NAME [--dry-run]
#   ./local.sh --vulkan        --profile NAME [-- extra llama-server flags]
#
# Backends:
#   --cpu           Ubuntu x64 CPU-only build
#   --rocm          Ubuntu x64 ROCm build (llama.cpp upstream release)
#   --rocm-nightly  Ubuntu x64 ROCm build (lemonade-sdk/llamacpp-rocm nightly)
#   --vulkan        Ubuntu x64 Vulkan build
#
# Note: There is no Ubuntu CUDA release binary. Use scripts/serve-profile.sh
#       (container-based) for NVIDIA GPU workloads.
#
# Flags after -- are forwarded to llama-server and override profile defaults.
#
# Environment:
#   LLAMA_RELEASE       llama.cpp release tag to use  (default: latest from GitHub)
#                       for --rocm-nightly this is the lemonade-sdk build tag
#                       (e.g. b1293); auto-resolved from ROCM_NIGHTLY_REPO
#   ROCM_VERSION        ROCm version in the asset name (default: 7.2)
#   ROCM_NIGHTLY_REPO   GitHub repo for nightly ROCm builds
#                       (default: lemonade-sdk/llamacpp-rocm)
#   ROCM_GFX            GPU target in the nightly asset name (default: gfx120X)
#   ARCH                CPU architecture override      (default: x64)
#   HF_HUB              HuggingFace cache directory   (default: ~/.cache/huggingface/hub)
#   HOST                Bind address                   (default: 0.0.0.0)
#   PORT                Bind port                      (default: 8080)
#
# Binary cache:
#   Upstream backends cache to bin/<tag>/<backend>/; the nightly backend
#   caches to bin/<repo>/<tag>/rocm-nightly-<gfx>/ (namespaced by repo so
#   its independent b#### tags never collide with upstream).  To force a
#   re-download, delete the relevant subdirectory under bin/.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

# Resolve the latest release tag from a GitHub repo.
# $1 = repo in "owner/name" form, $2 = fallback tag if the API call fails.
_resolve_latest_release() {
    local repo="$1"
    local fallback="$2"
    local tag
    tag="$(curl -fsSL --max-time 5 \
        "https://api.github.com/repos/${repo}/releases/latest" \
        2>/dev/null | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
    if [[ -n "$tag" ]]; then
        echo "$tag"
    else
        echo "$fallback"
    fi
}

# Track whether LLAMA_RELEASE was pinned via env or --release.  The
# rocm-nightly backend pulls its builds from a different repo, so when the
# tag was NOT explicitly pinned we re-resolve it from ROCM_NIGHTLY_REPO
# instead of the upstream llama.cpp releases.
LLAMA_RELEASE_EXPLICIT=false
if [[ -n "${LLAMA_RELEASE:-}" ]]; then
    LLAMA_RELEASE_EXPLICIT=true
fi
if [[ -z "${LLAMA_RELEASE:-}" ]]; then
    LLAMA_RELEASE="$(_resolve_latest_release "ggml-org/llama.cpp" "b9536")"
fi
ROCM_VERSION="${ROCM_VERSION:-7.2}"
ROCM_NIGHTLY_REPO="${ROCM_NIGHTLY_REPO:-lemonade-sdk/llamacpp-rocm}"
ROCM_GFX="${ROCM_GFX:-gfx120X}"
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
        cpu)          echo "llama-${LLAMA_RELEASE}-bin-ubuntu-${ARCH}.tar.gz" ;;
        vulkan)       echo "llama-${LLAMA_RELEASE}-bin-ubuntu-vulkan-${ARCH}.tar.gz" ;;
        rocm)         echo "llama-${LLAMA_RELEASE}-bin-ubuntu-rocm-${ROCM_VERSION}-${ARCH}.tar.gz" ;;
        rocm-nightly) echo "llama-${LLAMA_RELEASE}-ubuntu-rocm-${ROCM_GFX}-${ARCH}.zip" ;;
    esac
}

# Human-readable backend description
backend_label() {
    case "$1" in
        cpu)          echo "CPU (Ubuntu x64)" ;;
        rocm)         echo "AMD ROCm ${ROCM_VERSION}" ;;
        rocm-nightly) echo "AMD ROCm nightly (${ROCM_GFX})" ;;
        vulkan)       echo "Vulkan" ;;
    esac
}

# GitHub repo (owner/name) hosting the releases for the given backend.
backend_repo() {
    case "$1" in
        rocm-nightly) echo "${ROCM_NIGHTLY_REPO}" ;;
        *)            echo "ggml-org/llama.cpp" ;;
    esac
}

# ── Argument parsing ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu)          BACKEND="cpu";          shift ;;
        --rocm)         BACKEND="rocm";         shift ;;
        --rocm-nightly) BACKEND="rocm-nightly"; shift ;;
        --vulkan)       BACKEND="vulkan";       shift ;;
        --profile)
            [[ -z "${2:-}" ]] && die "--profile requires a name (e.g. --profile qwen3.5-4b)"
            PROFILE="$2"
            shift 2
            ;;
        --release)
            [[ -z "${2:-}" ]] && die "--release requires a tag (e.g. --release b9190)"
            LLAMA_RELEASE="$2"
            LLAMA_RELEASE_EXPLICIT=true
            shift 2
            ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h)
            echo "Usage: ./local.sh --BACKEND --profile NAME [--dry-run] [-- LLAMA_ARGS...]"
            echo ""
            echo "Run llama-server from a pinned llama.cpp release binary (no container needed)."
            echo ""
            echo "Backends:  --cpu  --rocm  --rocm-nightly  --vulkan"
            echo ""
            echo "Options:"
            echo "  --profile NAME    Source profiles/<NAME>.sh for model + defaults (required)"
            echo "  --release TAG     Release tag. llama.cpp tag for --cpu/--rocm/--vulkan,"
            echo "                    lemonade-sdk build tag (e.g. b1293) for --rocm-nightly"
            echo "                    (default: ${LLAMA_RELEASE})"
            echo "  --dry-run         Print the command without executing it"
            echo "  -- ARGS           Forward remaining args to llama-server (override defaults)"
            echo ""
            echo "Environment:"
            echo "  LLAMA_RELEASE     Release tag          (default: latest from GitHub, resolved to ${LLAMA_RELEASE})"
            echo "  ROCM_VERSION      ROCm version in asset name (default: ${ROCM_VERSION})"
            echo "  ROCM_NIGHTLY_REPO Nightly ROCm repo    (default: ${ROCM_NIGHTLY_REPO})"
            echo "  ROCM_GFX          Nightly GPU target   (default: ${ROCM_GFX})"
            echo "  ARCH              CPU arch             (default: ${ARCH})"
            echo "  HF_HUB            HuggingFace cache    (default: ~/.cache/huggingface/hub)"
            echo "  HOST              Bind address          (default: ${HOST})"
            echo "  PORT              Bind port             (default: ${PORT})"
            echo ""
            echo "Binary cache:"
            echo "  Upstream:     bin/<tag>/<backend>/"
            echo "  rocm-nightly: bin/<repo>/<tag>/rocm-nightly-<gfx>/"
            echo "  Delete the relevant subdirectory to force a fresh download."
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

[[ -z "$BACKEND" ]]  && die "a backend is required: --cpu, --rocm, --rocm-nightly, or --vulkan"
[[ -z "$PROFILE" ]]  && die "--profile NAME is required"

# ── Resolve release tag for the chosen backend ────────────────────────────────
# When the tag was not pinned via --release / LLAMA_RELEASE, the rocm-nightly
# backend auto-resolves from its own repo (ROCM_NIGHTLY_REPO) instead of the
# upstream llama.cpp releases, since the two publish independent tag streams.
if [[ "$BACKEND" == "rocm-nightly" && "$LLAMA_RELEASE_EXPLICIT" == false ]]; then
    LLAMA_RELEASE="$(_resolve_latest_release "$ROCM_NIGHTLY_REPO" "b1293")"
fi

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
if [[ "$BACKEND" == "rocm-nightly" ]]; then
    command -v unzip &>/dev/null || die "unzip is required for --rocm-nightly (install with: sudo apt install unzip)"
fi

# ── Download + cache binary ───────────────────────────────────────────────────

ASSET="$(asset_name "$BACKEND")"
GH_REPO="$(backend_repo "$BACKEND")"
CACHE_DIR="$BIN_DIR/${LLAMA_RELEASE}/${BACKEND}"
# The nightly backend pulls from a separate repo (ROCM_NIGHTLY_REPO) whose
# b#### tags are independent of upstream llama.cpp, so namespace its cache
# under a repo-derived folder to keep the two tag streams from colliding.
# It also publishes one archive per GPU target, so include ROCM_GFX.
if [[ "$BACKEND" == "rocm-nightly" ]]; then
    REPO_DIR="${ROCM_NIGHTLY_REPO##*/}"   # last path component, e.g. llamacpp-rocm
    CACHE_DIR="$BIN_DIR/${REPO_DIR}/${LLAMA_RELEASE}/${BACKEND}-${ROCM_GFX}"
fi
SERVER_BIN="$CACHE_DIR/llama-server"
DOWNLOAD_URL="https://github.com/${GH_REPO}/releases/download/${LLAMA_RELEASE}/${ASSET}"

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
        if [[ "$BACKEND" == "rocm-nightly" ]]; then
            die "download failed: $DOWNLOAD_URL
       Check that the build tag and GPU target are correct (LLAMA_RELEASE=${LLAMA_RELEASE}, ROCM_GFX=${ROCM_GFX})."
        else
            die "download failed: $DOWNLOAD_URL
       Check that the release tag and ROCm version are correct (ROCM_VERSION=${ROCM_VERSION})."
        fi
    fi

    info "extracting to $CACHE_DIR"
    case "$BACKEND" in
        rocm-nightly)
            # lemonade-sdk zips store files at the archive root (no top-level
            # directory), so extract straight into the cache dir.
            unzip -q -o "$TMPFILE" -d "$CACHE_DIR"
            # The zip does not set the executable bit on the llama-* binaries,
            # so restore it (otherwise the -x check below fails).
            for bin in "$CACHE_DIR"/llama-*; do
                [[ -f "$bin" ]] || continue
                chmod +x "$bin"
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
info "source:   github.com/${GH_REPO}"
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
