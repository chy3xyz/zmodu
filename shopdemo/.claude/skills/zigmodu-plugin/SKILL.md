---
name: zigmodu-plugin
description: Generate stub plugins for missing Zig dependencies. Creates compilable placeholder modules with error.NotImplemented markers.
---

# Plugin Stub System

## Principle
When migrating, dependencies without Zig equivalent get a stub.
Stub compiles, returns error.NotImplemented. AI fills later.

## Stub Convention
```zig
// src/plugins/<name>/stub.zig
// Priority: P0|P1|P2 (P0=core, P1=important, P2=nice)
// Status: STUB
pub const Plugin = struct {{
    pub fn method(...) !ReturnType {{
        _ = ...;
        return error.NotImplemented;
    }}
}};
```

## Priority
P0 (blocks business): 支付, 短信, 推送, 认证
P1 (blocks features): 文件存储, 搜索, 报表
P2 (nice to have): 日志聚合, 配置中心

## Commands
```bash
zmodu plugin list                    # list stubs by priority
zmodu plugin stub --name x --methods a,b --priority P0
zmodu plugin done --name x          # mark implemented
```
