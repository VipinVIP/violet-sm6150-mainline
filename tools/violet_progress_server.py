#!/usr/bin/env python3
"""Serve the violet/glissando build status as a live web page.

The chat-side terminal pane is easy to miss, so this exposes the same dashboard
the shell script prints as an auto-refreshing page that the Hermes preview pane
can show beside the chat:

    python3 tools/violet_progress_server.py 8765 &
    # then: desktop_preview open http://127.0.0.1:8765/

The page re-fetches /status every 5 s.  Each frame runs
tools/violet-progress.sh --once, whose phone block costs one ssh round trip, so
frames are cached for 4 s to keep both the phone and this process quiet when
several viewers poll at once.
"""
import html
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "tools" / "violet-progress.sh"
CACHE_TTL = 4.0

_lock = threading.Lock()
_cache = {"at": 0.0, "body": "", "err": ""}


def frame() -> tuple[str, str]:
    with _lock:
        now = time.monotonic()
        if now - _cache["at"] < CACHE_TTL and (_cache["body"] or _cache["err"]):
            return _cache["body"], _cache["err"]
        try:
            out = subprocess.run(
                ["bash", str(SCRIPT), "--once"],
                capture_output=True, text=True, timeout=25,
            )
            body = out.stdout
            err = out.stderr.strip()
        except subprocess.TimeoutExpired:
            body, err = _cache["body"], "status frame timed out (ssh busy?)"
        if body:
            _cache.update(at=now, body=body, err=err)
        return _cache["body"], err or _cache["err"]


PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><title>violet build</title>
<style>
  :root {{ color-scheme: dark; }}
  body {{ margin:0; background:#11131a; color:#d8dee9;
         font:13px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace; }}
  header {{ display:flex; align-items:center; gap:10px;
            padding:10px 14px; border-bottom:1px solid #262b36; }}
  h1 {{ font-size:13px; font-weight:600; margin:0; color:#e5e9f0; }}
  .dot {{ width:8px; height:8px; border-radius:50%; background:#5aa87a; }}
  .dot.stale {{ background:#c9824a; }}
  .age {{ color:#7b8496; margin-left:auto; }}
  pre {{ margin:0; padding:12px 14px; white-space:pre-wrap;
         word-break:break-word; font:inherit; }}
  .err {{ color:#d08770; padding:0 14px 10px; }}
</style></head><body>
<header><span class="dot" id="d"></span><h1>violet / glissando keyboard build</h1>
<span class="age" id="a">loading…</span></header>
<pre id="s">(first frame: querying the phone…)</pre>
<div class="err" id="e"></div>
<script>
let fails = 0;
async function tick() {{
  try {{
    const r = await fetch('/status?ts=' + Date.now(), {{cache: 'no-store'}});
    const t = await r.text();
    document.getElementById('s').textContent = t;
    fails = 0;
    document.getElementById('d').className = 'dot';
    document.getElementById('a').textContent = 'updated ' + new Date().toLocaleTimeString();
    document.getElementById('e').textContent = '';
  }} catch (e) {{
    fails++;
    document.getElementById('d').className = 'dot stale';
    document.getElementById('a').textContent = 'stale (' + fails + ')';
    document.getElementById('e').textContent = String(e);
  }}
}}
tick(); setInterval(tick, 5000);
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        if self.path.startswith("/status"):
            body, err = frame()
            text = body or "waiting for the first frame…"
            if err:
                text += f"\n\n[stderr] {err}"
            payload = text.encode()
            ctype = "text/plain; charset=utf-8"
        elif self.path in ("/", "/index.html"):
            payload = PAGE.format().encode()
            ctype = "text/html; charset=utf-8"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *a):  # keep the console clean
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"violet progress server on http://127.0.0.1:{port}/", flush=True)
    srv.serve_forever()
