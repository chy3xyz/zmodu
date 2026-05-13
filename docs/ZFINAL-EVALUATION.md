# ZFinal → ZigModu 移植评估 (Modulith 视角)

## 评估原则

zigmodu 是 Modulith 框架 — 模块化单进程架构。移植需满足：
1. 自包含 — 不引入外部运行时依赖
2. 框架层 — 属于基础设施，非业务逻辑
3. 模块可组合 — 每个模块独立可用

## Kit 工具评估

| zfinal Kit | zigmodu 等价 | 移植 | 理由 |
|------------|-------------|------|------|
| HashKit | 无 | **P0 移植** | 密码存储、token生成、文件校验 — 通用基础设施 |
| StrKit | std.mem 覆盖 | ❌ | 标准库已充分 |
| DateKit | 无 | P2 | 日期格式化常见但非核心 |
| FileKit | 无 | P2 | 安全文件操作有价值但使用频率低 |
| JsonKit | Context.bindJson | ❌ | 已有深度校验的 parse |
| ValidateKit | validation/Validator | ❌ | 已有 validateStruct + FieldRules |
| NumberKit | std.fmt | ❌ | 标准库已充分 |
| ArrayKit | std.mem | ❌ | 标准库已充分 |
| RandomKit | util.randomHex | ❌ | 已有 |
| CacheKit | cache/CacheManager | **P1** | 需增强 Redis backend |

## Plugin 评估

| zfinal Plugin | zigmodu 等价 | 移植 | 理由 |
|--------------|-------------|------|------|
| cron | scheduler/Cron.zig | **P1 增强** | zfinal 5-field 解析器更完整 |
| cache | cache/CacheManager | **P1 增强** | 需 Redis backend |
| redis | redis/redis.zig | ❌ | 已有 |
| mqtt | 无 | ❌ | 非 Modulith 核心，业务层关注 |
| p2p | 无 | ❌ | 极 niche |
| did | 无 | ❌ | 极 niche |
| agent | 无 | ❌ | 未来方向，非当前 |
| compat/stubs | zmodu plugin 系统 | ❌ | zmodu 已有 |

## 实施清单

| 优先级 | 内容 | 代码量 | 位置 |
|--------|------|--------|------|
| P0 | HashKit (md5/sha1/sha256/hex) | 40行 | zigmodu util.zig |
| P1 | CronExpression 5-field parser | 120行 | zigmodu scheduler/Cron.zig |
| P1 | Cache Redis backend hint | 30行 | zigmodu cache/ |
| P2 | DateKit format | 60行 | zigmodu util.zig |
| P2 | FileKit safe ops | 50行 | zigmodu util.zig |

## 不移植的理由

- **mqtt/p2p/did/agent** — 这些是业务层或特定领域的中间件，不属于 Modulith 框架核心。应作为项目级 plugin stub (zmodu plugin 系统) 处理
- **StrKit/NumberKit/ArrayKit** — Zig 标准库已充分覆盖，加封装反而增加学习成本
- **JsonKit depth check** — Context.bindJson 可以加 depth 参数
