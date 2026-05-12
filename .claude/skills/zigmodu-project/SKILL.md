---
name: zigmodu-project
description: Navigate and understand a ZigModu project structure. Use when exploring a ZigModu codebase, understanding module conventions, or learning the project layout.
allowed-tools: Read, Bash, Grep, Glob
---

# ZigModu Project Navigation

## Project Recognition

A ZigModu project is identified by:
- `build.zig.zon` with `zigmodu` dependency
- `src/main.zig` importing `zigmodu`
- `src/modules/` directory with subdirectories per module

## Quick Orientation

```bash
# Check framework version
grep zigmodu build.zig.zon

# List all modules
ls src/modules/

# Count modules
ls src/modules/ | wc -l
```

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

Every module MUST have:
```zig
pub const info = api.Module{ .name = "x", .dependencies = &.{}, .is_internal = false };
pub fn init() !void { ... }
pub fn deinit() void { ... }
pub fn registerHealthChecks(endpoint: *zigmodu.HealthEndpoint) !void { ... }
```

## Import Conventions

```zig
// module.zig — minimal imports
const api = zigmodu.api;

// persistence.zig — data domain only
const data = @import("zigmodu").data;

// service.zig — data + EventBus
const data = zigmodu.data;

// api.zig — http domain only
const http = @import("zigmodu").http;
```

## Key Types Reference

| Type | Import Path | Usage |
|------|------------|-------|
| `Context` | `zigmodu.http.Context` | HTTP request/response |
| `Server` | `zigmodu.http.Server` | HTTP server |
| `RouteGroup` | `zigmodu.http.RouteGroup` | Route registration |
| `SqlxBackend` | `zigmodu.data.SqlxBackend` | DB backend |
| `Repository(T)` | `zigmodu.data.Repository(T)` | Typed ORM repo |
| `HealthEndpoint` | `zigmodu.HealthEndpoint` | Health checks |
| `EventBus(T)` | `zigmodu.EventBus(T)` | Typed event bus |
| `Application` | `zigmodu.Application` | App lifecycle |
| `ModuleInfo` | `zigmodu.ModuleInfo` | Module metadata |
| `CircuitBreaker` | `zigmodu.CircuitBreaker` | Fault tolerance |
| `RateLimiter` | `zigmodu.RateLimiter` | Rate limiting |
| `PrometheusMetrics` | `zigmodu.observability.PrometheusMetrics` | /metrics endpoint |

## Building and Running

```bash
zig build              # compile
zig build run          # run (reads HTTP_PORT, DB_* env vars)
zig build test         # run all tests
zig fmt src/           # format code
```

## Environment Variables

```
HTTP_PORT=8080         DB_HOST=127.0.0.1    DB_PORT=3306
DB_USER=root           DB_PASS=            DB_NAME=heysen
JWT_SECRET=changeme    # with --with-auth
```
