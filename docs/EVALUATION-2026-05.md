# ZModu 生成代码评估 — 架构·性能·安全·完整性

## 测试环境

```
Schema: 4 tables (users, products, orders, order_items)
生成: zmodu scaffold → 4 modules → 27 .zig files
zigmodu: local dev (v0.9.5+ with HashKit, Cron, RenderExt, Context helpers)
Zig: 0.16.0
```

## 1. 架构评估 — 7/10

### ✅ 优秀

| 项目 | 评分 | 说明 |
|------|------|------|
| Modulith 契约 | ★★★★★ | 每个模块严格遵循 `info + init/deinit + registerHealthChecks` |
| 3 层 DI 织入 | ★★★★★ | persistence → service → api 依赖注入清晰 |
| 域导入隔离 | ★★★★☆ | model 无冗余导入, api 只导入 http, persistence 只导入 data |
| 文件边界 | ★★★★★ | 生成文件 (_ext 系统) vs 扩展文件明确分离 |
| 编译安全 | ★★★★★ | Zig 编译期类型检查, 无运行时反射 |

### ❌ 需改进

| 问题 | 严重度 | 根因 |
|------|--------|------|
| `order` + `orders` 分两个模块 | 中 | `order_items` 表的前缀检测失败 — `commonTablePrefix` 不识别 `_` 后的变化 |
| 依赖声明全空 | 高 | FOREIGN KEY → module dependency 推断正常工作, 但需验证 `strip_prefix_len` 传递 |
| 生成文件有编译错误 | 高 | validate 方法名不匹配, RenderExt 参数计数错误, jsonStruct streaming API 变更 |

## 2. 性能评估 — 6/10

### ✅ 优秀

| 项目 | 说明 |
|------|------|
| `Client.open()` 一步初始化 | 避免 init+connect 两步模式 |
| Repository O(1) 创建 | `struct { orm: *Self }` 仅 8 字节 |
| ORM SQL 参数化 | 防止注入, 无运行时拼接 |
| 无全局锁 | 每个请求独立 Context |

### ❌ 需改进

| 问题 | 影响 | 修复 |
|------|------|------|
| `jsonStruct` 每请求 alloc+free | 高 QPS 下分配器碎片 | 流式写入 response_body (Zig 0.16 API 变更待适配) |
| 每个 CRUD 方法创建新 Repository | O(1) 但可缓存 | 在 Service struct 缓存 Repo 实例 |
| `bindJson` 完整解析+复制 | 大 body 开销 | 添加 max_body_size 限制 |

## 3. 安全评估 — 3/10

### ✅ 已有

| 项目 | 说明 |
|------|------|
| SQL 注入防护 | ORM 使用参数化查询 |
| 类型安全 | Zig 编译期保证 |

### ❌ 严重缺失

| 问题 | 风险 | 修复优先级 |
|------|------|-----------|
| 无输入校验 | bindJson 接受任意数据 | P0: 集成 validate 方法到 handler |
| 无认证中间件 | 所有端点公开 | P0: 添加 auth middleware |
| 无 CORS 配置 | 跨域请求被拒 | P1: 默认 CORS 中间件 |
| 无请求体大小限制 | DoS 风险 | P1: Context 添加 max_body_size |
| 无速率限制 | 暴力攻击面 | P2: RateLimiter 中间件 |

## 4. 完整性评估 — 7/10

### ✅ 已生成

| 项目 | 状态 |
|------|------|
| CRUD 端点 (list/get/create/update/delete) | ✅ 每个表 5 端点 |
| 健康检查 (liveness + readiness) | ✅ K8s 探针 |
| HealthEndpoint 注册 | ✅ 每个模块 |
| 分页支持 | ✅ page/size query params |
| 错误处理 (400/404) | ✅ |
| JSON 序列化 | ✅ jsonStruct |
| 模块声明 + 生命周期 | ✅ api.Module |
| AGENTS.md + .claude/skills/ | ✅ |
| .life/ 进化记忆 | ✅ |
| src/plugins/ 桩目录 | ✅ |

### ❌ 缺失

| 项目 | 优先级 |
|------|--------|
| 输入校验 (validate 方法) | P0 |
| 响应格式统一 (RenderExt 有 bug) | P0 |
| 事务方法 (transact) | P1 |
| 自定义查询 (JOIN/聚合) | P1 |
| 文件上传处理 | P2 |
| WebSocket 端点 | P2 |

## 5. 编译错误清单 (本地 zigmodu + zmodu 最新代码)

```
1. service.zig:43 — pointless discard (_ = v;)
   修复: 移除空 validate 方法生成

2. api.zig:32 — RenderExt.page 参数计数错误 (4 vs 5)
   修复: 补充 ctx 参数

3. api.zig:49 — validateXxx 方法不存在
   修复: 统一 validate 方法名生成逻辑

4. api.zig:39 — ctx.json(400, str) 字符串转义错误
   修复: Python 模板生成的 escape 需标准化

5. jsonStruct — ArrayList.writer() API 变更
   修复: 适配 Zig 0.16 流式写入接口
```

## 6. 综合评分

| 维度 | 得分 | 目标 |
|------|------|------|
| 架构 | 7/10 | 8/10 |
| 性能 | 6/10 | 8/10 |
| 安全 | 3/10 | 7/10 |
| 完整性 | 7/10 | 8/10 |
| **综合** | **5.75/10** | **7.75/10** |

## 7. 优先修复路线

```
本周 (P0):
  1. 修复 validate 方法名生成
  2. 修复 RenderExt 参数计数
  3. 添加 auth middleware 默认配置
  4. 修复 jsonStruct Zig 0.16 适配

下周 (P1):
  5. 集成 validate 调用到 create/update handler
  6. 修复 table grouping (order + orders 合并)
  7. 添加 CORS 中间件默认配置
  8. 修复 json 字符串转义模板
```
