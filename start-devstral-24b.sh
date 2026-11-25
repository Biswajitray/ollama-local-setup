#!/usr/bin/env zsh
# start-devstral-24b.sh — start Ollama serving devstral:24b on the Mac mini (M6, 24 GB).
# Agent harness model (14 GB, reads screenshots).
# Usage: ./start-devstral-24b.sh [--local|--stop]   (shared logic: ollama-common.sh; see README.md §2)
set -euo pipefail
OLLAMA_DIR="${OLLAMA_DIR:-$HOME/ollama}"
SCRIPT_NAME="$0"   # entry script path, before sourcing (zsh: $0 inside sourced file = that file)
source "$OLLAMA_DIR/ollama-common.sh"

MODEL="devstral:24b"
BIND="0.0.0.0"
VARIANT_NAME=""
VARIANT_NUM_CTX=""
VARIANT_TEMP=""

case "${1:-}" in
  --stop)  stop_all; exit 0 ;;
  --local) BIND="127.0.0.1" ;;
  "") ;;
  *) echo "usage: gen [--local|--stop]" >&2; exit 2 ;;
esac

run_start "$MODEL" "$BIND"
