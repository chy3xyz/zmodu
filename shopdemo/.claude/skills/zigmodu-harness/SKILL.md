---
name: zigmodu-harness
description: Run migration verification — diff test old vs new, verify schema, benchmark. Use when validating ZigModu migration.
---

# Migration Verification Harness

## Phase 4 of Migration Harness

## Diff Proxy Architecture
```
Client → Reverse Proxy → Old Backend (:8080)
                   └→ New Backend (:8081) [mirror]
                        │
                   Diff Comparator → Pass/Fail Report
```

## Quick Start
```bash
zmodu verify --old http://localhost:8080 --new http://localhost:8081
```

## Verification Steps
1. Start both backends
2. Dump + diff schemas (`mysqldump --no-data`)
3. Replay production requests, compare responses
4. Normalize: timestamps, float precision, field order
5. Benchmark: `wrk -t4 -c100 -d30s` both endpoints
6. Canary: 1%%→5%%→10%%→25%%→50%%→100%% cutover

## Abort Criteria
- Schema diff shows missing NOT NULL
- Payment endpoint returns different amounts
- Auth accepts invalid tokens
- Memory leak (RSS grows unbounded)
