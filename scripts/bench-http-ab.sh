#!/usr/bin/env bash
# A/B HTTP throughput: BASE_REF (default v0.43.7) vs HEAD.
# Interleaved rounds + median to cut thermal / scheduling noise.
#
# Env:
#   BASE_REF=v0.43.7   git ref for the baseline binary
#   ROUNDS=5           interleaved round count
#   DURATION=8s        wrk -d per path
#   PORT=18082
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18082}"
OUT="$ROOT/.tmp/bench-http-ab-results.txt"
BASE_REF="${BASE_REF:-v0.43.7}"
WT="$ROOT/.tmp/wt-bench-base"
ROUNDS="${ROUNDS:-5}"
DURATION="${DURATION:-8s}"
: > "$OUT"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "bench-http-ab: missing dependency '$1'" >&2
    exit 1
  }
}
need wrk
need lsof
need nc
need python3
need zig
need git

kill_port() {
  local pids
  pids=$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)
  if [[ -n "${pids}" ]]; then
    kill $pids 2>/dev/null || true
    sleep 0.2
    kill -9 $pids 2>/dev/null || true
  fi
}

stop_server() {
  if [[ -f "$ROOT/.tmp/bench-server.pid" ]]; then
    kill "$(cat "$ROOT/.tmp/bench-server.pid")" 2>/dev/null || true
    sleep 0.2
    kill -9 "$(cat "$ROOT/.tmp/bench-server.pid")" 2>/dev/null || true
    rm -f "$ROOT/.tmp/bench-server.pid"
  fi
  kill_port
}

start_server() {
  local bin="$1"
  stop_server
  HTTP_PORT="$PORT" BENCH_HOLD=1 "$bin" >"$ROOT/.tmp/bench-server.log" 2>&1 &
  echo $! >"$ROOT/.tmp/bench-server.pid"
  for _ in $(seq 1 200); do
    if nc -z 127.0.0.1 "$PORT" 2>/dev/null; then return 0; fi
    sleep 0.05
  done
  echo "server failed to listen ($bin)" >&2
  cat "$ROOT/.tmp/bench-server.log" >&2 || true
  return 1
}

# Multi-header load: ConnReadBuf zero-copy head is the claimed win vs tiny /ping.
HDR_ARGS=(
  -H "X-Trace-Id: 00000000-0000-4000-8000-000000000001"
  -H "X-Request-Id: bench-req-1"
  -H "X-Forwarded-For: 203.0.113.9"
  -H "Accept-Language: en-US,en;q=0.9"
  -H "User-Agent: zmodu-bench-http-ab/1"
  -H "X-Custom-A: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  -H "X-Custom-B: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  -H "X-Custom-C: cccccccccccccccccccccccccccccccc"
)

wrk_rps() {
  local path="$1"
  shift
  local out
  out=$(wrk -t4 -c50 -d"$DURATION" "$@" "http://127.0.0.1:${PORT}${path}" 2>/dev/null) || true
  local rps
  rps=$(awk '/Requests\/sec/ {print $2}' <<<"$out")
  if [[ -z "${rps}" ]]; then
    echo "bench-http-ab: wrk produced no Requests/sec for ${path}" >&2
    echo "0"
    return 1
  fi
  echo "$rps"
}

wrk_latency_snippet() {
  local path="$1"
  shift
  wrk -t4 -c50 -d10s --latency "$@" "http://127.0.0.1:${PORT}${path}" 2>/dev/null \
    | awk '/Requests\/sec|50%|99%|Latency/{print}'
}

ensure_worktree() {
  if [[ ! -d "$WT/.git" && ! -f "$WT/.git" ]]; then
    rm -rf "$WT"
    git -C "$ROOT" worktree add --detach "$WT" "$BASE_REF"
  else
    git -C "$WT" checkout --detach "$BASE_REF"
  fi
}

build_one() {
  local dir="$1"
  local stamp="$2"
  (
    cd "$dir/examples/http-stress-test"
    zig build -Doptimize=ReleaseFast
    cp -f zig-out/bin/http-stress-test "$ROOT/.tmp/http-stress-$stamp"
  )
}

SAFE_BASE=$(echo "$BASE_REF" | tr '/.' '__')
echo "bench-http-ab start $(date -u +%Y-%m-%dT%H:%M:%SZ) rounds=$ROUNDS duration=$DURATION base=$BASE_REF" | tee -a "$OUT"
echo "HEAD=$(git -C "$ROOT" rev-parse --short HEAD) vs $BASE_REF" | tee -a "$OUT"

ensure_worktree
echo "building ${BASE_REF}..." | tee -a "$OUT"
build_one "$WT" "base-$SAFE_BASE"
echo "building HEAD..." | tee -a "$OUT"
build_one "$ROOT" "head"

BIN_BASE="$ROOT/.tmp/http-stress-base-$SAFE_BASE"
BIN_HEAD="$ROOT/.tmp/http-stress-head"
trap 'stop_server' EXIT

# Warm both binaries once
start_server "$BIN_BASE"
wrk -t2 -c20 -d2s "http://127.0.0.1:${PORT}/ping" >/dev/null 2>&1 || true
stop_server
start_server "$BIN_HEAD"
wrk -t2 -c20 -d2s "http://127.0.0.1:${PORT}/ping" >/dev/null 2>&1 || true
stop_server

# Interleaved: odd rounds BASE first, even rounds HEAD first
for i in $(seq 1 "$ROUNDS"); do
  if (( i % 2 == 1 )); then
    order=(BASE HEAD)
  else
    order=(HEAD BASE)
  fi
  for label in "${order[@]}"; do
    bin="$BIN_BASE"
    [[ "$label" == HEAD ]] && bin="$BIN_HEAD"
    start_server "$bin"
    wrk -t2 -c20 -d1s "http://127.0.0.1:${PORT}/ping" >/dev/null 2>&1 || true
    ping=$(wrk_rps /ping || true)
    json=$(wrk_rps /json || true)
    # /headers may be absent on old baselines — treat missing as 0.
    headers=$(wrk_rps /headers "${HDR_ARGS[@]}" || true)
    echo "$label round$i ping_rps=$ping json_rps=$json headers_rps=$headers" | tee -a "$OUT"
    stop_server
  done
done

echo "---- latency snapshots ----" | tee -a "$OUT"
start_server "$BIN_BASE"
echo "BASE /ping latency:" | tee -a "$OUT"
wrk_latency_snippet /ping | tee -a "$OUT"
echo "BASE /headers latency:" | tee -a "$OUT"
wrk_latency_snippet /headers "${HDR_ARGS[@]}" | tee -a "$OUT" || true
stop_server
start_server "$BIN_HEAD"
echo "HEAD /ping latency:" | tee -a "$OUT"
wrk_latency_snippet /ping | tee -a "$OUT"
echo "HEAD /headers latency:" | tee -a "$OUT"
wrk_latency_snippet /headers "${HDR_ARGS[@]}" | tee -a "$OUT"
stop_server

BENCH_OUT="$OUT" BASE_REF="$BASE_REF" python3 - <<'PY' | tee -a "$OUT"
from pathlib import Path
import os, statistics
rows = {"BASE": {"ping": [], "json": [], "headers": []}, "HEAD": {"ping": [], "json": [], "headers": []}}
for line in Path(os.environ["BENCH_OUT"]).read_text().splitlines():
    if "ping_rps=" not in line:
        continue
    parts = line.split()
    label = parts[0]
    if label not in rows:
        continue
    d = {}
    for p in parts[1:]:
        if "=" in p:
            k, v = p.split("=", 1)
            try:
                d[k] = float(v)
            except ValueError:
                pass
    if "ping_rps" in d:
        rows[label]["ping"].append(d["ping_rps"])
        rows[label]["json"].append(d.get("json_rps", 0.0))
        rows[label]["headers"].append(d.get("headers_rps", 0.0))

def med(xs):
    return statistics.median(xs) if xs else float("nan")

base = os.environ.get("BASE_REF", "BASE")
print("---- summary (median of interleaved rounds) ----")
for label in ("BASE", "HEAD"):
    for key in ("ping", "json", "headers"):
        xs = rows[label][key]
        if not xs:
            print(f"{label:4s}  {key:7s} (no samples)")
            continue
        print(f"{label:4s}  {key:7s} median={med(xs):.1f}  mean={statistics.fmean(xs):.1f}  min={min(xs):.1f}  max={max(xs):.1f}  n={len(xs)}")
bp, hp = med(rows["BASE"]["ping"]), med(rows["HEAD"]["ping"])
bj, hj = med(rows["BASE"]["json"]), med(rows["HEAD"]["json"])
bh, hh = med(rows["BASE"]["headers"]), med(rows["HEAD"]["headers"])
def pct(a, b):
    return ((b / a) - 1) * 100 if a and a == a and a > 0 else float("nan")
print(f"HEAD vs BASE ({base}): ping {pct(bp, hp):+.1f}%  json {pct(bj, hj):+.1f}%  headers {pct(bh, hh):+.1f}%  (median)")
PY

echo "bench-http-ab done $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$OUT"
trap - EXIT
stop_server
