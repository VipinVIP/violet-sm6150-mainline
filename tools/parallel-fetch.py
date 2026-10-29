#!/usr/bin/env python3
"""Fetch a URL in N parallel byte ranges (the Leipzig corpus server throttles
each connection hard, so 1 stream crawls at ~20 KB/s while N streams scale
roughly linearly).

    parallel-fetch.py URL OUTFILE [CONNECTIONS] [EXPECTED_SIZE]

Writes to OUTFILE.part, prints progress every 5 s, and only renames to OUTFILE
once every byte arrived; a truncated file is never left under the final name.
"""
import os
import sys
import threading
import time
import urllib.request

URL, OUT = sys.argv[1], sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 8
SIZE = int(sys.argv[4]) if len(sys.argv) > 4 else None

if SIZE is None:
    req = urllib.request.Request(URL, method="HEAD")
    with urllib.request.urlopen(req, timeout=30) as r:
        SIZE = int(r.headers["Content-Length"])
print(f"{SIZE/1048576:.1f} MiB in {N} ranges -> {OUT}", flush=True)

part = OUT + ".part"
step = SIZE // N + 1
done = [0] * N
lock = threading.Lock()
fail = []


def worker(i):
    start = i * step
    end = min(SIZE - 1, start + step - 1)
    if start > end:
        return
    for attempt in range(4):
        try:
            req = urllib.request.Request(URL, headers={"Range": f"bytes={start}-{end}"})
            with urllib.request.urlopen(req, timeout=45) as r, open(f"{part}.{i}", "r+b") as f:
                f.seek(0)
                pos = start
                while True:
                    chunk = r.read(65536)
                    if not chunk:
                        break
                    f.write(chunk)
                    pos += len(chunk)
                    with lock:
                        done[i] = pos - start
                if pos - start >= end - start + 1:
                    return
        except Exception as e:  # noqa: BLE001 - retry any transport error
            print(f"  range {i} attempt {attempt+1}: {e}", flush=True)
            time.sleep(2 * (attempt + 1))
    fail.append(i)


for i in range(N):
    open(f"{part}.{i}", "wb").close()
threads = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(N)]
t0 = time.time()
for t in threads:
    t.start()

while any(t.is_alive() for t in threads):
    time.sleep(5)
    with lock:
        got = sum(done)
    el = max(time.time() - t0, 0.001)
    print(f"  {got/1048576:5.1f}/{SIZE/1048576:.1f} MiB  {got/el/1024:5.0f} KB/s  "
          f"{100*got/SIZE:3.0f}%", flush=True)

for t in threads:
    t.join()

if fail:
    sys.exit(f"ranges failed: {fail}")

with open(part, "wb") as out:
    for i in range(N):
        with open(f"{part}.{i}", "rb") as f:
            while True:
                b = f.read(1 << 20)
                if not b:
                    break
                out.write(b)
        os.unlink(f"{part}.{i}")

got = os.path.getsize(part)
if got != SIZE:
    sys.exit(f"size mismatch: got {got}, expected {SIZE}")

os.replace(part, OUT)
print(f"done: {OUT} ({got} bytes, {got/1048576:.1f} MiB, {(time.time()-t0)/60:.1f} min)", flush=True)
