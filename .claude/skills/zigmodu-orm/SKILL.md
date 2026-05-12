---
name: zigmodu-orm
description: Generate ZigModu ORM modules from SQL schema. Use when creating persistence layers, generating CRUD code from CREATE TABLE statements, or scaffolding modules from existing database schemas.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Generate ORM Modules from SQL

## CLI: Generate from SQL file

```bash
# Auto-group tables into modules by prefix detection
zmodu orm --sql schema.sql --out src/modules

# Force all tables into a single module
zmodu orm --sql schema.sql --out src/modules --module orders

# Preview without writing files
zmodu orm --sql schema.sql --out src/modules --dry-run

# Overwrite existing files
zmodu orm --sql schema.sql --out src/modules --force

# Data-only (model.zig + persistence.zig only, no service/api/module)
zmodu orm --sql schema.sql --out src/modules --data-only

# Zent backend (alternative to default sqlx)
zmodu orm --sql schema.sql --out src/modules --backend zent
```

## CLI: Full project scaffold

```bash
# One-shot: SQL → full project with all wiring
zmodu scaffold --sql schema.sql --name myapp --out ./myproject

# With capability flags
zmodu scaffold --sql schema.sql --name myapp \
  --with-events \
  --with-resilience \
  --with-cluster \
  --with-metrics \
  --with-auth \
  --force

# Regenerate the reference shopdemo (152 tables → 42 modules)
zmodu bigdemo
```

## SQL Parser: Supported CREATE TABLE Syntax

The parser recognizes:
```sql
CREATE TABLE order (
    id BIGINT PRIMARY KEY,
    order_no VARCHAR(64) NOT NULL,
    total_price DECIMAL(10,2),
    buyer_remark TEXT,
    is_paid BOOLEAN DEFAULT false,
    created_at DATETIME,
    FOREIGN KEY (user_id) REFERENCES user(id),
    UNIQUE (order_no)
);
```

### Type mapping

| SQL Type | Zig Type |
|----------|----------|
| INT, BIGINT, SMALLINT, TINYINT, SERIAL | `i64` |
| VARCHAR, TEXT, CHAR, JSON, JSONB, UUID | `[]const u8` |
| BOOLEAN, BOOL | `bool` |
| FLOAT, DOUBLE, REAL, NUMERIC, DECIMAL | `f64` |
| DATETIME, TIMESTAMP, DATE, TIME | `[]const u8` |
| Unknown types | `[]const u8` |

### Constraints → field modifiers

- `PRIMARY KEY` → field becomes non-nullable
- `NOT NULL` → non-optional `T`
- `UNIQUE` → `is_unique: true`
- `DEFAULT` → `has_default: true`
- No NOT NULL → optional `?T`

## Auto-Grouping Logic

When `--module` is not specified, tables are grouped by common prefix:

```sql
-- These 3 tables:
CREATE TABLE order_header (...);
CREATE TABLE order_line (...);
CREATE TABLE order_payment (...);
-- → Single module: src/modules/order/
--   Prefix "order_" auto-detected and stripped from model names
```

## Generated Output (6 files per module)

```
src/modules/<name>/
├── module.zig      # api.Module + init/deinit + registerHealthChecks
├── model.zig       # Struct per table with sql_table_name
├── persistence.zig # XRepo() accessors → data.Repository(T)
├── service.zig     # CRUD delegation + EventBus(T) + publish()
├── api.zig         # registerRoutes() + resolve() + handlers
└── root.zig        # Barrel re-exports
```

## Model Naming

Common table prefix is stripped from generated names:
```
zmodu_order → module: order     model: Order     route: /orders
zmodu_user  → module: user      model: User      route: /users
```

## Dependency Inference

FOREIGN KEY references are automatically converted to module dependencies:
```sql
CREATE TABLE order (..., FOREIGN KEY (user_id) REFERENCES user(id));
-- → module "order" depends on module "user"
-- → info.dependencies = &.{"user"}
```

Tables without FOREIGN KEY declarations will have empty dependencies.

## Manual Refinement After Generation

After `zmodu orm`, refine the generated code:

1. **module.zig**: set `is_internal = true` for non-public modules
2. **service.zig**: add business logic methods after generated CRUD
3. **model.zig**: adjust field types if needed (e.g., `i64` → `u64` for unsigned IDs)
4. **api.zig**: add custom endpoints beyond CRUD
5. Create `service_ext.zig` for logic that survives regeneration

## Best Practices

- Keep SQL schema as the source of truth — regenerate after schema changes
- Put custom business logic in `service_ext.zig` (not overwritten by regeneration)
- Put custom API endpoints in `api_ext.zig` (not overwritten by regeneration)
- Use `--dry-run` first to preview changes
- Use `--force` to overwrite generated files safely
- Run `zig build test` after each regeneration
