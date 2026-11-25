#!/usr/bin/env zsh
# start-qwen3-coder-30b.sh — start Ollama serving qwen3-coder:30b on the Mac mini (M6, 24 GB).
# Coding specialist (19 GB MoE) — creates qwen3-coder-ctx with a 16K context cap so the KV cache fits in 24 GB.
# Usage: ./start-qwen3-coder-30b.sh [--local|--stop]   (shared logic: ollama-common.sh; see README.md §2)
set -euo pipefail
OLLAMA_DIR="${OLLAMA_DIR:-$HOME/ollama}"
source "$OLLAMA_DIR/ollama-common.sh"

MODEL="qwen3-coder:30b"
BIND="0.0.0.0"
VARIANT_NAME=""
VARIANT_NUM_CTX=""
VARIANT_TEMP=""
VARIANT_NAME="qwen3-coder-ctx"
VARIANT_NUM_CTX="${NUM_CTX:-16384}"   # 19 GB model: keep num_ctx low on 24 GB
VARIANT_TEMP="0.2"
case "${1:-}" in
  --stop)  stop_all; exit 0 ;;
  --local) BIND="127.0.0.1" ;;
  "") ;;
  *) echo "usage: gen [--local|--stop]" >&2; exit 2 ;;
esac

run_start "$MODEL" "$BIND"
