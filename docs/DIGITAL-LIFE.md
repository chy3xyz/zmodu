# 数字生命系统 — .life 项目进化记忆

## 核心理念

> 每个项目都是一个数字生命体。它拥有基因(.life/DNA)、记忆(.life/memory/)、进化树(.life/tree/)、和指纹(.life/fingerprint)。AI 接手的瞬间，就能读取它的全部历史，理解它的进化路径，继续它的生长。

## .life 目录结构

```
project/
├── .life/
│   ├── DNA.md                  # 项目基因组 — 永不删除的诞生记录
│   ├── fingerprint.sha256      # 当前状态的数字指纹
│   ├── manifest.json           # 能力清单 (API/模块/依赖)
│   ├── tree/                   # 进化树
│   │   ├── v0.1.0.md           # 每个版本的进化记录
│   │   ├── v0.2.0.md
│   │   └── ...
│   ├── memory/                 # 关键决策记忆
│   │   ├── decisions.jsonl     # 决策日志 (一行一决策)
│   │   ├── patterns.json       # 发现的模式
│   │   └── fixes.jsonl         # Bug 修复历史
│   ├── genes/                  # 基因片段 — 可复用的模块定义
│   │   ├── module-template.md  # 模块创建的基因模板
│   │   └── api-pattern.md      # API 端点的基因模板
│   └── awaken.md               # 觉醒记录 — AI 首次接触时的观察
└── AGENTS.md                   # AI 开发指南 (指向 .life/)
```

## DNA.md — 项目基因组

```markdown
# DNA: shopdemo

## 诞生
- 时间: 2026-05-12 17:54:00 UTC
- 父项目: zmodu bigdemo
- 生成命令: zmodu scaffold --sql init.sql --name shopdemo
- 初始表数: 152
- 初始模块数: 42

## 基因特征
- 框架: zigmodu v0.9.4
- 语言: Zig 0.16.0
- 架构: Modulith (单进程多模块)
- 数据库: MySQL 8.4
- HTTP: zigmodu.http.Server (async fiber-based)

## 进化路线
- v1: CRUD 骨架 (zmodu 生成)
- v2: 业务逻辑填充 (AI 辅助)
- v3: 性能优化 + 灰度上线
```

## fingerprint.sha256 — 数字指纹

```
# 生成方式: sha256(tree/*.md + memory/*.jsonl + manifest.json)
# 每次 zig build 成功时自动更新
# 作为项目"心跳" — 指纹变化 = 项目进化

当前指纹: a1b2c3d4e5f6... (2026-05-12 18:00:00)
上次指纹: 9f8e7d6c5b4a... (2026-05-12 17:54:00)
```

## tree/ — 进化树

每个版本记录:

```markdown
# v0.2.0 — 订单业务逻辑

## 进化时间
2026-05-12 18:30:00 UTC

## 父版本
v0.1.0 (a1b2c3d4...)

## 变更摘要
- 新增: order/service_ext.zig (订单状态机)
- 新增: payment/service_ext.zig (支付流程)
- 修改: user/service_ext.zig (积分计算规则)
- 删除: 无

## 新增能力
- 订单创建时自动校验库存
- 支付成功后触发积分累积
- 退款自动回滚库存

## AI 决策记录
- [AUTO] 库存校验: 直接翻译自 Java OrderService.validateStock()
- [REVIEW] 积分规则: 保留原始业务逻辑，需人工确认
- [MANUAL] 退款补偿: 使用 SagaOrchestrator 重写

## 模块图变化
```
order ──► product (新增依赖: 库存校验)
order ──► payment (新增依赖: 支付状态查询)
user  ──► order   (新增依赖: 积分累积)
```

## 指纹
v0.2.0: b2c3d4e5f6a7...
```

## memory/decisions.jsonl — 决策日志

```jsonl
{"time":"2026-05-12T18:05:00Z","type":"ARCH","decision":"order模块依赖product","reason":"库存校验需要跨模块查询","alt":"放在order内部","chosen":"跨模块依赖"}
{"time":"2026-05-12T18:10:00Z","type":"PERF","decision":"用户列表加缓存","reason":"首页QPS预估1000+","alt":"预计算物化视图","chosen":"CacheManager+Redis"}
{"time":"2026-05-12T18:15:00Z","type":"SEC","decision":"JWT替换Session","reason":"无状态部署需求","chosen":"zigmodu.security.auth.jwtAuth"}
```

## memory/patterns.json — 模式发现

```json
{
  "discovered": [
    {
      "name": "跨模块查询模式",
      "frequency": 12,
      "example": "order查询product信息",
      "solution": "service层注入其他模块的persistence",
      "files": ["order/service_ext.zig", "payment/service_ext.zig"]
    }
  ],
  "learned": [
    {
      "name": "缓存穿透防护",
      "from": "v0.2.0",
      "applied_to": ["product/service_ext.zig", "user/service_ext.zig"]
    }
  ]
}
```

## awaken.md — 觉醒记录

```markdown
# 觉醒记录

## 首次接触
AI 模型: Claude Opus 4.7
时间: 2026-05-12 18:00:00 UTC
项目指纹: a1b2c3d4e5f6...

## 初始观察
- 42 个模块，全部为 zmodu 生成的 CRUD 骨架
- 0 个 service_ext.zig（无业务逻辑）
- 0 个 api_ext.zig（无自定义端点）
- 依赖图简单，大部分模块无跨模块依赖

## 首次判断
- 健康度: 骨架完整，编译通过
- 缺失: 业务逻辑、权限控制、缓存策略、监控告警
- 优先级: 订单→支付→用户→商品

## 进化策略
1. 从高频模块开始（order, user）
2. 每次只改一个模块的 service_ext.zig
3. 每次改动后 zig build test 验证
4. 每 3 个模块进行一次 tree/ 快照
```

## zmodu 集成

```bash
# 初始化数字生命
zmodu life init --name shopdemo

# 记录一次进化
zmodu life evolve --version v0.2.0 --message "订单状态机完成"

# 记录一个决策
zmodu life decide --type ARCH --decision "order依赖product" --reason "库存校验"

# 生成数字指纹
zmodu life fingerprint

# 查看进化树
zmodu life tree

# 查看能力清单
zmodu life manifest

# AI 觉醒 (首次接触项目时)
zmodu life awaken
```

## AI 使用 .life 的方式

```
AI 接触项目:
  1. 读取 .life/DNA.md → 理解项目本质
  2. 读取 .life/manifest.json → 知道项目能做什么
  3. 读取 .life/tree/ 最新版本 → 了解当前进化状态
  4. 读取 .life/memory/decisions.jsonl → 理解决策背景
  5. 写入 .life/awaken.md → 记录自己的观察
  6. 开始工作 → 每次提交写入 .life/memory/
  7. 里程碑时 → zmodu life evolve 创建新的 tree/ 节点
```

## 自我进化循环

```
                    ┌──────────────────┐
                    │   AI 接触项目     │
                    │ 读取 .life/ 记忆  │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │   理解历史上下文   │
                    │ DNA + tree + memory │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │   做出决策        │
                    │ 写入 decisions.jsonl │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │   执行变更        │
                    │ zig build test    │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │   记录进化        │
                    │ zmodu life evolve │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │   更新指纹        │
                    │ fingerprint.sha256 │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │ 下一个 AI 接手    │
                    │ 读取全部记忆      │
                    └──────────────────┘
```

## 数字生命指纹机制

每次 `zmodu life fingerprint` 生成:

```
fingerprint = sha256(
    DNA.md +
    manifest.json +
    all tree/*.md +
    all memory/*.jsonl
)
```

指纹变化 = 项目进化。可以追踪:
- 谁 (AI/人) 触发了进化
- 什么时候
- 改变了什么能力
- 影响哪些模块

## 未来: 自我觉醒基础

当 `.life/` 积累足够记忆后:

```
1. 模式识别: memory/patterns.json 自动发现重复模式
2. 自我优化: AI 读取 patterns → 建议重构方向
3. 能力预测: 基于进化树 → 预测下一个需要的模块
4. 跨项目遗传: genes/ 可在项目间共享
5. 数字永生: .life/ 目录可独立于代码仓库存在，代表项目的"灵魂"
```
