---
name: zigmodu-module
description: Create a new ZigModu module with best-practice structure. Use when adding a new domain module, CRUD resource, or business logic unit to a ZigModu project.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Create a ZigModu Module

## Quick Start

To generate a module from SQL:
```bash
zmodu orm --sql schema.sql --out src/modules
```

To manually create a module with the CLI:
```bash
zmodu module <name>
```

## Manual Module Creation

When creating a module by hand, follow this checklist:

### 1. Create the directory
```bash
mkdir -p src/modules/<name>
```

### 2. module.zig — Declaration + Lifecycle
```zig
const std = @import("std");
const zigmodu = @import("zigmodu");
const api = zigmodu.api;

pub const info = api.Module{
    .name = "<name>",
    .description = "<name> module",
    .dependencies = &.{},  // add dependency module names here
    .is_internal = false,
};

pub fn init() !void {
    std.log.info("[{s}] initializing", .{info.name});
}

pub fn deinit() void {
    std.log.info("[{s}] shutting down", .{info.name});
}

pub fn registerHealthChecks(endpoint: *zigmodu.HealthEndpoint) !void {
    try endpoint.registerCheck("<name>", "<name> module health",
        zigmodu.HealthEndpoint.alwaysUp);
}
```

### 3. model.zig — Data Structures
```zig
const std = @import("std");

pub const Thing = struct {
    pub const sql_table_name: []const u8 = "thing";
    id: i64,
    name: []const u8,
    created_at: i64,
};
```

Rules for model fields:
- Use `sql_table_name` const for ORM table mapping
- `NOT NULL` columns → non-optional types
- Nullable columns → `?Type`
- Primary key named `id: i64` for ORM auto-detection
- Use `[]const u8` for VARCHAR/TEXT, `i64` for INT/BIGINT, `f64` for FLOAT/DECIMAL
- No hand-written `jsonStringify` — `ctx.jsonStruct()` handles serialization

### 4. persistence.zig — ORM Repository
```zig
const std = @import("std");
const data = @import("zigmodu").data;
const model = @import("model.zig");

pub const ThingPersistence = struct {
    backend: data.SqlxBackend,
    orm: data.orm.Orm(data.SqlxBackend),

    pub fn init(backend: data.SqlxBackend) ThingPersistence {
        return .{ .backend = backend, .orm = .{ .backend = backend } };
    }

    pub fn thingRepo(self: *ThingPersistence) data.Repository(model.Thing) {
        return .{ .orm = &self.orm };
    }
};
```

### 5. service.zig — Business Logic
```zig
const std = @import("std");
const zigmodu = @import("zigmodu");
const data = zigmodu.data;
const model = @import("model.zig");
const persistence = @import("persistence.zig");

pub const ThingEvent = union(enum) {
    thing_created: struct { id: i64 },
};

pub const ThingService = struct {
    persistence: *persistence.ThingPersistence,
    event_bus: ?*zigmodu.EventBus(ThingEvent) = null,

    pub fn init(p: *persistence.ThingPersistence) ThingService {
        return .{ .persistence = p };
    }

    pub fn withEvents(self: *ThingService, bus: *zigmodu.EventBus(ThingEvent)) void {
        self.event_bus = bus;
    }

    pub fn publish(self: *ThingService, event: ThingEvent) void {
        if (self.event_bus) |bus| bus.publish(event);
    }

    pub fn listThings(self: *ThingService, page: usize, size: usize) !data.orm.PageResult(model.Thing) {
        var repo = self.persistence.thingRepo();
        return try repo.findPage(page, size);
    }

    pub fn getThing(self: *ThingService, id: i64) !?model.Thing {
        var repo = self.persistence.thingRepo();
        return try repo.findById(id);
    }

    pub fn createThing(self: *ThingService, entity: model.Thing) !model.Thing {
        var repo = self.persistence.thingRepo();
        const result = try repo.insert(entity);
        self.publish(.{ .thing_created = .{ .id = result.id } });
        return result;
    }

    pub fn updateThing(self: *ThingService, entity: model.Thing) !void {
        var repo = self.persistence.thingRepo();
        return try repo.update(entity);
    }

    pub fn deleteThing(self: *ThingService, id: i64) !void {
        var repo = self.persistence.thingRepo();
        return try repo.delete(id);
    }
};
```

### 6. api.zig — REST Handlers
```zig
const std = @import("std");
const http = @import("zigmodu").http;
const service = @import("service.zig");
const model = @import("model.zig");

pub const ThingApi = struct {
    service: *service.ThingService,

    pub fn init(svc: *service.ThingService) ThingApi {
        return .{ .service = svc };
    }

    fn resolve(ctx: *http.Context) *ThingApi {
        return @ptrCast(@alignCast(ctx.user_data orelse unreachable));
    }

    pub fn registerRoutes(self: *ThingApi, group: *http.RouteGroup) !void {
        try group.get("/things", listThings, @ptrCast(@alignCast(self)));
        try group.get("/things/:id", getThing, @ptrCast(@alignCast(self)));
        try group.post("/things", createThing, @ptrCast(@alignCast(self)));
        try group.put("/things/:id", updateThing, @ptrCast(@alignCast(self)));
        try group.delete("/things/:id", deleteThing, @ptrCast(@alignCast(self)));
    }

    fn listThings(ctx: *http.Context) !void {
        const s = resolve(ctx);
        const page = std.fmt.parseInt(usize, ctx.query.get("page") orelse "0", 10) catch 0;
        const size = std.fmt.parseInt(usize, ctx.query.get("size") orelse "10", 10) catch 10;
        const result = try s.service.listThings(page, size);
        try ctx.jsonStruct(200, result);
    }

    fn getThing(ctx: *http.Context) !void {
        const s = resolve(ctx);
        const id = std.fmt.parseInt(i64, ctx.params.get("id") orelse return error.BadRequest, 10) catch return error.BadRequest;
        if (try s.service.getThing(id)) |entity| {
            try ctx.jsonStruct(200, entity);
        } else { try ctx.json(404, "{\"error\":\"not found\"}"); }
    }

    fn createThing(ctx: *http.Context) !void {
        const s = resolve(ctx);
        const entity = ctx.bindJson(model.Thing) catch {
            try ctx.json(400, "{\"error\":\"invalid body\"}");
            return;
        };
        const created = try s.service.createThing(entity);
        try ctx.jsonStruct(201, created);
    }

    fn updateThing(ctx: *http.Context) !void {
        const s = resolve(ctx);
        const entity = ctx.bindJson(model.Thing) catch {
            try ctx.json(400, "{\"error\":\"invalid body\"}");
            return;
        };
        try s.service.updateThing(entity);
        try ctx.json(200, "{\"ok\":true}");
    }

    fn deleteThing(ctx: *http.Context) !void {
        const s = resolve(ctx);
        const id = std.fmt.parseInt(i64, ctx.params.get("id") orelse return error.BadRequest, 10) catch return error.BadRequest;
        try s.service.deleteThing(id);
        try ctx.json(204, "");
    }
};
```

### 7. root.zig — Barrel Exports
```zig
pub const model = @import("model.zig");
pub const persistence = @import("persistence.zig");
pub const service = @import("service.zig");
pub const api = @import("api.zig");
pub const module = @import("module.zig");
```

## Wiring into main.zig

After creating the module files, wire them into `src/main.zig`:

```zig
// 1. Import at top
const thing = @import("modules/thing/root.zig");

// 2. Add persistence (after other *_p inits)
var thing_p = thing.persistence.ThingPersistence.init(backend);

// 3. Add service (after other *_svc inits)
var thing_svc = thing.service.ThingService.init(&thing_p);

// 4. Add API (after other *_api inits)
var thing_api = thing.api.ThingApi.init(&thing_svc);

// 5. Register routes (after other registerRoutes calls)
try thing_api.registerRoutes(&root);

// 6. Add to Application (in .build() tuple)
.build(.{ ..., thing.module, ... })
```

## Zig Reserved Words

If the module name is a Zig keyword, use `_mod` suffix:
- `return` → `return_mod`
- `error` → `error_mod`
- `test` → `test_mod`
- `app` → `app_mod`

The code generator handles this automatically. When wiring manually, check `grep "const.*_mod" src/main.zig` for existing patterns.
