---
name: zigmodu-api
description: Add REST API endpoints to a ZigModu module. Use when adding new routes, custom handlers, middleware, or extending an existing module's HTTP surface.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Add REST API Endpoints

## Quick Start — Inline Handler

To add a single endpoint to an existing module, append to its `api.zig`:

### Step 1: Register the route

Add inside `registerRoutes()`:
```zig
try group.get("/things/custom", customHandler, @ptrCast(@alignCast(self)));
```

### Step 2: Write the handler

Add inside the `ThingApi` struct:
```zig
fn customHandler(ctx: *http.Context) !void {
    const s = resolve(ctx);
    // Read params
    const filter = ctx.query.get("filter") orelse "";
    // Call service
    const result = try s.service.customQuery(filter);
    // Respond
    try ctx.jsonStruct(200, result);
}
```

## Handler Patterns

### GET with path param
```zig
fn getById(ctx: *http.Context) !void {
    const s = resolve(ctx);
    const id = std.fmt.parseInt(i64, ctx.params.get("id") orelse return error.BadRequest, 10)
        catch return error.BadRequest;
    if (try s.service.getThing(id)) |entity| {
        try ctx.jsonStruct(200, entity);
    } else {
        try ctx.json(404, "{\"error\":\"not found\"}");
    }
}
```

### GET with query params (list/paginate)
```zig
fn list(ctx: *http.Context) !void {
    const s = resolve(ctx);
    const page = std.fmt.parseInt(usize, ctx.query.get("page") orelse "0", 10) catch 0;
    const size = std.fmt.parseInt(usize, ctx.query.get("size") orelse "10", 10) catch 10;
    const result = try s.service.listThings(page, size);
    try ctx.jsonStruct(200, result);
}
```

### POST with JSON body
```zig
fn create(ctx: *http.Context) !void {
    const s = resolve(ctx);
    const entity = ctx.bindJson(model.Thing) catch {
        try ctx.json(400, "{\"error\":\"invalid body\"}");
        return;
    };
    const created = try s.service.createThing(entity);
    try ctx.jsonStruct(201, created);
}
```

### PUT with path param + body
```zig
fn update(ctx: *http.Context) !void {
    const s = resolve(ctx);
    const id = std.fmt.parseInt(i64, ctx.params.get("id") orelse return error.BadRequest, 10)
        catch return error.BadRequest;
    const entity = ctx.bindJson(model.Thing) catch {
        try ctx.json(400, "{\"error\":\"invalid body\"}");
        return;
    };
    entity.id = id;  // Ensure ID matches path
    try s.service.updateThing(entity);
    try ctx.json(200, "{\"ok\":true}");
}
```

### DELETE with path param
```zig
fn delete(ctx: *http.Context) !void {
    const s = resolve(ctx);
    const id = std.fmt.parseInt(i64, ctx.params.get("id") orelse return error.BadRequest, 10)
        catch return error.BadRequest;
    try s.service.deleteThing(id);
    try ctx.json(204, "");
}
```

## Available Route Methods

```zig
group.get(path, handler, user_data)
group.post(path, handler, user_data)
group.put(path, handler, user_data)
group.delete(path, handler, user_data)
group.patch(path, handler, user_data)
group.head(path, handler, user_data)
group.options(path, handler, user_data)
```

## Context Methods Reference

```zig
// Reading request
ctx.params.get("id")          → ?[]const u8   // path param
ctx.query.get("page")         → ?[]const u8   // query string
ctx.headers.get("Authorization") → ?[]const u8
ctx.body                      → ?[]const u8   // raw body

// Writing response
ctx.json(status, json_string)        // raw JSON string
ctx.jsonStruct(status, value)        // serialize any Zig type
ctx.text(status, text)               // plain text

// JSON binding
ctx.bindJson(T)                      // parse body into type T
```

## Route Path Conventions

```
GET    /things              → list
GET    /things/:id          → get by id
POST   /things              → create
PUT    /things/:id          → update
DELETE /things/:id          → delete

GET    /things/search       → custom search
POST   /things/:id/approve  → custom action
```

Use lowercase plural nouns. Separate words with underscores if needed. Use `:id` for path parameters.

## Error Response Pattern

```zig
// Always catch bindJson errors and return 400
const entity = ctx.bindJson(model.Thing) catch {
    try ctx.json(400, "{\"error\":\"invalid body\"}");
    return;
};

// Always validate path params
const id = std.fmt.parseInt(i64, ctx.params.get("id") orelse return error.BadRequest, 10)
    catch return error.BadRequest;

// NotFound → 404
if (entity == null) {
    try ctx.json(404, "{\"error\":\"not found\"}");
    return;
}
```
