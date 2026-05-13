# Migration Harness — Java/PHP → ZigModu 复刻体系

## 概述

Migration Harness 是 zmodu 的企业级功能：将传统 Java/PHP 后端项目，通过 AI 辅助 + 工程化流程，完整迁移到 Modulith 架构 + zigmodu 框架 + Zig 0.16.0。

核心原则：**最大化复用前端 UI 代码，最小化后端重写风险。**

## Harness 工程思想

```
                    ┌─────────────────────────────┐
                    │      Migration Harness       │
                    │  ┌───────┐  ┌────────────┐  │
Source Project ───►│  │Analyze│  │  Generate   │──► ZigModu Project
(Java/PHP)         │  └───┬───┘  └─────┬──────┘  │  (Zig 0.16.0)
                    │      │            │          │
                    │  ┌───▼────────────▼───────┐  │
                    │  │   Validation Loop       │  │
                    │  │  Diff Test · API Compare│  │
                    │  │  Schema Verify · Perf   │  │
                    │  └─────────────────────────┘  │
                    └─────────────────────────────┘
```

### Harness 四阶段

| 阶段 | 名称 | 产出 | 验证方式 |
|------|------|------|----------|
| 1 | **Analyze** | 项目画像、Schema 映射、API 清单 | 与原项目对比数据完整性 |
| 2 | **Scaffold** | ZigModu 项目骨架、模型、路由 | `zig build` 编译通过 |
| 3 | **Translate** | 业务逻辑翻译、中间件适配 | API diff test 对等 |
| 4 | **Verify** | 性能基准、集成测试、灰度切流 | 新旧并行对比 |

## 支持的源项目类型

### Java (Spring Boot / Spring Modulith)

```
源项目特征                          →  ZigModu 映射
─────────────────────────────────────────────────
@SpringBootApplication              → zigmodu.Application
@Modulith                          → api.Module (原生支持)
@Entity / @Table                   → model.zig (struct + sql_table_name)
@Repository (Spring Data JPA)      → persistence.zig (data.Repository)
@Service                           → service.zig
@RestController / @GetMapping      → api.zig (REST handlers)
application.yml / .properties      → ExternalizedConfig + env vars
Flyway / Liquibase migrations      → MigrationRunner
Spring Security / OAuth2           → security.auth (JWT/RBAC)
@CircuitBreaker (Resilience4j)     → CircuitBreaker
@Retry                             → retry module
@Cacheable                         → CacheManager
@Async / @EventListener            → EventBus
@Scheduled                         → cron module
@Transactional                     → Repository.transact()
Spring Actuator /health            → HealthEndpoint
```

### PHP (Laravel / Symfony)

```
源项目特征                          →  ZigModu 映射
─────────────────────────────────────────────────
artisan serve                      → zig build run
Eloquent Model                     → model.zig
Migration                          → Migration 模块
Controller                         → api.zig
Service / Repository Pattern       → service.zig + persistence.zig
Middleware (auth, cors, throttle)  → http Middleware
Event/Listener                     → EventBus
Queue/Job (Horizon)                → EventBus + OutboxPublisher
Cache (Redis/Memcached)            → CacheManager + Redis
Config (config/*.php)              → ExternalizedConfig
.env                               → env vars (built-in)
PHPUnit / Pest                     → zig test
Laravel Telescope / Debugbar       → PrometheusMetrics + Dashboard
```

## 复用 UI 前端策略

### 零改动方案（推荐）

前端代码完全不改。后端只替换 API 实现，保持：

```
前端 (React/Vue/jQuery) ──HTTP──► Nginx ──► 旧后端 (Java/PHP)
                                                │
                         前端 (不变) ──HTTP──► Nginx ──► 新后端 (ZigModu)
```

关键约束：
1. **URL 路径一致** — 生成的路由必须匹配原始 API 路径
2. **请求/响应格式一致** — JSON 字段名、状态码、分页格式完全对齐
3. **Cookie/Token 机制一致** — JWT/Session 认证无缝替换
4. **错误码一致** — 业务错误码映射

### 路径适配器

zmodu 分析源项目的路由定义，生成精确匹配的路由：

```bash
# 从 Spring @GetMapping 提取
zmodu analyze --source java --routes src/main/java/**/*Controller.java

# 从 Laravel routes/api.php 提取
zmodu analyze --source php --routes routes/api.php

# 输出路由清单 → 生成 ZigModu API
zmodu generate --from routes.json --preserve-paths
```

## 迁移流程

### Phase 1: Analyze — 项目画像

```bash
# 分析源项目结构
zmodu analyze --source java --input ./legacy-project/ --output analysis.json

# 产出:
# - analysis.json        完整项目画像
# - schema.sql           提取的数据库 DDL
# - routes.json          API 端点清单
# - dependencies.json    模块依赖图
# - config.json          配置项映射
```

分析内容：
- 数据库表结构（150+ 表 → SQL DDL）
- API 端点（路径、方法、参数、响应格式）
- 模块边界（包名/命名空间 → Modulith 模块分组）
- 中间件链（auth → cors → throttle → handler）
- 业务逻辑复杂度（圈复杂度标记需人工审查的函数）

### Phase 2: Scaffold — 项目骨架

```bash
# 从分析结果生成完整项目
zmodu harness --analysis analysis.json --output ./new-backend/

# 自动:
# 1. 表结构 → zmodu orm (生成 42+ 模块)
# 2. 路由清单 → API handler 骨架
# 3. 中间件链 → main.zig 织入
# 4. 配置项 → .env.example + config 模块
# 5. 认证逻辑 → security 模块
# 6. AGENTS.md + .claude/skills/ → AI 辅助开发基础设施
```

生成项目结构：
```
new-backend/
├── src/
│   ├── main.zig              # 入口 + 中间件织入
│   ├── modules/              # 自动生成的 CRUD 模块
│   │   ├── order/            # 从 SQL + Controller 分析生成
│   │   ├── user/
│   │   └── ...
│   ├── auth/                 # 认证模块（若源项目有）
│   ├── business/             # 复杂业务逻辑（需人工翻译）
│   └── compat/               # 兼容层（路径适配、响应格式转换）
├── tests/
│   ├── api/                  # API 对比测试
│   └── integration/          # 集成测试
├── harness/                  # Harness 验证工具
│   ├── diff-server.js        # 新旧后端对比代理
│   └── schema-verify.sql     # 数据库结构对比
└── AGENTS.md                 # AI 开发指南
```

### Phase 3: Translate — 业务逻辑翻译

AI 辅助 + 人工审查的模式：

```bash
# 翻译单个 Java Service → Zig Service
zmodu translate --source OrderService.java --output src/modules/order/service.zig

# 批量翻译（AI 生成 + 标记置信度）
zmodu translate --batch --source src/main/java/**/*Service.java

# 置信度标记:
# [AUTO]   简单 CRUD，无需人工审查
# [REVIEW] 包含业务规则，需人工确认
# [MANUAL] 复杂逻辑（事务、分布式），人工重写
```

AI 翻译规则：
- `@Transactional` → `repo.transact()` 包裹
- `Optional<T>` → `?T` (Zig optional)
- `Stream<T>` → `[]T` (slice)
- `CompletableFuture<T>` → `EventBus` publish/subscribe
- `@Cacheable` → `CacheManager.get/set` 包裹
- `throw new BusinessException` → `return error.BusinessError`

### Phase 4: Verify — 验证与切流

```bash
# 启动对比代理（新旧后端并行）
zmodu harness verify --old http://localhost:8080 --new http://localhost:8081

# 对比模式:
# 1. Mirror: 所有请求同时发送新旧后端，对比响应
# 2. Shadow: 新后端静默运行，只记录差异
# 3. Canary: 1% 流量切到新后端，监控错误率
```

验证矩阵：
```
API Endpoint        Old (ms)  New (ms)  Match  Status
────────────────────────────────────────────────────
GET  /api/users      45        12        ✓      PASS
GET  /api/orders     120       28        ✓      PASS
POST /api/orders     200       45        ✗      DIFF (price rounding)
GET  /api/products   80        18        ✓      PASS
```

## Skill 体系

### 复用现有 4 个 skills + 新增 3 个

| Skill | 类型 | 触发时机 |
|-------|------|----------|
| `zigmodu-project` | 现有 | 探索项目结构 |
| `zigmodu-module` | 现有 | 创建新模块 |
| `zigmodu-api` | 现有 | 添加 API 端点 |
| `zigmodu-orm` | 现有 | SQL → ORM 生成 |
| **`zigmodu-analyze`** | **新增** | 分析 Java/PHP 源项目 |
| **`zigmodu-translate`** | **新增** | 翻译业务逻辑 |
| **`zigmodu-harness`** | **新增** | 运行验证对比 |

### Skill: zigmodu-analyze

分析 Spring Boot / Laravel 项目，提取结构化画像。

Phase 1 触发：分析项目结构、提取 Schema、列出 API

### Skill: zigmodu-translate

将 Java/PHP 代码翻译为 Zig。包含：
- 类型映射表
- 常见模式转换规则
- 置信度标记（AUTO/REVIEW/MANUAL）

Phase 3 触发：逐个文件翻译

### Skill: zigmodu-harness

运行验证流程：
- Diff 服务器启动
- Schema 对比
- API 响应对比
- 性能基准

Phase 4 触发：验证和切流

## zmodu 命令扩展

```bash
# 新命令
zmodu analyze  --source java|php --input <dir>     # 项目分析
zmodu harness  --analysis analysis.json            # 完整迁移
zmodu translate --source <file> --output <file>     # 单文件翻译
zmodu verify   --old <url> --new <url>              # 对比验证

# 快捷命令
zmodu migrate  --source java --input ./old/ --output ./new/
# = analyze + harness + verify (一键迁移)
```

## 迁移检查清单

```
Phase 1: Analyze
□ 数据库表结构完整提取（表数、列数、FK 关系）
□ API 端点无遗漏（路径、方法、参数、响应格式）
□ 中间件链完整记录
□ 认证/授权机制识别
□ 定时任务/队列消费者清单
□ 第三方服务依赖清单

Phase 2: Scaffold
□ zig build 编译通过
□ 所有表生成 model + persistence + service + api
□ 路由路径与原始 API 一致
□ 中间件织入正确
□ 配置项映射到 .env.example
□ AGENTS.md 生成

Phase 3: Translate
□ 所有文件编译通过
□ 业务规则翻译正确（人工抽查）
□ 事务边界保留
□ 缓存策略迁移
□ 事件/消息队列适配
□ 错误码映射表更新

Phase 4: Verify
□ Schema diff 通过
□ Top 20 API 端点对比一致
□ 性能不低于原项目 50%
□ 灰度 1% 流量无错误
□ 内存/CPU 基线建立
```

## 版本

- zmodu target: v0.10.0 (migration harness feature)
- zigmodu: v0.9.5+
- Zig: 0.16.0
