#!/usr/bin/env zsh
# start-ollama.sh — start Ollama on the Mac mini (M6, 24 GB) with gemma4:26b
# (default) or gemma4-code (--code), LAN-exposed, with the non-closable
# always-on-top status window. Shared logic lives in ollama-common.sh.
#
# Usage:
#   ./start-ollama.sh            start server (if needed), pull + warm gemma4:26b, LAN + status window
#   ./start-ollama.sh --local    same, but bound to 127.0.0.1 only (no LAN exposure)
#   ./start-ollama.sh --code     create "gemma4-code" and warm that instead
#   ./start-ollama.sh --stop     stop server + watchdog + status window
#
# Memory note: gemma4-code uses num_ctx=32768 (NOT 64K) — a ~16 GB model plus a
# 64K KV cache does not fit in 24 GB and causes offload/OOM. Override: NUM_CTX=16384 ./start-ollama.sh --code
#
# Security: the Ollama API has NO authentication. Only expose it on a trusted home
# network — never forward port 11434 on your router. See README.md §4.

set -euo pipefail
OLLAMA_DIR="${OLLAMA_DIR:-$HOME/ollama}"
source "$OLLAMA_DIR/ollama-common.sh"

MODEL="gemma4:26b"
BIND="0.0.0.0"
VARIANT_NAME=""
VARIANT_NUM_CTX=""
VARIANT_TEMP=""

case "${1:-}" in
  --stop)  stop_all; exit 0 ;;
  --local) BIND="127.0.0.1" ;;
  --code)
    VARIANT_NAME="gemma4-code"
    VARIANT_NUM_CTX="${NUM_CTX:-32768}"   # 32K context fits 24 GB; 64K OOMs (KV cache)
    VARIANT_TEMP="0.2"
    ;;
  "") ;;
  *) echo "usage: $0 [--local|--code|--stop]" >&2; exit 2 ;;
esac

run_start "$MODEL" "$BIND"
