# Ollama on Mac mini M6 (24 GB) — Setup & Runbook

Everything in this folder (`~/ollama/`) is about running a local Ollama server on the
**Mac mini M6, 24 GB unified memory**, exposed to the home WiFi, with a desktop status
window that shows the URL + model name and cannot be closed while the model is running.

---

## 1. Folder layout

```
~/ollama/
├── start-ollama.sh                # the script (executable)
├── README.md                      # this file
├── logs/ollama-serve.log          # server + status-window logs
├── ollama-serve.pid               # PID of the server started by the script
├── ollama-status-watch.pid        # PID of the watchdog
├── ollama-status-window.js        # generated AppleScript/JXA status window
└── modelfiles/                    # created when using --code (gemma4-code.Modelfile)
```

---

## 2. Running the script

```bash
~/ollama/start-ollama.sh           # start server (if needed) + pull & warm gemma4:26b + LAN expose + status window
~/ollama/start-ollama.sh --local   # same, but bound to 127.0.0.1 only (no LAN exposure)
~/ollama/start-ollama.sh --code    # also create "gemma4-code" (64K context, temp 0.2) and warm that instead
~/ollama/start-ollama.sh --stop    # stop server + watchdog + status window
```

### What the script does, step by step

1. **Raises the GPU wired-memory limit** — `sudo sysctl -w iogpu.wired_limit_mb=20000`.
   macOS caps how much of the 24 GB unified memory the GPU may use (~19 GB); a ~16 GB
   model + KV cache needs more. **This resets on every reboot — rerun the script after
   restarting the Mac.** Verify with `ollama ps`: the model's PROCESSOR column must say
   **100% GPU** (a CPU/GPU split means it is offloading and will be slow).
2. **Starts `ollama serve`** in the background (unless already running) with:
   - `OLLAMA_HOST=0.0.0.0:11434` — binds all interfaces so the LAN can reach it
     (use `--local` for `127.0.0.1` only)
   - `OLLAMA_KEEP_ALIVE=30m` — model stays resident 30 min after the last request
   - `OLLAMA_NUM_PARALLEL=1` — one request at a time (safe on 24 GB)
   - Optional: `OLLAMA_ORIGINS="*"` — only needed if **browser** apps on other machines
     call the API (CLI clients don't need it)
3. **Pulls `gemma4:26b`** if not already present (~16 GB one-time download).
4. **`--code`**: creates `gemma4-code` from a Modelfile (`num_ctx 65536`,
   `temperature 0.2`) and warms that instead — use this for coding agents, which need
   ≥64K context.
5. **Warms the model** with a tiny request so it is loaded into memory immediately.
6. **Opens the desktop status window** and starts the **watchdog** (see §5).

> If the **Ollama desktop app** is running, it owns the server and the script's
> `OLLAMA_HOST` won't apply. Either quit the app and use the script, or run:
> `launchctl setenv OLLAMA_HOST "0.0.0.0:11434"` then quit & reopen the app.

---

## 3. Accessing Ollama from other computers on the WiFi

1. **Best: reserve the Mac mini's IP in the router's DHCP** so it never changes
   (current IP: `192.168.178.218`). If you skip this, see the IP-change note below.
2. On the Mac mini, allow incoming connections when the macOS firewall prompts for Ollama
   (System Settings → Network → Firewall).
3. Test from another computer:
   ```bash
   curl http://192.168.178.218:11434/api/tags
   ```
4. On each client machine (e.g. your other laptop):
   ```bash
   export OLLAMA_HOST=192.168.178.218:11434
   ollama run gemma4-code "hello"       # runs on the Mac mini
   ```
   Or point GUI clients (Open WebUI, Cherry Studio, Continue, Cline, OpenCode…) at
   `http://192.168.178.218:11434`.

**If the Mac mini's IP changes while Ollama is running (DHCP renewal, router restart):**
- Ollama keeps working — it is bound to `0.0.0.0`, i.e. **all interfaces**, so the *new*
  IP answers immediately. No restart of Ollama needed.
- The desktop status window **auto-refreshes within 5 s** and shows the new LAN URL
  (the watchdog re-queries the current IP every 5 s and rebuilds the window).
- **Best fix for a dynamic IP: use the Bonjour hostname instead of the IP.** The mini
  advertises `Biswajits-Mac-mini.local` via mDNS, which always resolves to the *current*
  LAN IP. Clients use:
  ```bash
  export OLLAMA_HOST=biswajits-mac-mini.local:11434
  # or in code: base_url="http://biswajits-mac-mini.local:11434"
  curl http://biswajits-mac-mini.local:11434/api/tags
  ```
  The status window shows this mDNS URL too. (On the mini itself, `.local` resolves to
  127.0.0.1 — that's normal; from other machines it resolves to the real LAN IP.)
- Belt-and-braces: also reserve the current IP (`192.168.178.218`) for the mini's MAC in
  the router's DHCP settings so the IP stops changing at all.

**Troubleshooting:**
- *Connection refused / "could not connect to server" from a client* → the server is
  bound to `127.0.0.1` only. Check with `lsof -iTCP:11434 -sTCP:LISTEN -n -P` (should show
  `*:11434`, not `127.0.0.1:11434`). Fix: `launchctl setenv OLLAMA_HOST "0.0.0.0:11434"`,
  quit the Ollama desktop app, and rerun `~/ollama/start-ollama.sh --code` (or reopen the
  app — the launchctl env makes it bind `0.0.0.0` too). The script's `LAN check:` line
  confirms reachability.
- *Timeout* → firewall blocking TCP 11434, or the two devices are on different subnets
  (e.g. a "guest" WiFi network isolates clients).
- *403 from browser apps* → set `OLLAMA_ORIGINS` (specific origin, or `*`).
- *Stopped when Mac mini sleeps* → disable sleep for the mini while serving.

---

## 4. Security — read this once, remember always

- **The Ollama API has NO authentication.** Anyone who can reach port 11434 can run
  prompts, pull and delete models on your Mac.
- Use LAN exposure **only on a trusted home network**. Put guest/IoT devices on a
  separate guest network.
- **Never forward port 11434 on the router** and never expose it via ngrok/cloudflared
  without an authenticating proxy in front. If you need access from outside home, use
  **Tailscale** or an **SSH tunnel** instead:
  ```bash
  ssh -N -L 11435:127.0.0.1:11434 user@mac-mini.local   # then use OLLAMA_HOST=127.0.0.1:11435
  ```

---

## 5. The desktop status window ("cannot be closed")

- After the model warms up, a window appears showing the **model name**, **local URL**
  (`http://127.0.0.1:11434`) and **LAN URL** (`http://<mac-ip>:11434`), plus the
  `OLLAMA_HOST` hint for other computers.
- The window is created **without a close button** (no `NSWindowStyleMaskClosable`) and
  pinned **always-on-top** (`NSFloatingWindowLevel`).
- A **watchdog** checks every 5 s that the server is up **and** the model is loaded
  (`ollama ps`). If the window is killed by any means, it is **re-opened within 5 s**.
- The watchdog also re-reads the Mac's **current LAN IP** every 5 s; if it changed, the
  window is rebuilt with the **new URL** — so the desktop always shows the address your
  other laptop should use right now.
- The window **closes by itself** when Ollama stops or the model is unloaded (e.g. after
  `OLLAMA_KEEP_ALIVE` expires) — that is the only way it goes away.
- `--stop` kills server + watchdog + window.
- Implementation note: the window is built with JXA (`osascript -l JavaScript`). On this
  macOS the JXA bridge does **not** expose `initWithContentRect:styleMask:backing:defer:`
  or `setFrame:display:`, so the script uses `$.NSWindow.new` + `setStyleMask(5)`
  (closable bit omitted) + `setContentSize` + `setFrameOrigin`, and `null` (not `nil`).
  If the window ever fails, check `~/ollama/logs/ollama-serve.log` for osascript errors.

---

## 6. Model recommendations for the M6 24 GB (Nov 2026)

Usable GPU memory ≈ 19–20 GB (after raising the wired limit). **MoE models save compute,
not memory** — all weights must fit in RAM.

| Role | Ollama tag | Size | Speed on M6 24 GB (community) | Notes |
|---|---|---|---|---|
| Daily driver (code + chat) | `gpt-oss:20b` | 14 GB | ~45 tok/s | Comfortable fit, 128K ctx, great tool-calling |
| Quality / vision | `gemma4:26b` | ~16 GB | ~48 tok/s | 26B-A4B MoE, 256K ctx, image input |
| Agent harness (Cline/OpenCode/Continue) | `devstral:24b` | 14 GB | good | Mistral agent-tuned coder, SWE-bench Verified 68%, reads screenshots |
| Coding specialist (tight fit) | `qwen3-coder:30b` | 19 GB | ~62 tok/s | 30B-A3B MoE, 256K ctx; keep `num_ctx` ≤ 32K on 24 GB |
| Small/fast | `gemma4:12b` | 8 GB | ~19 tok/s | Comfortable; good coder for 16 GB machines |

**Avoid on 24 GB:** `qwen3.8:27b` (dense, ~19 GB, only ~10 tok/s — too slow for daily
work), `gemma4:31b` (19–20 GB, tight, ~8 tok/s), `qwen3.6:35b` (23 GB — doesn't fit).

### Is Gemma 4 suitable?

- **Yes for coding** — Gemma 4 (Apache 2.0) is strong at code (LiveCodeBench v6: 77% on
  26B-A4B, 80% on 31B) with native function calling, 128K/256K context, and MTP
  speculative decoding (faster output).
- On 24 GB use **`gemma4:12b`** (comfortable) or **`gemma4:26b`** (sweet spot).
- Gemma 4 **understands** images/video/audio (input) — OCR, screenshots, charts — but
  **does NOT generate images** (see §8).
- Tags on Ollama: `gemma4:e2b` (4.6 GB), `gemma4:e4b`/`latest` (6.6 GB), `gemma4:12b`
  (8 GB), `gemma4:26b` (~16 GB), `gemma4:31b` (~19 GB).

### Coding-agent tips

- Always set a big context. Default is small on 24 GB. Use `--code` (creates
  `gemma4-code` with `num_ctx 65536`), or a Modelfile:
  ```
  FROM gemma4:26b
  PARAMETER num_ctx 65536
  PARAMETER temperature 0.2
  ```
- Keep the model warm: `OLLAMA_KEEP_ALIVE=30m` (set by the script).
- Check `ollama ps` — PROCESSOR must be **100% GPU**.

---

## 7. Auto-start on boot

1. Add `~/ollama/start-ollama.sh` to **System Settings → General → Login Items**.
2. Persist the env vars once:
   ```bash
   launchctl setenv OLLAMA_HOST "0.0.0.0:11434"
   launchctl setenv OLLAMA_KEEP_ALIVE "30m"
   ```
3. The `iogpu.wired_limit_mb` sysctl resets on reboot — the script re-applies it each
   run, so running the script at login covers it.

---

## 8. Running OpenCode with the local model

A ready-made config is installed at **`~/.config/opencode/opencode.json`**:

- default model: `ollama/gemma4-code`
- provider `ollama` → `baseURL: http://127.0.0.1:11434/v1` (OpenAI-compatible endpoint)
- also lists `gemma4:26b`, `gpt-oss:20b`, `devstral:24b` for `/models` switching

**First run on the Mac mini:**

```bash
~/ollama/start-ollama.sh --code     # pulls gemma4:26b, creates + warms gemma4-code (64K ctx)
opencode                            # in any project — uses ollama/gemma4-code by default
```

- Inside OpenCode: `/models` to switch models per session;
  `opencode run --model ollama/gpt-oss:20b "..."` for a one-shot command.
- One-command alternative: `ollama launch opencode --model gemma4-code`
  (inline config, does not touch opencode.json).
- **From another computer over WiFi:** edit `baseURL` in the other machine's
  `opencode.json` to `http://biswajits-mac-mini.local:11434/v1` (stable mDNS name —
  preferred over the dynamic IP `192.168.178.218`) — works because the script exposes
  Ollama on `0.0.0.0:11434`.
- ⚠️ **Context:** OpenCode needs **≥ 64K tokens**. Ollama auto-sizes context from free
  memory (can be as low as 32K on 24 GB), which breaks agent sessions. Always use
  **`gemma4-code`** (built by `--code` with `PARAMETER num_ctx 65536`) for agent work.
- Verify it's local: while OpenCode works, `ollama ps` on the mini shows the model at
  **100% GPU**; `/models` in OpenCode shows `ollama/...`.

## 9. Image generation on the Mac mini (separate from Ollama)

Ollama's experimental image generation was **removed in Aug 2026** — use a dedicated tool:

- **Tools:** **Draw Things** (free, Mac App Store, native Metal, easiest) or **mflux**
  (CLI, scriptable) / ComfyUI (node workflows).
- **Models (both Apache 2.0, commercial OK):**
  - **FLUX.2 [klein] 4B** — ~4.3 GB download, **~7–17 s per 1024×1024 image on M6 24 GB**.
    Best for fast drafts, product shots, edits.
  - **Z-Image-Turbo** — ~5.5 GB, **~17–50 s/image on M6**; better text-in-image and
    photorealism.
- Both fit easily in 24 GB (peak 5–11 GiB), so image gen can run alongside the LLM.
- mflux example:
  ```bash
  mflux-generate-flux2 --model mflux-community/flux2-klein-4b-mflux-q4 \
    --prompt "a red fox in fresh snow at sunrise" --width 1024 --height 1024
  ```
- Check the license of the exact checkpoint (FLUX 9B variants are non-commercial).

---

## 10. Quick command cheat sheet

```bash
~/ollama/start-ollama.sh                 # start everything
~/ollama/start-ollama.sh --stop          # stop everything
ollama ps                                # is the model loaded? 100% GPU?
ollama list                              # installed models
ollama pull gpt-oss:20b                  # add another model
curl http://127.0.0.1:11434/api/version  # server alive?
curl http://<mac-ip>:11434/api/tags      # from another machine
sudo sysctl iogpu.wired_limit_mb=20000   # after reboot, if model offloads
tail -f ~/ollama/logs/ollama-serve.log   # server logs
opencode                                 # coding agent on local model (see §8)
ollama launch opencode --model gemma4-code
```

---

## 11. If you later want bigger/better agents (Nemotron etc.)

NVIDIA **Nemotron** (open weights, agent-focused) needs far more than 24 GB locally — e.g.
Nemotron 3.5 Lightning 30B-A3B (~18 GB, ~45 tok/s on M6) fits but is modest;
Super VL (120B) / Ultra (550B) require 64 GB+ Macs or cloud/NIM. If you go that route,
treat it as a cloud/API model or a bigger machine — not something to run on this mini.
Nemotron models also **understand** multimodal input; image *generation* from NVIDIA is
Cosmos-Predict2 / Cosmos 3 Text2Image, not Nemotron.

---

*Last updated: 2026-11-24 · Mac mini M6 24 GB · Ollama v0.40.x · macOS 27*
