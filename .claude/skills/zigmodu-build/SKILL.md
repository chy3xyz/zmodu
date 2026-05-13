---
name: zigmodu-build
description: Build ZigModu backend. 3 modes: greenfield/SQL/migration. zmodu generates everything possible. AI fills only _ext files. Always start here. Choose mode by input type.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# ZigModu Build — AI Contract

## Input → Mode Selection

```
Input is SQL file?
  → Mode 2: Brownfield
Input is existing project directory (Java/PHP/Go/Rust)?
  → Mode 3: Migration — invoke zigmodu-analyze first
Input is requirements description (text)?
  → Mode 1: Greenfield
```

## Mode 1: Greenfield (requirements → project)

```
INPUT:  requirements description (text)
OUTPUT: compilable ZigModu project

Pipeline:
  1. AI reads requirements → designs schema.sql
  2. zmodu scaffold --sql schema.sql --name <name> --with-events --with-resilience --with-metrics
  3. zig build (MUST be 0 errors)
  4. AI reviews generated code → identifies gaps
  5. AI writes service_ext.zig only (business rules)
  6. zig build test (MUST all pass)

AI output per step:
  Step 1 → schema.sql (DDL)
  Step 2 → generated project (zmodu output)
  Step 3 → "zig build: 0 errors" or "zig build: N errors (list them)"
  Step 4 → gap list: "N methods need business logic, M endpoints need custom handlers"
  Step 5 → service_ext.zig + api_ext.zig
  Step 6 → "zig build test: all pass"
```

## Mode 2: Brownfield (SQL → project)

```
INPUT:  schema.sql
OUTPUT: compilable ZigModu project with AI extensions

Pipeline:
  1. Verify SQL: grep "CREATE TABLE" schema.sql → N tables
  2. zmodu scaffold --sql schema.sql --name <name> --with-events --with-metrics --with-auth
  3. zig build (MUST be 0 errors)
  4. AI identifies gaps:
     - Tables with FK → need cross-module JOIN queries
     - Tables with status fields → need state machine logic
     - Tables with auth-related fields → need permission checks
  5. AI writes service_ext.zig per module (business logic)
  6. AI writes api_ext.zig per module (custom endpoints)
  7. zig build test

AI output per step:
  Step 1 → "schema.sql: N tables, M FK relationships, X modules inferred"
  Step 2 → generated project path
  Step 3 → "zig build: 0 errors" or error list
  Step 4 → gap analysis: module-by-module
  Step 5 → files created: service_ext.zig list
  Step 6 → files created: api_ext.zig list  
  Step 7 → "zig build test: all pass"
```

## Mode 3: Migration (Java/PHP/Go/Rust → project)

```
INPUT:  path/to/legacy-project
OUTPUT: compilable ZigModu project with compatibility layer

Pipeline:
  1. Invoke zigmodu-analyze → analysis/{schema.sql, routes.json, module-map.json}
     If BLOCKED at any step → report missing, stop, ask user.
  2. zmodu scaffold --sql analysis/schema.sql --name <name>
  3. zig build (MUST be 0 errors)
  4. AI compares analysis/routes.json with generated api.zig:
     - Routes present in source but not generated → api_ext.zig
     - Routes with different path → compat layer
  5. Invoke zigmodu-translate for each source service file:
     - Input: Java/PHP/Go/Rust service file
     - Output: service_ext.zig with [AUTO]/[REVIEW]/[MANUAL] tags
  6. zig build test
  7. (Optional) Invoke zigmodu-harness for diff verification

AI output per step:
  Step 1 → "analysis complete: N tables, M routes, X modules. Missing: (list or none)"
  Step 2 → generated project path
  Step 3 → "zig build: 0 errors"
  Step 4 → route diff report: "N matched, M new endpoints in api_ext.zig"
  Step 5 → translate report: "X files, Y [AUTO], Z [REVIEW], W [MANUAL]"
  Step 6 → "zig build test: all pass"
```

## AI Edit Rules (All Modes)

### Safe (never overwritten)
```
src/modules/<name>/service_ext.zig
src/modules/<name>/api_ext.zig
src/business/
src/compat/
tests/
```

### NEVER EDIT (overwritten on --force regeneration)
```
model.zig  persistence.zig  service.zig  api.zig
module.zig  root.zig  main.zig  build.zig  build.zig.zon
```

## Verify After Every Change

```bash
zig build          # 0 errors or STOP
zig build test     # all pass or FIX
```

## Blocking Rules (AI MUST stop and report)

```
BLOCKED if:
  - schema.sql empty after analysis → "Need DB credentials or migration files"
  - zig build has errors → "Fix compilation before proceeding"
  - zmodu not installed → "Install: cd zmodu && zig build"
  - zigmodu framework has compile errors → "Framework issue, not migration issue"
```
