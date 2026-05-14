---
name: zigmodu-api
description: Add REST API endpoints to a ZigModu module. Use when adding routes, custom handlers, or middleware.
---

# Add REST API Endpoints

## Route Registration
```zig
// In api.zig registerRoutes():
try group.get("/things/custom", handler, @ptrCast(@alignCast(self)));
try group.post("/things", createHandler, @ptrCast(@alignCast(self)));
```

## Handler Pattern
```zig
fn handler(ctx: *http.Context) !void {
    const s = resolve(ctx);
    // read: ctx.params.get("id"), ctx.query.get("key"), ctx.bindJson(T)
    // write: ctx.json(code, str), ctx.jsonStruct(code, value)
}
```

## Standard REST Routes
| Method | Path | Handler |
|--------|------|---------|
| GET | /things | list (paginated) |
| GET | /things/:id | get by id |
| POST | /things | create |
| PUT | /things/:id | update |
| DELETE | /things/:id | delete |

## Error Handling
- bindJson errors → `ctx.json(400, "{\\"error\\":\\"invalid body\\"}")`
- Not found → `ctx.json(404, "{\\"error\\":\\"not found\\"}")`
- Path param parse failure → `return error.BadRequest`
