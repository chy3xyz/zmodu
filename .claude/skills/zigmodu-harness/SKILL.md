---
name: zigmodu-harness
description: Run migration verification harness — diff test old vs new backend, verify schema parity, benchmark performance. Use when validating a completed ZigModu migration against the original Java/PHP backend.
allowed-tools: Read, Write, Bash, Grep, Glob
---

# Migration Verification Harness

## Phase 4 of Migration Harness

Purpose: Validate new ZigModu backend against original Java/PHP backend with zero-trust diff testing.

## Architecture

```
Client Request ──► Reverse Proxy (harness)
                      │
            ┌─────────┴─────────┐
            ▼                   ▼
      Old Backend          New Backend
      (Java/PHP)           (ZigModu)
      :8080                :8081
            │                   │
            └─────────┬─────────┘
                      ▼
              Diff Comparator
              │  Status │ Body │ Headers │ Latency
              ▼
         Pass/Fail Report
```

## Step 1: Start Both Backends

```bash
# Start old backend
cd old-backend && ./mvnw spring-boot:run -Dserver.port=8080 &

# Start new backend
cd new-backend && HTTP_PORT=8081 zig build run &
```

## Step 2: Schema Verification

```bash
# Dump old schema
mysqldump --no-data old_db > old-schema.sql

# Dump new schema (from generated models)
zmodu schema --from src/modules/ > new-schema.sql

# Compare
diff old-schema.sql new-schema.sql > schema.diff

# Verify critical checks
grep "PRIMARY KEY\|FOREIGN KEY\|NOT NULL\|UNIQUE" schema.diff
```

Schema check rules:
- Table names: exact match or snake_case normalize
- Column types: type mapping table (VARCHAR↔[]const u8, etc.)
- Indexes: must match (especially FK indexes)
- Default values: functional equivalence

## Step 3: API Response Comparison

### Start Diff Proxy

```bash
# nginx diff proxy
cat > nginx-harness.conf << 'EOF'
server {
    listen 9000;
    location /api/ {
        # Mirror to both backends
        proxy_pass http://old_backend;
        mirror /mirror;
    }
    location = /mirror {
        internal;
        proxy_pass http://new_backend$request_uri;
    }
}
EOF
```

### Run Comparison Script

```bash
# Capture requests from prod log
cat access.log | grep "POST\|PUT\|PATCH" | head -1000 > requests.txt

# Replay against both backends, compare
zmodu verify --old http://localhost:8080 --new http://localhost:8081 \
  --replay requests.txt --output diff-report.json
```

### Diff Report Format

```json
{
  "summary": {
    "total": 1000,
    "matched": 987,
    "differed": 8,
    "errors": 5,
    "match_rate": 98.7
  },
  "differences": [
    {
      "request": "POST /api/orders",
      "old_status": 200,
      "new_status": 200,
      "field_diffs": {
        "data.timestamp": "format: ISO vs Unix",
        "data.total_price": "14.990000000000002 vs 14.99"
      }
    }
  ]
}
```

## Step 4: Response Normalization

Common differences to normalize before comparison:

```python
# normalize.py — run before diff comparison

def normalize(json_str):
    data = json.loads(json_str)

    # 1. Timestamp format: both to Unix
    if 'timestamp' in data:
        data['timestamp'] = to_unix(data['timestamp'])

    # 2. Float precision: round to 2 decimal
    for key in data:
        if isinstance(data[key], float):
            data[key] = round(data[key], 2)

    # 3. Field order: sort keys
    return json.dumps(data, sort_keys=True)

    # 4. null vs missing field: normalize to omit
    # 5. Empty array vs null: normalize to []
```

## Step 5: Performance Baseline

```bash
# Benchmark old backend
wrk -t4 -c100 -d30s http://localhost:8080/api/users > old-bench.txt

# Benchmark new backend
wrk -t4 -c100 -d30s http://localhost:8081/api/users > new-bench.txt

# Compare
zmodu verify --bench old-bench.txt new-bench.txt
```

Target metrics:
```
Metric           Old        New       Target
────────────────────────────────────────────
Latency p50      45ms       <15ms     -66%
Latency p99      200ms      <50ms     -75%
Throughput       500 rps    >2000 rps +300%
Memory           512MB      <100MB    -80%
Cold start       8s         <2s       -75%
```

## Step 6: Canary Cutover

```bash
# Gradual traffic shift
zmodu harness canary --old :8080 --new :8081 \
  --steps 1%,5%,10%,25%,50%,100% \
  --evaluate error_rate,latency_p99 \
  --rollback-on "error_rate > 1% OR latency_p99 > 2x_baseline"
```

Canary decision matrix:
```
Step   Traffic%   Error Rate   Latency p99   Decision
───────────────────────────────────────────────────
1      1%         0.0%         18ms          PROMOTE → 5%
2      5%         0.1%         22ms          PROMOTE → 10%
3      10%        0.1%         25ms          PROMOTE → 25%
4      25%        0.2%         30ms          PROMOTE → 50%
5      50%        0.3%         35ms          PROMOTE → 100%
6      100%       -            -             CUTOVER COMPLETE
```

## Step 7: Rollback Plan

If verification fails at any step:

```bash
# Instant rollback: switch DNS/proxy back to old backend
zmodu harness rollback --target old --reason "p99 latency spike at 25% canary"

# Preserve new backend for debugging
zmodu harness snapshot --backend new --output debug-snapshot/
```

## Emergency Criteria

Abort migration immediately if:
- Schema diff shows missing NOT NULL constraints
- Any finance/payment endpoint returns different amounts
- Auth endpoint accepts invalid tokens
- New backend crashes on production traffic patterns
- Memory leak detected (RSS grows unbounded)
