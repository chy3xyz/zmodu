---
name: zigmodu-module
description: Create a new ZigModu module. Use when adding a domain module, CRUD resource, or business logic unit.
---

# Create a ZigModu Module

## Quick Start
```bash
zmodu module <name>          # CLI scaffold
zmodu orm --sql s.sql --out src/modules  # from SQL
```

## Manual Creation Checklist
1. `mkdir -p src/modules/<name>`
2. Create 6 files: module.zig, model.zig, persistence.zig, service.zig, api.zig, root.zig
3. Wire into `src/main.zig`:
   - Import: `const <name> = @import("modules/<name>/root.zig");`
   - Init: `var x_p = <name>.persistence.XPersistence.init(backend);`
   - Routes: `try <name>_api.registerRoutes(&root);`
   - Lifecycle: `.build(.{ ..., <name>.module, ... })`

## Model Rules
- `sql_table_name` const maps to database table
- NOT NULL → non-optional, nullable → `?Type`
- Primary key: `id: i64` (auto-detected by ORM)
- VARCHAR/TEXT → `[]const u8`, INT → `i64`, FLOAT → `f64`
- No hand-written jsonStringify needed

## Service Pattern
```zig
pub fn listThings(self: *S, page: usize, size: usize) !data.orm.PageResult(model.Thing) {
    var repo = self.persistence.thingRepo();
    return try repo.findPage(page, size);
}
```

## Zig Keywords → _mod suffix
return → return_mod, error → error_mod, test → test_mod, app → app_mod
