#!/usr/bin/env zsh
# ollama-watchdog.sh — keeps the Ollama status window alive.
# Started by start-*.sh via ollama-common.sh (start_watchdog). Env: MODEL (required),
# BIND, PORT, OLLAMA_DIR. Runs as its OWN process so `--stop` can pkill it reliably.
#
#   - re-opens the window within 5 s if it is killed
#   - rebuilds the window within 5 s if the Mac's LAN IP changed (DHCP renewal)
#   - closes the window and exits when the server is down or the model is unloaded
set -u  # deliberately no -e: the loop must survive transient curl/ollama failures

OLLAMA_DIR="${OLLAMA_DIR:-$HOME/ollama}"
PORT="${PORT:-11434}"
SCRIPT_NAME="$0"   # entry script path, before sourcing (zsh: $0 inside sourced file = that file)
source "$OLLAMA_DIR/ollama-common.sh"
: "${MODEL:?MODEL env var required}"
BIND="${BIND:-0.0.0.0}"

echo $$ >"$WATCHPID"
LAST_URL="__init__"
while true; do
  curl -sf "$API/api/version" >/dev/null 2>&1 || break   # server down
  # fix: match the FULL model name, not the family prefix
  OLLAMA_HOST="127.0.0.1:${PORT}" ollama ps 2>/dev/null | awk '{print $1}' | grep -qx "$MODEL" || break
  IP=$(current_lan_ip)
  URL=""
  [[ "$BIND" == "0.0.0.0" && -n "$IP" ]] && URL="http://${IP}:${PORT}"
  if [[ "$URL" != "$LAST_URL" ]]; then
    LAST_URL="$URL"
    write_status_window "$MODEL" "$URL" "$IP"
    pkill -f "$WINJS" 2>/dev/null || true
    sleep 1
    nohup osascript -l JavaScript "$WINJS" >>"$LOG" 2>&1 &
  elif ! pgrep -f "$WINJS" >/dev/null 2>&1; then
    nohup osascript -l JavaScript "$WINJS" >>"$LOG" 2>&1 &
  fi
  sleep 5
done
pkill -f "$WINJS" 2>/dev/null || true
rm -f "$WATCHPID"
