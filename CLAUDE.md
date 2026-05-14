# zmodu v0.10.0 — ZigModu Code Generator

CLI that generates complete ZigModu projects from SQL schemas. **zmodu generates everything; AI fills only ext/.**

## Build & Test

```bash
zig build                    # compile (must 0 errors)
zig build run -- <args>      # run CLI
zig build test               # test suite
```

## Architecture

```
src/main.zig          # ~4000 lines: SQL parser, CLI commands, 6 code generators
src/orm_tpl.zig       # template embedFile references
src/templates/orm/sqlx/  # templates: model/persistence/service/api/module headers
```

## Key Functions (by pipeline order)

| Function | Generates |
|----------|-----------|
| `parseSqlSchema` | TableDef[] from CREATE TABLE DDL |
| `groupTablesByModule` | Table→module grouping with prefix detection |
| `generateModuleModel` | model.zig (struct + json_names + `= null` defaults) |
| `generateModulePersistence` | persistence.zig (Repository(T) + custom queries) |
| `generateModuleService` | service.zig (CRUD + validate + EventBus) |
| `generateModuleApi` | api.zig (REST handlers + `{id}` routes + resolve) |
| `writeModuleFiles` | Writes 5 files + ext/ per module |
| `generateScaffoldMainZig` | main.zig (DB_DRIVER dispatch + module wiring) |
| `generateAgentsMd` | AGENTS.md (HARD BLOCK rules + workflow) |

## Generated Structure (target output)

```
src/
├── main.zig              # ⛔ @generated
├── shared/{types,errors,response}.zig
├── business/root.zig
└── modules/<name>/
    ├── module.zig         # ⛔ lifecycle + barrel re-exports
    ├── model.zig          # ⛔ struct(sql_table_name) + json_names
    ├── persistence.zig    # ⛔ ORM Repository(T)
    ├── service.zig        # ⛔ CRUD + validate
    ├── api.zig            # ⛔ REST handlers + {id} routes
    └── ext/               # ✅ AI writes here
        ├── service.zig
        └── api.zig
```

## Critical Rules (do not break)

1. **`= null` on optional model fields** — PK, nullable, has_default columns MUST have `= null` for Zig 0.16 `parseFromSlice`
2. **`{id}` not `:id`** — route params use curly braces (zigmodu router syntax), not colon
3. **`{{id}}` in format strings** — Zig format strings need double braces for literal `{`/`}`
4. **`RenderExt.success(ctx, "ok")`** — takes ctx as first arg
5. **5 files per module** — no root.zig (merged into module.zig)
6. **`= null` defaults** — every optional field needs `= null` literal, not just `?Type`
7. **`[:0]u8` for C interop** — PostgreSQL strings must be null-terminated
8. **`Stringify.valueAlloc` for jsonStruct** — not `std.json.fmt` (debug format)

## New Features (v0.10.0)

### --from-db: Generate from live database
```bash
zmodu scaffold --from-db "postgresql://user:pass@host:5432/db" --name <n>
zmodu scaffold --from-db "mysql://user:pass@host:3306/db" --name <n>
zmodu scaffold --from-db /path/to/db.sqlite --name <n>
# Import SQL to DB + introspect:
zmodu scaffold --sql schema.sql --from-db sqlite:///fresh.db --name <n>
```
Functions: `parseDsn`, `importSqlToDatabase`, `introspectDatabase`, `introspectDatabaseSqlite`, `introspectDatabasePostgres`, `introspectDatabaseMysql`

### Subsystem Detection
Tables like `shop_orders`, `shop_products` → subsystem `shop/` with nested modules.
Functions: `detectSubsystems` — post-processes module_map, reorganizes flat keys → `subsystem/module` format.
Imports: `const shop_orders = @import("modules/shop/orders/module.zig")`
Helper: `replaceChar(allocator, name, '/', '_')` converts path separators to var names.

### Inline FK Parsing
`extractForeignKeys` now handles inline `REFERENCES` (not just `FOREIGN KEY` syntax).

### Pluralization Fix
If PascalCase name ends in 'S' (e.g., `Users`), skip extra 's' in method names: `listUsers` not `listUserss`.

## Template Variables

```
<<MODULE_NAME>>     → module name (e.g. "users")
<<PASCAL_MODULE>>   → PascalCase (e.g. "Users")
<<DEPS>>            → dependency list from FK relationships
```

## Scaffold Arguments

```
--sql <file>        # DDL input
--name <name>       # project name
--out <dir>         # output directory (default .)
--json-style camel  # camelCase JSON field names
--with-events       # EventBus generation
--with-auth         # JWT auth generation
--with-resilience   # CircuitBreaker + RateLimiter
--with-metrics      # Prometheus /metrics
--with-transactions # SagaOrchestrator
--force             # overwrite existing
--dry-run           # preview only
```

## Common Fix Patterns

```
Problem: MissingField on POST
Fix: PK column needs ?i64 = null (not just ?i64)

Problem: route /users/:id returns 404
Fix: Use {id} not :id in route path

Problem: zig build error "too few arguments"
Fix: {id} in format string needs {{id}} escaping

Problem: PostgreSQL "invalid byte sequence"
Fix: Use allocSentinel for null-terminated SQL strings

Problem: jsonStruct returns debug format
Fix: Use Stringify.valueAlloc instead of std.json.fmt
```
