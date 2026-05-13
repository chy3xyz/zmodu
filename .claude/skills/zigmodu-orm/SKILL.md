---
name: zigmodu-orm
description: Generate ZigModu ORM modules from SQL schema. This is the machine-generation step — zmodu produces 100% of model/persistence/service/api/module/root. AI only extends via _ext files.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Generate ORM from SQL — Machine Generation Step

## Principle: zmodu generates everything, AI never edits generated files.

Generated files (DO NOT EDIT):
```
model.zig · persistence.zig · service.zig · api.zig · module.zig · root.zig
```

AI extension files (safe to edit):
```
service_ext.zig · api_ext.zig · src/business/ · tests/
```

## Commands

```bash
# Full project from SQL (all 3 modes use this)
zmodu scaffold --sql schema.sql --name <project> \
  --with-events --with-resilience --with-metrics --with-auth

# ORM only (modules under existing project)
zmodu orm --sql schema.sql --out src/modules

# Regenerate after schema change
zmodu orm --sql schema.sql --out src/modules --force
```

## After Generation

```bash
# 1. Verify compilation
zig build                    # must be 0 errors

# 2. Identify AI work needed
#    - JOIN queries across tables → service_ext.zig
#    - Business rules/validation → service_ext.zig
#    - Custom endpoints → api_ext.zig
#    - Transaction orchestration → src/business/

# 3. Never edit generated files
#    They get overwritten on --force regeneration
```

## SQL Type → Zig Type

| SQL | Zig |
|-----|-----|
| INT/BIGINT/SERIAL | `i64` |
| VARCHAR/TEXT/JSON | `[]const u8` |
| BOOLEAN | `bool` |
| FLOAT/DOUBLE/DECIMAL | `f64` |
| DATETIME/TIMESTAMP | `[]const u8` |

## Auto-Grouping

Tables with common prefix → single module. Prefix stripped from names.
`zmodu_order` → module `order`, model `Order`, route `/orders`

## FOREIGN KEY → Dependency

`FOREIGN KEY (user_id) REFERENCES user(id)` → module depends on "user"
