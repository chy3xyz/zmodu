---
name: zigmodu-translate
description: Translate Java/PHP/Go/Rust logic to ZigModu. Input: source file path. Output: _ext.zig file with [AUTO]/[REVIEW]/[MANUAL] tags. Never edits generated files.
allowed-tools: Read, Write, Bash, Grep, Glob
---

# Translate Business Logic → ZigModu _ext Files

## AI Contract

**Input**: path to Java/PHP/Go/Rust source file
**Output**: `src/modules/<name>/service_ext.zig` or `src/modules/<name>/api_ext.zig`
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

AI uses this exact mapping. No deviation.

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
List<T>, ArrayList<T>        →  []T (allocator required for mutable)
Map<K,V>, HashMap<K,V>       →  std.StringHashMap(V) (keys always []const u8)
Set<T>, HashSet<T>           →  std.AutoHashMap(T, void)
CompletableFuture<T>         →  EventBus publish/subscribe pattern
Stream<T>                    →  []T (materialize to slice first)
Page<T> (Spring Data)        →  data.orm.PageResult(T) (zmodu generated)
ResponseEntity<T>            →  ctx.jsonStruct(status, value)
```

```
PHP               →  Zig
───────────────────────────
string            →  []const u8
int               →  i64
float             →  f64
bool              →  bool
?Type / null      →  ?Type
array             →  []T  or  std.StringHashMap(V)
Collection        →  []T
Carbon\Carbon     →  []const u8
```

```
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

## Pattern Translation (Fixed Rules)

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
// TARGET: service_ext.zig
// [MANUAL] @Transactional with external payment — use SagaOrchestrator
pub fn createOrder(self: *OrderService, req: OrderRequest) !model.Order {
    // Multi-step with compensation. See zigmodu.SagaOrchestrator.
    @compileError("MANUAL: implement with Saga pattern");
}
```

### @Cacheable → CacheManager
```java
// SOURCE
@Cacheable(value = "products", key = "#id")
public Product getProduct(Long id) { ... }
```
```zig
// TARGET
pub fn getProduct(self: *ProductService, cache: *zigmodu.data.CacheManager, id: i64) !?model.Product {
    const key = try std.fmt.allocPrint(self.allocator, "products:{}", .{id});
    defer self.allocator.free(key);
    if (cache.get(key)) |cached| return parseProduct(cached); // [AUTO]
    const result = try self.persistence.productRepo().findById(id);
    if (result) |p| {
        const json = try std.json.stringifyAlloc(self.allocator, p, .{});
        defer self.allocator.free(json);
        try cache.set(key, json, 300); // TTL 5min
    }
    return result;
}
```

### @Async / CompletableFuture → EventBus
```java
// SOURCE
@Async
public CompletableFuture<Void> sendEmail(Email email) { ... }
```
```zig
// TARGET
// [AUTO] Async → EventBus
pub fn onOrderCreated(self: *EmailService, event: order.OrderEvent) void {
    if (event == .order_created) {
        // self.sendEmail(event.order_created.id);
        // triggered by EventBus, no return value needed
    }
}
```

### Validation Annotations → explicit checks
```java
// SOURCE
@NotNull @Size(min=1, max=100) private String name;
@Min(0) private int quantity;
```
```zig
// TARGET: place in service_ext.zig create method
pub fn validateOrder(self: *OrderService, req: OrderRequest) !void {
    if (req.name.len == 0 or req.name.len > 100) return error.InvalidName;
    if (req.quantity < 0) return error.InvalidQuantity;
}
```

### Exception → Error Union
```java
// SOURCE
throw new BusinessException("Product not found");
throw new InsufficientStockException(prodId, requested, available);
```
```zig
// TARGET
return error.ProductNotFound;
return error.InsufficientStock;
// Define custom errors in module:
pub const OrderError = error{ ProductNotFound, InsufficientStock, PaymentFailed };
```

## Output File Format

Every `_ext.zig` file follows this structure:

```zig
//! Custom business logic for <module> — survives zmodu regeneration.
//! Source: <original file path>
//! Translated: [AUTO] 3 methods, [REVIEW] 2 methods, [MANUAL] 1 method

const std = @import("std");
const zigmodu = @import("zigmodu");
const service = @import("service.zig");
const model = @import("model.zig");

pub const OrderServiceExt = struct {
    svc: *service.OrderService,

    pub fn init(svc: *service.OrderService) OrderServiceExt {
        return .{ .svc = svc };
    }

    // ── [AUTO] ──
    // methods automatically translated, no human review needed

    // ── [REVIEW] ──
    // methods translated, need human confirmation of business rules

    // ── [MANUAL] ──
    // skeletons only, must be rewritten with Saga/EventBus patterns
};
```

## Translation Checklist (AI runs per file)

After translating each source file:

```
□ Count: total methods in source file
□ Count: [AUTO] translated
□ Count: [REVIEW] translated
□ Count: [MANUAL] skeleton
□ Verify: zig build passes
□ Report: "X.java → service_ext.zig: 12 methods, 8 [AUTO], 3 [REVIEW], 1 [MANUAL]"
```

## Batch Translation Priority

Translate in this order (most impact first):

1. Controllers with @GetMapping/@PostMapping → api_ext.zig (route differences)
2. Services with @Transactional → service_ext.zig (business logic)
3. Services with @Cacheable → service_ext.zig (caching layer)
4. EventListeners → EventBus subscribers
5. @Scheduled methods → cron module or separate scheduler
6. Configuration classes → ExternalizedConfig
