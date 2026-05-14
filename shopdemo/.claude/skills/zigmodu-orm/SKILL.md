---
name: zigmodu-orm
description: Generate ORM modules from SQL schema. Use when creating persistence layers or scaffolding from CREATE TABLE statements.
---

# Generate ORM from SQL

## Commands
```bash
zmodu orm --sql schema.sql --out src/modules           # auto-group
zmodu orm --sql s.sql --module name --force            # single module
zmodu scaffold --sql s.sql --name app --with-metrics   # full project
zmodu bigdemo                                          # reference shopdemo
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
Tables with common prefix (e.g. `order_`) → single module.
Prefix is stripped from model names and route paths.

## FOREIGN KEY → Dependency
`FOREIGN KEY (user_id) REFERENCES user(id)` → module depends on "user"

## Regeneration Safety
Custom logic in `service_ext.zig` and `api_ext.zig` survives regeneration.
Use `--force` to overwrite, `--dry-run` to preview.
