# ZigModu 框架改进提案 — 参考 zfinal 最佳实践

## 概述

基于 zfinal 框架源码分析，提取可提升 zmodu 生成代码品质的 zigmodu 框架改进方案。

## 1. Validator — 请求校验器

**zfinal 参考**: `src/validator/validator.zig` — 完整的字段校验器，链式规则。

**现状**: zigmodu 生成的 API handler 中 `bindJson` 无校验，接受任意输入。

**需求**:

```zig
// zigmodu.validation — 新增模块
pub const Validator = struct {
    errors: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Validator { ... }
    pub fn deinit(self: *Validator) void { ... }
    pub fn hasErrors(self: *const Validator) bool { ... }

    // 规则方法
    pub fn required(self: *Validator, field: []const u8, value: ?[]const u8) !void { ... }
    pub fn maxLen(self: *Validator, field: []const u8, value: []const u8, max: usize) !void { ... }
    pub fn minLen(self: *Validator, field: []const u8, value: []const u8, min: usize) !void { ... }
    pub fn range(self: *Validator, field: []const u8, value: i64, min: i64, max: i64) !void { ... }
    pub fn email(self: *Validator, field: []const u8, value: []const u8) !void { ... }
    pub fn pattern(self: *Validator, field: []const u8, value: []const u8, regex: []const u8) !void { ... }
};
```

**zmodu 集成**: 从 SQL NOT NULL/UNIQUE/VARCHAR(n) 约束自动生成 validator 调用。

```zig
// 自动生成在 service_ext.zig:
pub fn validateOrder(self: *OrderService, entity: model.Order) !void {
    var v = zigmodu.Validator.init(self.allocator);
    defer v.deinit();
    if (entity.order_no.len == 0) try v.required("order_no", null);
    if (entity.order_no.len > 64) try v.maxLen("order_no", entity.order_no, 64);
    if (v.hasErrors()) return error.ValidationFailed;
}
```

---

## 2. RenderExt — 统一响应格式

**zfinal 参考**: `src/ext/util.zig` — `RenderExt.success/err/page` 统一包装。

**现状**: zigmodu handler 手动写 JSON 字符串，格式不统一。

**需求**:

```zig
// zigmodu.http — 新增 RenderExt
pub const RenderExt = struct {
    /// {"success":true,"data":<value>}
    pub fn success(ctx: *Context, data: anytype) !void {
        try ctx.jsonStruct(200, .{ .success = true, .data = data });
    }

    /// {"success":false,"err":"<message>"}
    pub fn err(ctx: *Context, message: []const u8) !void {
        try ctx.jsonStruct(200, .{ .success = false, .err = message });
    }

    /// {"success":true,"data":{"list":[...],"total":N,"page":P,"pageSize":S,"totalPages":T}}
    pub fn page(ctx: *Context, list: anytype, total: usize, page: usize, size: usize) !void {
        try ctx.jsonStruct(200, .{
            .success = true,
            .data = .{ .list = list, .total = total, .page = page, .pageSize = size,
                       .totalPages = (total + size - 1) / size },
        });
    }
};
```

**zmodu 集成**: 生成的 handler 默认使用 `RenderExt.page/success`。

---

## 3. ParamExt — 参数获取增强

**zfinal 参考**: `src/ext/util.zig` — `ParamExt.require/requireInt/getIntOr`。

**现状**: zigmodu Context 已有 `queryInt/paramInt`，但缺少必填参数直接报错的便捷方法。

**需求** — 在已有基础上补充:

```zig
// zigmodu.http.Context — 追加方法

/// Query parameter as integer, returns error with JSON response if missing.
pub fn requireQueryInt(self: *Context, comptime T: type, key: []const u8) !T {
    const val = self.query.get(key) orelse {
        try self.json(400, "{\"err\":\"Missing required parameter: " ++ key ++ "\"}");
        return error.BadRequest;
    };
    return std.fmt.parseInt(T, val, 10) catch {
        try self.json(400, "{\"err\":\"Invalid parameter: " ++ key ++ "\"}");
        return error.BadRequest;
    };
}

/// Query parameter as boolean ("1"/"true"/"yes" → true).
pub fn queryBool(self: *const Context, key: []const u8, default: bool) bool {
    const val = self.query.get(key) orelse return default;
    return std.mem.eql(u8, val, "1") or std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "yes");
}
```

---

## 4. IP/Request 工具扩展

**zfinal 参考**: `src/ext/ext_util.zig` — `IpExt.getRealIp`, `RequestExt.isAjax/isMobile`。

**需求**:

```zig
// zigmodu.http — 新增请求工具
pub const RequestUtil = struct {
    /// 获取客户端真实 IP (X-Real-IP > X-Forwarded-For > remote)
    pub fn getRealIp(ctx: *const Context) []const u8 { ... }

    /// 检查 AJAX 请求
    pub fn isAjax(ctx: *const Context) bool { ... }

    /// 检查移动端
    pub fn isMobile(ctx: *const Context) bool { ... }
};
```

---

## 5. Context 属性存储 (Attribute Map)

**zfinal 参考**: `src/core/context.zig` — `attributes: std.StringHashMap([]const u8)`。

**现状**: zigmodu Context 有 `user_data: ?*anyopaque`，只能存一个指针。

**需求**: 添加通用属性存储，中间件可在 Context 上挂任意数据。

```zig
// zigmodu.http.Context — 追加字段和方法
attributes: std.StringHashMap([]const u8),

pub fn setAttr(self: *Context, key: []const u8, value: []const u8) !void { ... }
pub fn getAttr(self: *const Context, key: []const u8) ?[]const u8 { ... }
```

---

## 6. 分页结果统一类型

**zfinal 参考**: `RenderExt.page` — 统一的分页响应结构。

**现状**: zigmodu `data.orm.PageResult(T)` 只含 `items/page/size/total`。

**需求**: 添加标准的分页响应结构。

```zig
// zigmodu.data — 新增
pub const PagedResponse = struct {
    pub fn json(page: data.orm.PageResult(T)) PagedData { ... }
};

pub const PagedData = struct {
    list: []const anyopaque, // type-erased
    total: usize,
    page: usize,
    page_size: usize,
    total_pages: usize,
};
```

---

## 7. Session 存储

**zfinal 参考**: `src/core/session.zig` — 内存 Session 存储。

**需求**: 轻量级 Session 支持。

```zig
// zigmodu.http — 新增
pub const SessionStore = struct {
    pub fn init(allocator: std.mem.Allocator) SessionStore { ... }
    pub fn get(self: *SessionStore, id: []const u8) ?*Session { ... }
    pub fn create(self: *SessionStore, allocator: std.mem.Allocator) !*Session { ... }
};
```

---

## 优先级排序

| 优先级 | 改进 | 改动量 | 影响 |
|--------|------|--------|------|
| P0 | Validator | 80 行 | 所有 POST/PUT handler 安全提升 |
| P0 | RenderExt (success/err/page) | 30 行 | 统一所有 handler 响应格式 |
| P1 | ParamExt (requireInt/queryBool) | 30 行 | 减少 handler 样板 |
| P1 | Context attributes | 20 行 | 中间件数据传递 |
| P2 | IP/Request 工具 | 40 行 | 运维/监控 |
| P2 | Session 存储 | 80 行 | 认证系统 |
| P3 | 分页统一类型 | 30 行 | API 规范 |

**建议**: P0 + P1 共 160 行改动，覆盖 90% 的代码品质提升。
