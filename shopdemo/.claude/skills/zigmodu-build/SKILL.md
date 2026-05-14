---
name: zigmodu-build
description: Build complete ZigModu backend — greenfield/SQL/migration. zmodu generates all possible code, AI fills only gaps. Always start here.
---

# ZigModu Build — First Principle

**zmodu generates everything possible. AI only writes what zmodu cannot.**

## Mode Selection
```
Have SQL schema? → Mode 2 (Brownfield)
Have reference project (Java/PHP/Go/Rust)? → Mode 3 (Migration)
Neither? → Mode 1 (Greenfield)
```

## Mode 1: Greenfield (from requirements)
```bash
# 1. Design schema → schema.sql (AI assists)
# 2. zmodu generates full project
zmodu scaffold --sql schema.sql --name <project> --with-events --with-resilience --with-metrics
# 3. Verify: zig build (must be 0 errors)
# 4. AI fills: service_ext.zig + api_ext.zig only. Never edit generated files.
```

## Mode 2: Brownfield (from SQL)
```bash
# 1. Verify SQL: grep "CREATE TABLE\|FOREIGN KEY" schema.sql
# 2. zmodu generates full project
zmodu scaffold --sql schema.sql --name <project> --with-events --with-auth
# 3. Verify: zig build
# 4. AI adds: JOIN queries, business rules, auth logic
```

## Mode 3: Migration (from Java/PHP/Go/Rust)
```bash
# 1. Analyze source → extract SQL + routes
# 2. zmodu generates from extracted SQL
zmodu scaffold --sql schema.sql --name <project>
# 3. AI translates: service logic diff, custom endpoints
# 4. Verify: zmodu verify --old :8080 --new :8081
```

## AI Edit Rules
### Safe to edit (survives regeneration):
`service_ext.zig` `api_ext.zig` `src/business/` `src/compat/` `tests/`
### NEVER edit (overwritten on regeneration):
`model.zig` `persistence.zig` `service.zig` `api.zig` `module.zig` `root.zig` `main.zig` `build.zig`

## Verify after every change
```bash
zig build && zig build test
```
