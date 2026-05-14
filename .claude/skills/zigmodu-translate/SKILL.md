---
name: zigmodu-translate
description: Translate Java/PHP/Go/Rust logic to ZigModu. Input: source file path. Output: ext/service.zig or ext/api.zig with [AUTO]/[REVIEW]/[MANUAL] tags. Never edits generated files.
allowed-tools: Read, Write, Bash, Grep, Glob
---

# Translate Business Logic → ZigModu ext/ Files

## AI Contract

**Input**: path to Java/PHP/Go/Rust source file
**Output**: `src/modules/<name>/ext/service.zig` or `src/modules/<name>/ext/api.zig`
**Rule**: output file path follows module-map.json mapping. See zigmodu-analyze.

## Translation Decision Tree

For each method in source file:

```
Method is pure CRUD delegation?
  ├─ YES → SKIP. zmodu already generated this.
  └─ NO  → Contains business rules?
            ├─ Simple (if/else, validation, single-table) → [AUTO] translate
            ├─ Medium (multi-table, calculation, state machine) → [REVIEW] translate + note
            └─ Complex (@Transactional + external API + compensation) → [MANUAL] skeleton only
```

## Type Mapping Table

```
Java                         →  Zig
────────────────────────────────────────────
String                       →  []const u8
int, Integer                 →  i32
long, Long                   →  i64
double, Double, BigDecimal   →  f64
boolean, Boolean             →  bool
Date, LocalDateTime, Instant →  []const u8 (ISO 8601 string)
Optional<T>                  →  ?T
List<T>, ArrayList<T>        →  []T
Map<K,V>, HashMap<K,V>       →  std.StringHashMap(V)
Page<T> (Spring Data)        →  data.orm.PageResult(T)
ResponseEntity<T>            →  ctx.jsonStruct(status, value)

PHP               →  Zig
───────────────────────────
string            →  []const u8
int               →  i64
float             →  f64
bool              →  bool
?Type / null      →  ?Type
array             →  []T or std.StringHashMap(V)

Go                →  Zig
───────────────────────────
string            →  []const u8
int, int64        →  i64
float64           →  f64
bool              →  bool
*Type / nil       →  ?T
[]Type            →  []T
map[string]Type   →  std.StringHashMap(Type)
time.Time         →  []const u8
error             →  !T (error union)
```

## Pattern Translation

### @Transactional → repo.transact()
```java
// SOURCE
@Transactional
public Order createOrder(OrderRequest req) {
    Order order = orderRepo.save(...);
    paymentService.charge(...);
    return order;
}
```
```zig
// TARGET: ext/service.zig
pub fn createOrder(self: *OrderServiceExt, req: OrderRequest) !model.Order {
    var repo = self.svc.persistence.orderRepo();
    return repo.transact(model.Order, struct {
        fn run(tx: *data.orm.Tx(data.SqlxBackend)) !model.Order {
            _ = tx;
            // [MANUAL] Multi-step with compensation. Use SagaOrchestrator.
            @compileError("MANUAL: implement with Saga pattern");
        }
    }.run);
}
```

### @Cacheable → CacheManager
```zig
// ext/service.zig
pub fn getProduct(self: *ProductServiceExt, cache: *zigmodu.data.CacheManager, id: i64) !?model.Product {
    const key = try std.fmt.allocPrint(self.svc.allocator, "products:{d}", .{id});
    defer self.svc.allocator.free(key);
    if (cache.get(key)) |cached| return parseJson(model.Product, cached); // [AUTO]
    const result = try self.svc.persistence.productRepo().findById(id);
    if (result) |p| {
        const json = try std.json.Stringify.valueAlloc(self.svc.allocator, p, .{});
        defer self.svc.allocator.free(json);
        try cache.set(key, json, 300);
    }
    return result;
}
```

### @Async / CompletableFuture → EventBus
```zig
// ext/service.zig
pub fn onOrderCreated(self: *EmailServiceExt, event: order.OrderEvent) void {
    if (event == .order_created) {
        // triggered by EventBus, no return value needed
    }
}
```

### Validation → explicit checks
```zig
// ext/service.zig
pub fn validateOrder(self: *OrderServiceExt, req: OrderRequest) !void {
    if (req.name.len == 0 or req.name.len > 100) return error.InvalidName;
    if (req.quantity < 0) return error.InvalidQuantity;
}
```

### Exception → Error Union
```zig
return error.ProductNotFound;
return error.InsufficientStock;
```

## Output File Format

```zig
//! Custom business logic for <module> — survives zmodu regeneration.
//! Source: <original file path>
//! Translated: [AUTO] 3 methods, [REVIEW] 2 methods, [MANUAL] 1 method

const std = @import("std");
const zigmodu = @import("zigmodu");
const service = @import("../service.zig");  // parent dir
const model = @import("../model.zig");

pub const OrderServiceExt = struct {
    svc: *service.OrderService,

    pub fn init(svc: *service.OrderService) OrderServiceExt {
        return .{ .svc = svc };
    }

    // ── [AUTO] ── (direct translations, no review needed)

    // ── [REVIEW] ── (translated but need human confirmation)

    // ── [MANUAL] ── (skeletons, must be rewritten)
};
```

## Translation Checklist (AI runs per file)

```
□ Count: total methods in source file
□ Count: [AUTO] translated
□ Count: [REVIEW] translated
□ Count: [MANUAL] skeleton
□ Verify: zig build passes
□ Report: "X.java → ext/service.zig: 12 methods, 8 [AUTO], 3 [REVIEW], 1 [MANUAL]"
```

## Batch Translation Priority

1. Controllers → ext/api.zig (route differences)
2. Services with @Transactional → ext/service.zig (business logic)
3. Services with @Cacheable → ext/service.zig (caching)
4. EventListeners → EventBus subscribers
5. @Scheduled → cron module
6. Configuration → ExternalizedConfig
