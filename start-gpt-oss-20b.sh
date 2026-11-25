#!/usr/bin/env zsh
# start-gpt-oss-20b.sh — start Ollama serving gpt-oss:20b on the Mac mini (M6, 24 GB).
# Daily driver (14 GB, 128K ctx, tool-calling).
# Usage: ./start-gpt-oss-20b.sh [--local|--stop]   (shared logic: ollama-common.sh; see README.md §2)
set -euo pipefail
OLLAMA_DIR="${OLLAMA_DIR:-$HOME/ollama}"
SCRIPT_NAME="$0"   # entry script path, before sourcing (zsh: $0 inside sourced file = that file)
source "$OLLAMA_DIR/ollama-common.sh"

MODEL="gpt-oss:20b"
BIND="0.0.0.0"
VARIANT_NAME="gpt-oss-ctx"
VARIANT_NUM_CTX="${NUM_CTX:-32768}"   # 14 GB model: 32K ctx fits 24 GB
VARIANT_TEMP="0.2"

case "${1:-}" in
  --stop)  stop_all; exit 0 ;;
  --local) BIND="127.0.0.1" ;;
  "") ;;
  *) echo "usage: gen [--local|--stop]" >&2; exit 2 ;;
esac

run_start "$MODEL" "$BIND"
