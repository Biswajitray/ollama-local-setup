# ollama-common.sh — shared helpers for the start-*.sh scripts in ~/ollama.
# Sourced, not executed. Entry scripts set `set -euo pipefail` before sourcing;
# the watchdog sources this with only `set -u` (its loop must survive errors).
#
# Security: the Ollama API has NO authentication. Only expose on a trusted home
# network — never forward port 11434 on the router.

OLLAMA_DIR="${OLLAMA_DIR:-$HOME/ollama}"
PORT="${PORT:-11434}"
LOG="$OLLAMA_DIR/logs/ollama-serve.log"
PIDFILE="$OLLAMA_DIR/ollama-serve.pid"
WATCHPID="$OLLAMA_DIR/ollama-status-watch.pid"
WINJS="$OLLAMA_DIR/ollama-status-window.js"
API="http://127.0.0.1:${PORT}"

log() { echo "==> $*"; }

# --- locking (fix: concurrent runs spawned duplicate watchdogs/windows) --------
# Portable lock: `mkdir` is atomic on macOS (no flock binary here). Stale-lock
# recovery: if the recorded PID is dead, remove the lock dir and retry once.
LOCKDIR="$OLLAMA_DIR/.lock.d"
SCRIPT_NAME="${SCRIPT_NAME:-$0}"
# Top-level EXIT trap (a trap set INSIDE a zsh function fires at function return).
# Only the lock holder removes the lock dir.
trap '[[ -f "$LOCKDIR/pid" && "$(cat "$LOCKDIR/pid" 2>/dev/null)" == "$$" ]] && rm -rf "$LOCKDIR"' EXIT

with_lock() {
  local tries=0 oldpid
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    oldpid=$(cat "$LOCKDIR/pid" 2>/dev/null || true)
    if [[ -n "$oldpid" ]] && ! kill -0 "$oldpid" 2>/dev/null; then
      rm -rf "$LOCKDIR"          # stale lock: holder process is dead
      continue
    fi
    tries=$((tries + 1))
    if [[ $tries -ge 2 ]]; then
      echo "==> Another start script holds $LOCKDIR (pid ${oldpid:-?}). If stale: rm -rf $LOCKDIR; or run: $SCRIPT_NAME --stop" >&2
      exit 1
    fi
    sleep 1
  done
  echo $$ >"$LOCKDIR/pid"
}

# --- LAN IP (fix: try en0..en5, not just en0/en1) -------------------------------
current_lan_ip() {
  local iface ip
  for iface in en0 en1 en2 en3 en4 en5; do
    ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    if [[ -n "$ip" ]]; then echo "$ip"; return 0; fi
  done
  return 0
}

server_up() { curl -sf "$API/api/version" >/dev/null 2>&1; }

# management commands always go to localhost
run() { OLLAMA_HOST="127.0.0.1:${PORT}" "$@"; }

# --- server lifecycle ----------------------------------------------------------
start_server() {
  local bind="$1"
  if server_up; then
    log "Ollama already running"
    if pgrep -x "Ollama" >/dev/null 2>&1; then
      echo "    (started by the desktop app — to expose it to the LAN run:"
      echo "     launchctl setenv OLLAMA_HOST '0.0.0.0:11434'   then quit & reopen the app)"
    fi
    return 0
  fi
  if pgrep -x "Ollama" >/dev/null 2>&1; then
    echo "==> The Ollama desktop app is running and owns the server." >&2
    echo "    Quit the app and rerun this script, or use the launchctl command above." >&2
    return 1
  fi
  log "Starting ollama serve on ${bind}:${PORT} (log: $LOG)"
  export OLLAMA_HOST="${bind}:${PORT}"
  export OLLAMA_KEEP_ALIVE="${KEEP_ALIVE:-30m}"
  export OLLAMA_NUM_PARALLEL=1          # one request at a time on 24 GB
  export OLLAMA_MAX_LOADED_MODELS=1      # memory safety: only one model resident
  mkdir -p "$(dirname "$LOG")"
  nohup ollama serve >>"$LOG" 2>&1 &
  echo $! >"$PIDFILE"
  local i
  for i in {1..30}; do server_up && break; sleep 1; done
  server_up || { echo "server failed to start — see $LOG" >&2; return 1; }
}

pull_model() {
  local model="$1"
  if ! run ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$model"; then
    log "Pulling $model (one-time download)..."
    run ollama pull "$model"
  else
    log "$model already present"
  fi
}

# ensure_variant <name> <from_model> <num_ctx> <temperature>
ensure_variant() {
  local name="$1" from="$2" num_ctx="$3" temp="$4"
  local mf="$OLLAMA_DIR/modelfiles/$name.Modelfile"
  mkdir -p "$(dirname "$mf")"
  {
    echo "FROM $from"
    [[ -n "$num_ctx" ]] && echo "PARAMETER num_ctx $num_ctx"
    [[ -n "$temp" ]] && echo "PARAMETER temperature $temp"
  } >"$mf"
  log "Creating $name (num_ctx=${num_ctx:-default}, temperature=${temp:-default})"
  run ollama create "$name" -f "$mf"
}

# fix: warm-up failure must NOT abort the script under set -e
warm_model() {
  local model="$1"
  log "Warming $model ..."
  if ! curl -sf "$API/api/generate" \
       -d "{\"model\":\"$model\",\"prompt\":\"Reply with: OK\",\"stream\":false,\"options\":{\"num_predict\":4}}" >/dev/null; then
    echo "    ! warm-up request failed — model may still be loading; check 'ollama ps'"
  fi
  run ollama ps 2>/dev/null || true
}

# --- status window (fix: escape " and \ in generated JS string literals) --------
write_status_window() {
  local model="$1" lan_url="$2" lan_ip="${3:-}"
  local -a lines
  lines=(
    "OLLAMA RUNNING"
    ""
    "Model : ${model}"
    "Local : http://127.0.0.1:${PORT}"
  )
  if [[ -n "$lan_url" ]]; then
    lines+=("LAN   : ${lan_url}")
    lines+=("mDNS  : http://$(scutil --get LocalHostName 2>/dev/null || echo localhost).local:${PORT}  (stable name, survives IP changes)")
    lines+=("other computers: export OLLAMA_HOST=${lan_ip}:${PORT}")
  fi
  lines+=("")
  lines+=("No close button: this window stays on top while the model is loaded.")
  lines+=("It closes by itself when Ollama stops or unloads the model.")

  local l escaped
  local -a js
  for l in "${lines[@]}"; do
    escaped="${l//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    js+=("\"$escaped\"")
  done
  local js_lines
  js_lines=$(printf '%s,' "${js[@]}"); js_lines=${js_lines%,}

  # JXA: window WITHOUT the Closable style bit, pinned to floating (always-on-top)
  # level. On this macOS the JXA bridge does not expose
  # initWithContentRect:styleMask:backing:defer: / setFrame:display:, so we use
  # NSWindow.new + setStyleMask(5) + setContentSize + setFrameOrigin.
  cat >"$WINJS" <<EOF
ObjC.import('AppKit');
var lines = [${js_lines}];
var W = 620, H = 46 + lines.length * 20;
var app = \$.NSApplication.sharedApplication;
app.setActivationPolicy(0);
var win = \$.NSWindow.new;
win.setStyleMask(5);                               // Titled(1)|Miniaturizable(4); Closable(2) omitted => no close button
win.setContentSize(\$.NSMakeSize(W, H));
var sf = \$.NSScreen.mainScreen.frame.size;
win.setFrameOrigin(\$.NSMakePoint((sf.width - W) / 2, (sf.height - H) / 2));
win.setTitle("Ollama Status");
win.setLevel(3);                                   // NSFloatingWindowLevel => always on top
win.setReleasedWhenClosed(false);
win.setHidesOnDeactivate(false);
lines.forEach(function (l, i) {
  var f = \$.NSTextField.alloc.initWithFrame(\$.NSMakeRect(16, H - 32 - i * 20, W - 32, 18));
  f.setEditable(false); f.setBordered(false); f.setDrawsBackground(false); f.setSelectable(true);
  f.setStringValue(l);
  f.setFont(\$.NSFont.systemFontOfSize(13));
  win.contentView.addSubview(f);
});
win.makeKeyAndOrderFront(null);
app.activateIgnoringOtherApps(true);
app.run();
EOF
}

# --- watchdog (fix: own file so --stop can pkill it reliably even without pidfile)
start_watchdog() {
  local model="$1" bind="$2"
  stop_watchdog
  MODEL="$model" BIND="$bind" PORT="$PORT" OLLAMA_DIR="$OLLAMA_DIR" \
    nohup zsh "$OLLAMA_DIR/ollama-watchdog.sh" >>"$LOG" 2>&1 &
  echo $! >"$WATCHPID"
}

stop_watchdog() {
  if [[ -f "$WATCHPID" ]]; then kill "$(cat "$WATCHPID")" 2>/dev/null || true; rm -f "$WATCHPID"; fi
  pkill -f "ollama-watchdog.sh" 2>/dev/null || true
}

stop_all() {
  stop_watchdog
  pkill -f "$WINJS" 2>/dev/null || true
  if [[ -f "$PIDFILE" ]]; then kill "$(cat "$PIDFILE")" 2>/dev/null || true; rm -f "$PIDFILE"; fi
  pkill -f "ollama serve" 2>/dev/null || true
  log "Ollama server + status window stopped."
}

# --- LAN reachability check -----------------------------------------------------
lan_check() {
  local bind="$1" ip="$2"
  [[ "$bind" == "0.0.0.0" && -n "$ip" ]] || return 0
  if curl -sf -m 3 "http://${ip}:${PORT}/api/version" >/dev/null 2>&1; then
    echo "  LAN check: OK — http://${ip}:${PORT} answers; other devices can connect."
  else
    echo "  LAN check: NOT reachable on ${ip} — server is bound to localhost only."
    echo "           Fix: quit the Ollama desktop app and rerun this script, or run:"
    echo "           launchctl setenv OLLAMA_HOST '0.0.0.0:11434'  and quit/reopen the app"
  fi
}

# --- main flow used by every start-*.sh -----------------------------------------
# run_start <model> <bind>  — uses optional VARIANT_NAME/VARIANT_NUM_CTX/VARIANT_TEMP
run_start() {
  local model="$1" bind="$2"
  with_lock
  stop_watchdog
  pkill -f "$WINJS" 2>/dev/null || true

  log "Raising GPU wired limit to 20 GB"
  sudo sysctl -w iogpu.wired_limit_mb=20000 >/dev/null 2>&1 \
    || echo "    ! could not raise wired limit — model may offload to CPU (check 'ollama ps')"

  start_server "$bind"
  pull_model "$model"
  if [[ -n "${VARIANT_NAME:-}" ]]; then
    ensure_variant "$VARIANT_NAME" "$model" "${VARIANT_NUM_CTX:-}" "${VARIANT_TEMP:-}"
    model="$VARIANT_NAME"
  fi
  warm_model "$model"
  start_watchdog "$model" "$bind"

  local ip
  ip=$(current_lan_ip)
  echo
  echo "  local:  $API"
  if [[ "$bind" == "0.0.0.0" && -n "$ip" ]]; then
    echo "  LAN:    http://${ip}:${PORT}  (status window auto-updates if the IP changes)"
  fi
  echo "  Status window is on the desktop (closes automatically when the model stops)."
  echo "  Stop everything with: $0 --stop"
  lan_check "$bind" "$ip"
}
