#!/bin/sh
# Run Bonsai model with llama.cpp
# Usage: ./scripts/run_llama.sh -p "Your prompt" -n 100
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/common.sh"
assert_valid_model
DEMO_DIR="$(resolve_demo_dir)"
cd "$DEMO_DIR"
assert_gguf_downloaded

# ── Find model ──
MODEL=""
for _m in $GGUF_MODEL_DIR/*.gguf; do
    [ -f "$_m" ] && MODEL="$_m" && break
done

# ── Find binary (search all known locations) ──
BIN=""
for _d in bin/mac bin/cuda llama.cpp/build/bin llama.cpp/build-mac/bin llama.cpp/build-cuda/bin; do
    [ -f "$DEMO_DIR/$_d/llama-cli" ] && BIN="$DEMO_DIR/$_d/llama-cli" && break
done
if [ -z "$BIN" ]; then
    err "llama-cli not found. Run ./setup.sh or ./scripts/download_binaries.sh first."
    echo "  Intel Mac: there is no arm64 pre-build — use ./scripts/build_mac.sh"
    exit 1
fi

NGL=$(bonsai_llama_ngl)

# ── Library path for bundled shared libs (needed on Linux CUDA, harmless elsewhere) ──
BIN_DIR="$(cd "$(dirname "$BIN")" && pwd)"
export LD_LIBRARY_PATH="$BIN_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# If you pass -c N, we do not inject -c 0 / fallback (those messages were misleading).
USER_CTX=""
_prev=""
for _a in "$@"; do
    if [ "$_prev" = "-c" ]; then
        USER_CTX="$_a"
        break
    fi
    _prev="$_a"
done

info "Model:  $MODEL"
info "Binary: $BIN"
if [ -n "$USER_CTX" ]; then
    info "Context: -c $USER_CTX (from your arguments; no auto-fit / fallback)"
else
    info "Context: -c 0 (auto-fit RAM); pass -c N to set explicitly"
fi

if [ -n "$USER_CTX" ]; then
    "$BIN" -m "$MODEL" -ngl "$NGL" --log-disable \
        --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
        --reasoning-budget 0 --reasoning-format none \
        --chat-template-kwargs '{"enable_thinking": false}' \
        "$@"
else
    "$BIN" -m "$MODEL" -ngl "$NGL" -c "$CTX_SIZE_DEFAULT" --log-disable \
        --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
        --reasoning-budget 0 --reasoning-format none \
        --chat-template-kwargs '{"enable_thinking": false}' \
        "$@" \
    || {
        CTX_SIZE=$(get_context_size_fallback)
        warn "First run failed (often: this build does not support -c 0 auto-fit). Retrying with -c $CTX_SIZE"
        "$BIN" -m "$MODEL" -ngl "$NGL" -c "$CTX_SIZE" --log-disable \
            --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 \
            --reasoning-budget 0 --reasoning-format none \
            --chat-template-kwargs '{"enable_thinking": false}' \
            "$@"
    }
fi
