---
name: zigmodu-project
description: Navigate and understand a ZigModu project. Use when exploring the codebase, understanding module conventions, or learning the project layout.
---

# ZigModu Project Navigation

## Module Structure (6 files per module)
```
src/modules/<name>/
├── module.zig      # info + init/deinit + registerHealthChecks
├── model.zig       # data structs (sql_table_name + fields)
├── persistence.zig # ORM repositories → data.Repository(T)
├── service.zig     # business logic + EventBus(T) + CRUD
├── api.zig         # REST routes + resolve(ctx) helper
└── root.zig        # barrel re-exports
```

## Module Contract
```zig
pub const info = api.Module{ .name = "x", .dependencies = &.{}, .is_internal = false };
pub fn init() !void { ... }
pub fn deinit() void { ... }
pub fn registerHealthChecks(endpoint: *zigmodu.HealthEndpoint) !void { ... }
```

## Import Conventions
- module.zig → `const api = zigmodu.api;`
- persistence.zig → `const data = @import("zigmodu").data;`
- service.zig → `const data = zigmodu.data;`
- api.zig → `const http = @import("zigmodu").http;`

## Building
```bash
zig build              # compile
zig build run          # run (reads HTTP_PORT, DB_* env vars)
zig build test         # run all tests
```
