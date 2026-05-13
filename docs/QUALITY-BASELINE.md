# ZModu 项目品质基线 — 不可退化的最低标准

## 编译标准

| 指标 | 基线 | 当前 |
|------|------|------|
| `zig build` 编译错误 | 0 | 0 ✅ |
| `zig build test` 失败 | 0 | 0 ✅ |
| 生成代码行数 | < 350 files | 344 files ✅ |

## 代码质量标准

### 1. Model 层

| 检查项 | 要求 | 当前 |
|--------|------|------|
| 字段名与 SQL 列名一致 | snake_case | ✅ |
| NOT NULL → 非 optional | 编译期保证 | ✅ |
| 无手写 jsonStringify | ctx.jsonStruct 自动序列化 | ✅ |
| JSON 字段名可配置 | `--json-style snake|camel` | ❌ 缺失 |
| sql_table_name 常量 | 每个 struct 必须有 | ✅ |
| 无未使用 import | `const std` 可移除 | ❌ model.zig 有无用导入 |

### 2. Persistence 层

| 检查项 | 要求 | 当前 |
|--------|------|------|
| Repo 方法使用 data.Repository(T) | 类型别名 | ✅ |
| 无重复 ORM 实例 | 每个 struct 一个 orm 字段 | ✅ |
| backend 字段传递正确 | init() 接收 backend | ✅ |

### 3. Service 层

| 检查项 | 要求 | 当前 |
|--------|------|------|
| CRUD 方法 5 个/表 | list/get/create/update/delete | ✅ |
| EventBus 可选 | `--enable-events` flag 控制 | ❌ 始终生成 |
| 无冗余 import | 无 EventBus 时不导入 | ❌ 始终导入 zigmodu |
| 事务方法 | `--with-transactions` 生成 transact | ❌ 缺失 |

### 4. API 层

| 检查项 | 要求 | 当前 |
|--------|------|------|
| RESTful 路径 | `/<resource>` + `/<resource>/:id` | ✅ |
| resolve(ctx) helper | 每个 struct 有 | ✅ |
| 分页参数解析 | page/size query params | ✅ |
| 错误处理 | 400/404 显式返回 | ✅ |
| 路由复数正确 | `addresses` 不是 `addresss` | ❌ 简单加 's' |
| 输入校验 | bindJson 后校验必填字段 | ❌ 缺失 |
| Content-Type header | application/json | ✅ |

### 5. Module 层

| 检查项 | 要求 | 当前 |
|--------|------|------|
| api.Module 声明 | name + deps + is_internal | ✅ |
| init/deinit 生命周期 | 完整实现 | ✅ |
| registerHealthChecks | HealthEndpoint 注册 | ✅ |
| 无运行时 @import | 全部顶部导入 | ✅ |

### 6. Main 层

| 检查项 | 要求 | 当前 |
|--------|------|------|
| 模块织入顺序 | import → persistence → service → api → routes → lifecycle | ✅ |
| Zig 关键字处理 | `return_mod`, `app_mod` 等 | ✅ |
| HealthEndpoint 探针 | liveness + readiness | ✅ |
| 环境变量读取 | env.get("KEY") orelse "default" | ✅ |

## AI 可编程标准

| 检查项 | 要求 | 当前 |
|--------|------|------|
| 文件边界清晰 | 生成文件 vs _ext 文件明确分离 | ✅ |
| AGENTS.md 存在 | 项目根目录 | ✅ |
| .claude/skills/ 存在 | 8+ skills | ✅ |
| .life/ 存在 | DNA + tree + memory | ✅ |
| 决策记录格式 | JSONL 一行一决策 | ✅ |
| regenerate 安全 | --force 不破坏 _ext 文件 | ❌ 未验证 |

## 性能标准

| 检查项 | 要求 | 当前 |
|--------|------|------|
| jsonStruct 无额外分配 | 流式写入 response_body | ❌ allocPrint 分配 |
| Repository 创建开销 | O(1) 每次调用 | ✅ (struct { orm: *Self }) |
| SQL 查询参数化 | 防止注入 | ✅ (ORM 层) |
| 无全局锁 | 每个请求独立 Context | ✅ |

## JSON 字段命名标准

| 检查项 | 要求 |
|--------|------|
| 前端期望 snake_case | model 字段直接序列化 — 无转换开销 |
| 前端期望 camelCase | model 编译期生成 @jsonName 映射 — 零运行时开销 |
| 配置方式 | `--json-style snake|camel` (默认 snake) |
| 实现方式 | comptime 反射 + 编译期字段名映射，非运行时字符串替换 |

## zigmodu 框架需改进

| 优先级 | 问题 | 影响 |
|--------|------|------|
| P0 | ctx.jsonStruct 使用 allocPrint 分配 | 每个请求额外分配 |
| P1 | Context 缺少 queryInt/paramInt 辅助 | 每个 handler 4 行样板 |
| P1 | Route 复数化规则缺失 | `addresss` 等错误 |
| P2 | EventBus(T) 编译期开销 | 不需要事件时也生成 |
| P2 | ctx.bindJson 无验证钩子 | 接受任意输入 |
| P2 | Server.fromEnv 类型不匹配 | `Environ` vs `*Environ.Map` |

## 版本兼容性检查

每次 zigmodu 升级后必须验证:

```
□ zmodu bigdemo 生成成功 (152 tables → 42 modules → 344 files)
□ zmodu scaffold 生成项目编译 0 error
□ zmodu new 生成项目编译 0 error
□ zmodu life tree 正常工作
□ zmodu life fingerprint 正常工作
□ zmodu life evolve 正常工作
□ zmodu plugin list 正常工作
□ 所有 8+ skills 正确生成
□ AGENTS.md 包含 First Principle 章节
□ .life/ 目录包含 5 个文件
□ src/plugins/manifest.json 存在
```
