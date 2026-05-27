# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# zmodu v0.13.0 — ZigModu Code Generator

CLI that generates complete ZigModu projects from SQL schemas. **zmodu generates everything; AI edits generated files directly** (@initialized model, not ext/).

## Build & Test

```bash
zig build                    # compile (must 0 errors)
zig build run -- <args>      # run CLI
zig build test               # test suite (all tests in src/main.zig)
```

## Architecture

```
src/main.zig              # ~7300 lines: SQL parser, CLI (19 commands), 10+ code generators
src/orm_tpl.zig           # template embedFile references
src/templates/
  orm/sqlx/               # model/persistence/service/api/module templates (SQLx backend)
  orm/zent/               # Zent backend templates (client/schema)
  module/                 # module boilerplate
  ai_prompts/             # AI agent prompt templates
```

## Key Pipeline (scaffold command)

| Function | Generates |
|----------|-----------|
| `parseSqlSchema` | TableDef[] from CREATE TABLE DDL |
| `groupTablesByModule` | Table→module grouping with prefix detection |
| `detectSubsystems` | Nested module paths (e.g. `shop_orders` → `shop/orders`) |
| `generateModuleModel` | model.zig (struct + json_names + `= null` defaults) |
| `generateModulePersistence` | persistence.zig (Repository(T) + custom queries) |
| `generateModuleService` | service.zig (CRUD + validate + EventBus) |
| `generateModuleApi` | api.zig (REST handlers + `{id}` routes + resolve) |
| `generateModuleModule` | module.zig (lifecycle + barrel re-exports) |
| `writeModuleFiles` | Writes 5 files per module via safeWrite |
| `generateScaffoldMainZig` | main.zig (DB_DRIVER dispatch + module wiring) |
| `generateScaffoldBuildZig` | build.zig with zigmodu dependency |
| `generateAgentsMd` | AGENTS.md (HARD BLOCK rules + workflow) |

## CLI Commands

```
new, module, event, api, orm, generate, scaffold, add, migration,
health, config, test, plugin, life, upgrade, help, version
```

## Scaffold Flags

```
--sql <file>          # DDL input
--from-db <dsn>       # Introspect live database (pg/mysql/sqlite)
--name <name>         # project name (required)
--out <dir>           # output directory (default: .)
--json-style camel    # camelCase JSON field names
--force               # overwrite existing files
--dry-run             # preview only
--with-events         # EventBus generation
--with-auth           # JWT auth generation
--with-resilience     # CircuitBreaker + RateLimiter
--with-metrics        # Prometheus /metrics
--with-transactions   # SagaOrchestrator
--with-redis          # Redis cache layer
--with-websocket      # IM real-time messaging module
--with-aichat         # AI Chat (LLM provider) module
--with-agent          # AI Agent (ReAct loop + SkillRegistry) module
--with-web4           # Web4 (DID + x402) module
--with-cluster        # Cluster mode
--with-marketing      # Marketing module
```

## Generated Structure

```
src/
├── main.zig              # @initialized — AI may modify
├── shared/{types,errors,response}.zig
├── business/root.zig
└── modules/<name>/
    ├── module.zig         # lifecycle + barrel re-exports
    ├── model.zig          # struct(sql_table_name) + json_names
    ├── persistence.zig    # ORM Repository(T)
    ├── service.zig        # CRUD + validate
    └── api.zig            # REST handlers + {id} routes
```

## @initialized Model (replaced ext/)

Generated files use `//! @initialized by zmodu — AI may modify freely` header.
No `ext/` directory. AI edits generated files directly.

**safeWrite**: file exists → writes to `path.gen.new` (never overwrites user code).
Use `--force` to overwrite.

## Critical Rules

1. **`= null` on optional model fields** — PK, nullable, has_default columns MUST have `= null` for Zig 0.16 `parseFromSlice`
2. **`{id}` not `:id`** — route params use curly braces (zigmodu router syntax)
3. **`{{id}}` in format strings** — Zig format strings need double braces for literal `{`/`}`
4. **5 files per module** — model, persistence, service, api, module (root.zig merged into module.zig)
5. **`[:0]u8` for C interop** — PostgreSQL strings must be null-terminated
6. **`Stringify.valueAlloc` for jsonStruct** — not `std.json.fmt` (debug format)
7. **Pluralization**: PascalCase ending in 'S' (e.g. `Users`) skips extra 's' → `listUsers` not `listUserss`

## Database Introspection (`--from-db`)

```bash
zmodu scaffold --from-db "postgresql://user:pass@host:5432/db" --name <n>
zmodu scaffold --from-db "mysql://user:pass@host:3306/db" --name <n>
zmodu scaffold --from-db /path/to/db.sqlite --name <n>
zmodu scaffold --sql schema.sql --from-db sqlite:///fresh.db --name <n>
```

Functions: `parseDsn`, `importSqlToDatabase`, `introspectDatabase`, `introspectDatabasePostgres`, `introspectDatabaseMysql`, `introspectDatabaseSqlite`

## Subsystem Detection

Tables like `shop_orders`, `shop_products` → subsystem `shop/` with nested modules.
Imports: `const shop_orders = @import("modules/shop/orders/module.zig")`
Helper: `replaceChar(allocator, name, '/', '_')` for var names.

## Common Fix Patterns

```
Problem: MissingField on POST
Fix:     PK column needs ?i64 = null (not just ?i64)

Problem: route /users/:id returns 404
Fix:     Use {id} not :id in route path

Problem: zig build error "too few arguments"
Fix:     {id} in format string needs {{id}} escaping

Problem: PostgreSQL "invalid byte sequence"
Fix:     Use allocSentinel for null-terminated SQL strings

Problem: jsonStruct returns debug format
Fix:     Use Stringify.valueAlloc instead of std.json.fmt
```

## Zig 0.16 Patterns (applies to zmodu itself)

- **ArrayList**: `.empty` only, all mutations need explicit `allocator` param
- **Stream.Writer**: `w.interface.writeAll(data)` not `w.writeAll(data)`
- **std.time**: No functions — use zigmodu `Time.monotonicNowSeconds()`
- **Environ**: `std.process.Environ.empty`, instance method `createMap(gpa)`
- **HashMap StringContext**: zero-sized → `init(alloc)` works
