#!/usr/bin/env zsh
# start-gemma4-code.sh — start Ollama serving gemma4:26b on the Mac mini (M6, 24 GB).
# Coding variant of gemma4:26b with num_ctx 32768 (memory-safe on 24 GB) and temperature 0.2.
# Usage: ./start-gemma4-code.sh [--local|--stop]   (shared logic: ollama-common.sh; see README.md §2)
set -euo pipefail
OLLAMA_DIR="${OLLAMA_DIR:-$HOME/ollama}"
source "$OLLAMA_DIR/ollama-common.sh"

MODEL="gemma4:26b"
BIND="0.0.0.0"
VARIANT_NAME=""
VARIANT_NUM_CTX=""
VARIANT_TEMP=""
VARIANT_NAME="gemma4-code"
VARIANT_NUM_CTX="${NUM_CTX:-32768}"   # 32K fits 24 GB; 64K OOMs (KV cache)
VARIANT_TEMP="0.2"
case "${1:-}" in
  --stop)  stop_all; exit 0 ;;
  --local) BIND="127.0.0.1" ;;
  "") ;;
  *) echo "usage: gen [--local|--stop]" >&2; exit 2 ;;
esac

run_start "$MODEL" "$BIND"
