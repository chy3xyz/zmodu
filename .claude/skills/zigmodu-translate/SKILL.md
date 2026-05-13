---
name: zigmodu-translate
description: Translate Java/PHP business logic to ZigModu Zig code. Use when converting service classes, controllers, middleware, or domain logic from legacy backends.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Translate Legacy Code → ZigModu

## Phase 3 of Migration Harness

Purpose: Convert business logic from Java/PHP to idiomatic Zig with confidence tagging.

## Translation Confidence Tags

Always mark each translation block:

```
[AUTO]    Direct mechanical translation, no review needed
[REVIEW]  Business logic preserved, needs human confirmation
[MANUAL]  Complex logic, framework-specific, must rewrite manually
```

## Type Mapping

### Java → Zig
```
String, varchar, text      → []const u8
int, Integer, long, Long   → i64
double, Double, BigDecimal → f64
boolean, Boolean           → bool
Date, LocalDateTime        → []const u8 (ISO 8601)
Optional<T>                → ?T
List<T>, ArrayList<T>      → []T
Map<K,V>, HashMap<K,V>     → std.StringHashMap(V)
Set<T>, HashSet<T>         → std.AutoHashMap(T, void)
CompletableFuture<T>       → EventBus publish/subscribe
Stream<T>                  → []T (materialize)
```

### PHP → Zig
```
string              → []const u8
int                 → i64
float               → f64
bool                → bool
?Type / null        → ?Type
array               → []T  or  std.StringHashMap(V)
Collection          → []T
Carbon/DateTime     → []const u8
```

## Pattern Translation

### [AUTO] Simple CRUD Service

```java
// Spring Boot
@Service
public class OrderService {
    @Autowired
    private OrderRepository repo;

    public Page<Order> listOrders(int page, int size) {
        return repo.findAll(PageRequest.of(page, size));
    }

    public Optional<Order> getOrder(Long id) {
        return repo.findById(id);
    }

    public Order createOrder(Order order) {
        return repo.save(order);
    }
}
```

→

```zig
// ZigModu service.zig
pub fn listOrders(self: *OrderService, page: usize, size: usize) !data.orm.PageResult(model.Order) {
    var repo = self.persistence.orderRepo();
    return try repo.findPage(page, size);
}

pub fn getOrder(self: *OrderService, id: i64) !?model.Order {
    var repo = self.persistence.orderRepo();
    return try repo.findById(id);
}

pub fn createOrder(self: *OrderService, entity: model.Order) !model.Order {
    var repo = self.persistence.orderRepo();
    return try repo.insert(entity);
}
// [AUTO] confidence: high
```

### [REVIEW] Business Logic with Rules

```java
public Order placeOrder(OrderRequest req) {
    // Validate stock
    var product = productRepo.findById(req.getProductId())
        .orElseThrow(() -> new BusinessException("Product not found"));
    if (product.getStock() < req.getQuantity()) {
        throw new BusinessException("Insufficient stock");
    }

    // Calculate price
    var totalPrice = product.getPrice() * req.getQuantity();
    if (req.getCouponCode() != null) {
        var coupon = couponService.validateCoupon(req.getCouponCode());
        totalPrice = totalPrice - coupon.getDiscount();
    }

    // Create order
    var order = new Order();
    order.setProductId(req.getProductId());
    order.setQuantity(req.getQuantity());
    order.setTotalPrice(totalPrice);
    order.setStatus(OrderStatus.PENDING);

    // Deduct stock
    product.setStock(product.getStock() - req.getQuantity());
    productRepo.save(product);

    // Publish event
    eventPublisher.publishEvent(new OrderCreatedEvent(order));

    return orderRepo.save(order);
}
```

→

```zig
pub fn placeOrder(self: *OrderService, req: PlaceOrderRequest) !model.Order {
    // Validate stock
    const product = (try self.productRepo().findById(req.product_id)) orelse
        return error.ProductNotFound;
    if (product.stock < req.quantity) return error.InsufficientStock;

    // Calculate price
    var total_price = product.price * @as(f64, @floatFromInt(req.quantity));
    if (req.coupon_code) |code| {
        const coupon = try self.couponService.validateCoupon(code);
        total_price -= coupon.discount;
    }

    // Create order
    var order = model.Order{
        .id = 0,
        .product_id = req.product_id,
        .quantity = req.quantity,
        .total_price = total_price,
        .status = "PENDING",
    };
    const created = try self.repo.insert(order);

    // Deduct stock
    var updated_product = product;
    updated_product.stock -= req.quantity;
    try self.productRepo().update(updated_product);

    // Publish event
    self.publish(.{ .order_created = .{ .id = created.id } });

    return created;
}
// [REVIEW] business rules preserved, confirm stock concurrency, coupon edge cases
```

### [MANUAL] Complex Transaction

```java
@Transactional(rollbackFor = Exception.class)
public void processPayment(PaymentRequest req) {
    // 1. Lock order
    var order = orderRepo.findByIdForUpdate(req.getOrderId());
    if (order.getStatus() != OrderStatus.PENDING) {
        throw new BusinessException("Order not in pending state");
    }

    // 2. Call payment gateway
    var paymentResult = paymentGateway.charge(req.getAmount(), req.getCardToken());

    // 3. Update order status
    order.setStatus(paymentResult.isSuccess() ?
        OrderStatus.PAID : OrderStatus.PAYMENT_FAILED);
    orderRepo.save(order);

    // 4. Create payment record
    var payment = new PaymentRecord();
    payment.setOrderId(req.getOrderId());
    payment.setTransactionId(paymentResult.getTransactionId());
    payment.setAmount(req.getAmount());
    payment.setStatus(paymentResult.isSuccess() ? "SUCCESS" : "FAILED");
    paymentRepo.save(payment);

    // 5. If success, trigger fulfillment
    if (paymentResult.isSuccess()) {
        fulfillmentService.createFulfillment(order);
    }
}
```

→

```zig
pub fn processPayment(self: *PaymentService, req: PaymentRequest) !void {
    // [MANUAL] Requires transaction, external API call, multi-step compensation
    // Use Saga pattern with compensation steps:
    //
    // try saga.execute("process-payment", &.{
    //     .{ .action = lockOrder,       .compensate = unlockOrder },
    //     .{ .action = chargeGateway,   .compensate = refundGateway },
    //     .{ .action = updateOrder,     .compensate = revertOrder },
    //     .{ .action = createRecord,    .compensate = voidRecord },
    //     .{ .action = triggerFulfill,  .compensate = cancelFulfill },
    // });
}
// [MANUAL] confidence: low — rewrite with SagaOrchestrator
```

## Translation Rules

### 1. Exception → Error Union
```java
throw new BusinessException("msg")   → return error.BusinessError
throw new NotFoundException("msg")   → return error.NotFound
throw new ValidationException("msg") → return error.ValidationFailed
```

### 2. Dependency Injection → Explicit Wiring
```java
@Autowired private OrderRepository repo;
@Autowired private CouponService couponService;
```
→
```zig
persistence: *persistence.OrderPersistence,
couponService: *CouponService,  // passed via init()
```

### 3. Annotation → Struct Field / Module Config
```java
@Value("${app.max-order-items}")
private int maxOrderItems;
```
→
```zig
const max_order_items: usize = 10; // from env config
// OR load from ExternalizedConfig at startup
```

### 4. Logging
```java
log.info("Order {} created", order.getId());
log.error("Payment failed", e);
```
→
```zig
std.log.info("Order {d} created", .{order.id});
std.log.err("Payment failed: {s}", .{@errorName(err)});
```

## Batch Translation

```bash
# Translate all service files
zmodu translate --batch \
  --source src/main/java/com/example/service/ \
  --output src/modules/ \
  --mapping translation-map.json
```

`translation-map.json`:
```json
{
  "OrderService.java": "src/modules/order/service.zig",
  "UserService.java": "src/modules/user/service.zig",
  "PaymentService.java": "src/modules/payment/service.zig",
  "confidence_threshold": "REVIEW"
}
```

Files below REVIEW confidence are skipped for manual handling.

## Post-Translation Steps

1. Run `zig build` to check compilation
2. For [REVIEW] files: run `zig build test` with generated tests
3. For [MANUAL] files: add to manual rewrite queue
4. Re-run `zmodu harness verify` to compare with original backend
