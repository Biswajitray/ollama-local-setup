#!/usr/bin/env zsh
# start-ollama.sh — Start Ollama on the Mac mini (M6, 24 GB), expose it to the LAN,
# warm gemma4:26b, and show a NON-CLOSABLE, always-on-top desktop status window
# (model name + URLs) that stays up as long as Ollama is running the model.
#
# Location: ~/ollama/start-ollama.sh  (logs: ~/ollama/logs, state: ~/ollama/*.pid|js,
# Modelfiles: ~/ollama/modelfiles)
#
# Usage:
#   ./start-ollama.sh            start server (if needed), pull + warm gemma4:26b, LAN-exposed + status window
#   ./start-ollama.sh --local    same, but bound to 127.0.0.1 only (no LAN exposure)
#   ./start-ollama.sh --code     also create "gemma4-code" (64K context) and warm that instead
#   ./start-ollama.sh --stop     stop the server, the watchdog and the status window
#
# How the "cannot be closed" window works:
#   - the window is created WITHOUT the close button (no NSWindowStyleMaskClosable)
#     and pinned to the floating (always-on-top) window level
#   - a watchdog re-opens the window within 5 s if it is ever killed
#   - the watchdog closes the window automatically once Ollama stops
#     or the model is unloaded (e.g. after OLLAMA_KEEP_ALIVE expires)
#
# Security: the Ollama API has NO authentication. Only expose it on a trusted home
# network — never forward port 11434 on your router.

set -euo pipefail

MODEL="gemma4:26b"
PORT="11434"
BIND="0.0.0.0"
OLLAMA_DIR="$HOME/ollama"
LOG="$OLLAMA_DIR/logs/ollama-serve.log"
PIDFILE="$OLLAMA_DIR/ollama-serve.pid"
WATCHPID="$OLLAMA_DIR/ollama-status-watch.pid"
WINJS="$OLLAMA_DIR/ollama-status-window.js"
API="http://127.0.0.1:${PORT}"

case "${1:-}" in
  --stop)
    [[ -f "$WATCHPID" ]] && kill "$(cat "$WATCHPID")" 2>/dev/null || true
    pkill -f "$WINJS" 2>/dev/null || true
    rm -f "$WATCHPID"
    if [[ -f "$PIDFILE" ]]; then kill "$(cat "$PIDFILE")" 2>/dev/null || true; rm -f "$PIDFILE"; fi
    pkill -f "ollama serve" 2>/dev/null || true
    echo "Ollama server + status window stopped."
    exit 0 ;;
  --local) BIND="127.0.0.1" ;;
  --code)  CREATE_CODE=1 ;;
esac

# --- stop any status window / watchdog left over from an earlier run -----------
if [[ -f "$WATCHPID" ]]; then kill "$(cat "$WATCHPID")" 2>/dev/null || true; rm -f "$WATCHPID"; fi
pkill -f "$WINJS" 2>/dev/null || true

# 1. Raise the GPU wired-memory limit.
#    On a 24 GB Mac, macOS caps how much unified memory the GPU may wire (~19 GB here).
#    gemma4:26b (~16 GB) plus its KV cache needs more. Requires sudo; resets on reboot,
#    so rerun this script after each restart (or add it to a LaunchAgent).
echo "==> Raising GPU wired limit to 20 GB"
sudo sysctl -w iogpu.wired_limit_mb=20000 >/dev/null 2>&1 \
  || echo "    ! could not raise wired limit — model may offload to CPU (check 'ollama ps')"

# 2. Start the server if it isn't already up
if curl -sf "$API/api/version" >/dev/null 2>&1; then
  echo "==> Ollama already running"
  if pgrep -x "Ollama" >/dev/null 2>&1; then
    echo "    (started by the desktop app — to expose it to the LAN run:"
    echo "     launchctl setenv OLLAMA_HOST '0.0.0.0:11434'   then quit & reopen the app)"
  fi
else
  if pgrep -x "Ollama" >/dev/null 2>&1; then
    echo "==> The Ollama desktop app is running and owns the server."
    echo "    Quit the app and rerun this script, or use the launchctl command above."
    exit 1
  fi
  echo "==> Starting ollama serve on ${BIND}:${PORT} (log: $LOG)"
  export OLLAMA_HOST="${BIND}:${PORT}"   # bind address for the SERVER process
  export OLLAMA_KEEP_ALIVE="30m"         # keep model resident 30 min after last call
  export OLLAMA_NUM_PARALLEL=1           # one request at a time on 24 GB
  # export OLLAMA_ORIGINS="*"            # only needed if browser apps on other machines call the API
  mkdir -p "$(dirname "$LOG")"
  nohup ollama serve >>"$LOG" 2>&1 &
  echo $! >"$PIDFILE"
  for _ in {1..30}; do curl -sf "$API/api/version" >/dev/null 2>&1 && break; sleep 1; done
  curl -sf "$API/api/version" >/dev/null || { echo "server failed to start — see $LOG"; exit 1; }
fi

# management commands always go to localhost
run() { OLLAMA_HOST="127.0.0.1:${PORT}" "$@"; }

# 3. Pull the model if missing
if ! run ollama list | awk '{print $1}' | grep -qx "$MODEL"; then
  echo "==> Pulling $MODEL (~16 GB, one-time download)..."
  run ollama pull "$MODEL"
else
  echo "==> $MODEL already present"
fi

# 4. Optional: 64K-context variant for coding agents
if [[ "${CREATE_CODE:-0}" == "1" ]]; then
  MF="$OLLAMA_DIR/modelfiles/gemma4-code.Modelfile"
  mkdir -p "$(dirname "$MF")"
  printf 'FROM %s\nPARAMETER num_ctx 65536\nPARAMETER temperature 0.2\n' "$MODEL" >"$MF"
  echo "==> Creating gemma4-code (num_ctx=64K) from $MF"
  run ollama create gemma4-code -f "$MF"
  MODEL="gemma4-code"
fi

# 5. Warm the model so it loads into memory now
echo "==> Warming $MODEL ..."
curl -sf "$API/api/generate" -d "{\"model\":\"$MODEL\",\"prompt\":\"Reply with: OK\",\"stream\":false,\"options\":{\"num_predict\":4}}" >/dev/null
echo "==> $MODEL is loaded."
run ollama ps

# 6. Desktop status window (no close button, always on top) + watchdog ----------
# current_lan_ip: the Mac's CURRENT LAN IP (re-queried, so DHCP changes are picked up)
current_lan_ip() { ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true; }

write_status_window() {
  local model="$1" lan_url="$2" lan_ip="${3:-}"
  local -a lines
  lines=(
    "OLLAMA RUNNING"
    ""
    "Model : ${model}"
    "Local : http://127.0.0.1:${PORT}"
  )
  [[ -n "$lan_url" ]] && lines+=("LAN   : ${lan_url}")
  [[ -n "$lan_url" ]] && lines+=("mDNS  : http://$(scutil --get LocalHostName).local:${PORT}  (stable name, survives IP changes)")
  [[ -n "$lan_url" ]] && lines+=("other computers: export OLLAMA_HOST=${lan_ip}:${PORT}")
  lines+=("")
  lines+=("No close button: this window stays on top while the model is loaded.")
  lines+=("It closes by itself when Ollama stops or unloads the model.")

  local js_lines
  js_lines=$(printf '"%s",' "${lines[@]}"); js_lines=${js_lines%,}

  # JXA: build a titled window WITHOUT the Closable style bit, pinned to the
  # floating window level so it stays on top. NOTE: on this macOS the JXA bridge
  # does not expose initWithContentRect:styleMask:backing:defer: / setFrame:display:,
  # so we use NSWindow.new + setStyleMask(5) + setContentSize + setFrameOrigin.
  cat > "$WINJS" <<EOF
ObjC.import('AppKit');
var lines = [${js_lines}];
var W = 620, H = 46 + lines.length * 20;
var app = $.NSApplication.sharedApplication;
app.setActivationPolicy(0);                        // NSApplicationActivationPolicyRegular
var win = $.NSWindow.new;
win.setStyleMask(5);                               // Titled(1)|Miniaturizable(4) -- Closable(2) omitted => no close button
win.setContentSize($.NSMakeSize(W, H));
var sf = $.NSScreen.mainScreen.frame.size;         // center on screen
win.setFrameOrigin($.NSMakePoint((sf.width - W) / 2, (sf.height - H) / 2));
win.setTitle("Ollama Status");
win.setLevel(3);                                   // NSFloatingWindowLevel => always on top
win.setReleasedWhenClosed(false);
win.setHidesOnDeactivate(false);
lines.forEach(function (l, i) {
  var f = $.NSTextField.alloc.initWithFrame($.NSMakeRect(16, H - 32 - i * 20, W - 32, 18));
  f.setEditable(false); f.setBordered(false); f.setDrawsBackground(false); f.setSelectable(true);
  f.setStringValue(l);
  f.setFont($.NSFont.systemFontOfSize(13));
  win.contentView.addSubview(f);
});
win.makeKeyAndOrderFront(null);
app.activateIgnoringOtherApps(true);
app.run();
EOF
}

# Watchdog owns the status window:
#   - opens it right away, re-opens it within 5 s if it is ever killed
#   - REFRESHES it within 5 s if the Mac's LAN IP changes (DHCP renewal etc.),
#     so the URL shown on the desktop is always the current one
#   - closes the window and exits when Ollama stops or the model is unloaded
echo "==> Starting status window + watchdog (model: ${MODEL})"
(
  LAST_URL="__init__"
  while true; do
    curl -sf "$API/api/version" >/dev/null 2>&1 || break                        # server down
    OLLAMA_HOST="127.0.0.1:${PORT}" ollama ps 2>/dev/null | grep -q "${MODEL%%:*}" || break  # model unloaded
    IP=$(current_lan_ip)
    URL=""
    [[ "$BIND" == "0.0.0.0" && -n "$IP" ]] && URL="http://${IP}:${PORT}"
    if [[ "$URL" != "$LAST_URL" ]]; then
      LAST_URL="$URL"
      write_status_window "$MODEL" "$URL" "$IP"     # regenerate window JS with current IP
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
) &
echo $! > "$WATCHPID"

LAN_IP=$(current_lan_ip)
echo
echo "  local:  $API"
[[ "$BIND" == "0.0.0.0" && -n "$LAN_IP" ]] && echo "  LAN:    http://${LAN_IP}:${PORT}  (status window auto-updates if the IP changes)"
echo "  Status window is on the desktop (closes automatically when the model stops)."
echo "  Stop everything with: $0 --stop"

# Verify the LAN address actually answers (matters when the desktop app owns the server)
if [[ "$BIND" == "0.0.0.0" && -n "$LAN_IP" ]]; then
  if curl -sf -m 3 "http://${LAN_IP}:${PORT}/api/version" >/dev/null 2>&1; then
    echo "  LAN check: OK — http://${LAN_IP}:${PORT} answers; other devices can connect."
  else
    echo "  LAN check: NOT reachable on ${LAN_IP} — server is bound to localhost only."
    echo "           Fix: quit the Ollama desktop app and rerun this script, or run:"
    echo "           launchctl setenv OLLAMA_HOST '0.0.0.0:11434'  and quit/reopen the app"
  fi
fi
