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
P0 (blocks business):    支付网关, 短信, 推送, 认证
P1 (blocks features):    文件存储, 搜索, 报表, 定时任务
P2 (nice to have):       日志聚合, 配置中心, 功能开关
```

## Usage

```bash
# Generate a single stub plugin
zmodu plugin stub --name wechat-pay --methods "createOrder,queryOrder,refund" --priority P0

# Generate from analysis (reads analysis.json for missing deps)
zmodu plugin generate --analysis analysis.json

# List all stubs and their status
zmodu plugin list

# Mark a stub as implemented
zmodu plugin done --name wechat-pay
```

## Generated Stub Structure

```
src/plugins/wechat-pay/
├── stub.zig          # Interface + error.NotImplemented
├── README.md         # Original dependency info + implementation notes
└── PRIORITY          # P0|P1|P2 file
```

## stub.zig Template

```zig
//! WeChat Pay Plugin — STUB
//! Priority: P0 | Source: com.example.payment.WeChatPayService
//! Original dep: wechatpay-apiv3 (Maven)

pub const WechatPayPlugin = struct {
    /// Create payment order. Returns prepay_id.
    /// Original: WeChatPayService.createOrder(OrderRequest) → OrderResponse
    pub fn createOrder(req: CreateOrderRequest) !CreateOrderResponse {
        _ = req;
        return error.NotImplemented;
    }

    /// Query order status by out_trade_no.
    pub fn queryOrder(out_trade_no: []const u8) !OrderResponse {
        _ = out_trade_no;
        return error.NotImplemented;
    }

    /// Refund order. Returns refund_id.
    pub fn refund(req: RefundRequest) !RefundResponse {
        _ = req;
        return error.NotImplemented;
    }

    // ── Request/Response types (from original API) ──

    pub const CreateOrderRequest = struct {
        out_trade_no: []const u8,
        amount: i64,        // in cents
        description: []const u8,
        notify_url: []const u8,
    };

    pub const CreateOrderResponse = struct {
        prepay_id: []const u8,
        qr_code: ?[]const u8,
    };

    pub const OrderResponse = struct {
        out_trade_no: []const u8,
        transaction_id: ?[]const u8,
        status: OrderStatus,
        amount: i64,
    };

    pub const OrderStatus = enum {
        pending,
        paid,
        closed,
        refunded,
    };

    pub const RefundRequest = struct {
        out_trade_no: []const u8,
        refund_no: []const u8,
        amount: i64,
        reason: []const u8,
    };

    pub const RefundResponse = struct {
        refund_id: []const u8,
        status: RefundStatus,
    };

    pub const RefundStatus = enum {
        processing,
        success,
        failed,
    };
};
```

## Service Integration

Service uses stub through interface injection:

```zig
// src/modules/payment/service_ext.zig
const wechat = @import("../../plugins/wechat-pay/stub.zig");

pub fn processPayment(self: *PaymentService, order: model.Order) !void {
    const req = wechat.WechatPayPlugin.CreateOrderRequest{ ... };
    const resp = wechat.WechatPayPlugin.createOrder(req) catch |err| switch (err) {
        error.NotImplemented => {
            std.log.warn("WeChat Pay stub: payment not processed for order {}", .{order.id});
            return error.PaymentUnavailable;
        },
        else => return err,
    };
    _ = resp;
}
```

## AI Implementation Workflow

```
1. zmodu plugin list → see all stubs, sorted by priority
2. Pick highest P0 stub
3. Read stub.zig → understand interface
4. Implement real logic (HTTP call to WeChat API, etc.)
5. zmodu plugin done --name wechat-pay → marks as implemented
6. zig build test → verify
```

## Plugin Manifest

`src/plugins/manifest.json`:
```json
{
  "stubs": [
    {"name":"wechat-pay","priority":"P0","source":"WeChatPayService.java","status":"STUB"},
    {"name":"aliyun-oss","priority":"P1","source":"OssService.java","status":"STUB"},
    {"name":"excel-export","priority":"P2","source":"ReportService.java","status":"STUB"}
  ]
}
```

## Integration with zigmodu-analyze

During migration analysis, detect dependencies with no Zig equivalent:

```bash
# zigmodu-analyze step 6: detect missing deps
grep -rn "import com.wechat\|import com.aliyun\|import org.apache.poi" src/main/java > analysis/missing-deps.txt
# AI reviews missing-deps.txt → generates plugin stubs
# zmodu plugin generate --from analysis/missing-deps.txt
```
