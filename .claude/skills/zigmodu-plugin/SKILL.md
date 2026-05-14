---
name: zigmodu-plugin
description: Generate stub plugins for missing Zig dependencies during migration. Creates compilable placeholder modules with error.NotImplemented markers. AI fills implementation later.
allowed-tools: Read, Write, Bash, Grep, Glob
---

# Plugin Stub System — Migration Gap Filler

## Principle

When migrating Java/PHP/Go projects, some dependencies have no Zig equivalent.
Don't block migration. Generate a stub that compiles, mark it, move on.
AI fills real implementation later.

## Stub Convention

```zig
// src/plugins/<name>/stub.zig
// Priority: P0|P1|P2  (P0 = core business, P1 = important, P2 = nice-to-have)
// Source: <original Java/PHP dependency>
// Status: STUB (compiles, returns error.NotImplemented)

pub const <Name>Plugin = struct {
    pub fn <method>(...) !<return_type> {
        _ = ...;
        return error.NotImplemented; // STUB
    }
};
```

## Priority Mapping

```
P0 (blocks business):    payment gateway, SMS, push notifications, auth
P1 (blocks features):    file storage, search, reports, scheduled tasks
P2 (nice to have):       log aggregation, config center, feature flags
```

## Usage

```bash
zmodu plugin stub --name wechat-pay --methods "createOrder,queryOrder,refund" --priority P0
zmodu plugin generate --analysis analysis.json
zmodu plugin list                        # list all stubs
zmodu plugin done --name wechat-pay      # mark as implemented
```

## Plugin Structure

```
src/plugins/wechat-pay/
├── stub.zig          # Interface + error.NotImplemented
├── README.md         # Original dependency info + implementation notes
└── PRIORITY          # P0|P1|P2 file
```

## Service Integration

```zig
// ext/service.zig — using a plugin stub
const wechat = @import("../../plugins/wechat-pay/stub.zig");

pub fn processPayment(self: *PaymentServiceExt, order: model.Order) !void {
    const req = wechat.WechatPayPlugin.CreateOrderRequest{ ... };
    const resp = wechat.WechatPayPlugin.createOrder(req) catch |err| switch (err) {
        error.NotImplemented => {
            std.log.warn("stub: payment not processed for order {d}", .{order.id});
            return error.PaymentUnavailable;
        },
        else => return err,
    };
    _ = resp;
}
```

## AI Implementation Workflow

```
1. zmodu plugin list → see all stubs sorted by priority
2. Pick highest P0 stub
3. Read stub.zig → understand interface
4. Implement real logic (HTTP call, native lib, etc.)
5. zmodu plugin done --name wechat-pay
6. zig build test → verify
```
