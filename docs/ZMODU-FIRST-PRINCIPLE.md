# ZModu 第一性原理 — AI 编程体系

## 核心原则

> **zmodu 生成所有能生成的，AI 只编写 zmodu 无法生成的。**

```
                     ┌──────────────────────────────────────┐
                     │        zmodu 代码生成边界            │
                     │                                      │
  输入 ──► zmodu 生成 ──► AI 补足 ──► zmodu 校验 ──► 完成  │
                     │                                      │
                     └──────────────────────────────────────┘
```

## 三种模式，一条管线

```
模式 1: 原始需求 (Greenfield)
  需求描述 → 数据库建模 → zmodu orm → 编译通过 → AI 补业务逻辑

模式 2: 已有 SQL (Brownfield)
  schema.sql → zmodu scaffold → 编译通过 → AI 补业务逻辑

模式 3: 参考项目 (Migration)
  Java/PHP/Go/Rust → zmodu analyze → zmodu harness → AI 翻译差异
```

## zmodu 生成能力清单

| ✅ zmodu 自动生成 | ❌ AI 需要补足 |
|-------------------|---------------|
| model.zig (表→struct) | 复杂业务规则 |
| persistence.zig (ORM repo) | 第三方 API 集成 |
| service.zig (CRUD 方法) | 事务编排 (Saga) |
| api.zig (REST 路由+handler) | 自定义查询 (JOIN/聚合) |
| module.zig (声明+生命周期) | 权限校验逻辑 |
| root.zig (barrel 导出) | 文件上传/导出 |
| main.zig (DI 织入) | 定时任务逻辑 |
| build.zig + build.zig.zon | 前端模板渲染 |
| AGENTS.md + .claude/skills/ | 特定中间件适配 |
| .env.example | 遗留系统兼容层 |

## 管线流程

### 模式 1: 原始需求

```
Step 1: 需求 → 数据库建模
  输入: 需求文档/描述
  工具: AI 辅助设计表结构
  输出: schema.sql

Step 2: schema.sql → zmodu 全量生成
  zmodu scaffold --sql schema.sql --name <project>
  输出: 完整项目 (0 编译错误)

Step 3: 编译验证
  cd <project> && zig build
  预期: 0 errors

Step 4: AI 补足业务逻辑
  AI 直接修改生成文件，添加自定义业务逻辑
  重新生成时: zmodu 使用 SHA256 哈希追踪，检测 AI 修改并跳过已变更的文件

Step 5: 再次验证
  zig build test
  zmodu verify (对比原始需求)
```

### 模式 2: 已有 SQL

```
Step 1: 确认 SQL 文件
  检查: 表结构完整性、FK 关系、索引
  工具: grep "CREATE TABLE\|FOREIGN KEY" schema.sql

Step 2: zmodu 全量生成
  zmodu scaffold --sql schema.sql --name <project> \
    --with-events --with-resilience --with-metrics

Step 3: 编译验证
  cd <project> && zig build

Step 4: AI 补足
  分析: 哪些表有关联查询需要自定义 JOIN
  原则: AI 直接修改生成文件，zmodu 使用哈希追踪保护已修改文件

Step 5: 验证
  zig build test
```

### 模式 3: 参考项目迁移

```
Step 1: 源项目分析
  zmodu analyze --source java|php|go|rust --input ./legacy/
  输出: analysis.json + schema.sql + routes.json

Step 2: zmodu 全量生成
  zmodu harness --analysis analysis.json
  生成: schema → 模块, routes → API 路径匹配

Step 3: 编译验证
  cd <project> && zig build

Step 4: AI 差异翻译
  对比: 原项目 API 响应 vs 新项目 API 响应
  标记: [AUTO] 自动翻译 / [REVIEW] 需人工 / [MANUAL] 重写

Step 5: Harness 验证
  zmodu verify --old :8080 --new :8081
  检查: Schema diff, API response diff, Performance baseline
```

## 文件边界

```
AI 直接修改生成文件。当重新生成时，zmodu 使用 SHA256 哈希追踪检测 AI 修改并跳过已变更的文件。
```

### 生成的文件（AI 可直接修改，重新生成时受哈希保护）

```
src/modules/<name>/model.zig         # 表→struct
src/modules/<name>/persistence.zig   # ORM repo
src/modules/<name>/service.zig       # CRUD 方法
src/modules/<name>/api.zig           # REST 路由+handler
src/modules/<name>/module.zig        # 声明+生命周期
src/modules/<name>/root.zig          # barrel 导出
src/main.zig                         # DI 织入
build.zig / build.zig.zon            # 构建配置
```

### AI 自主创建的文件

```
src/business/                         # 跨模块业务逻辑
src/compat/                           # 兼容层 (迁移模式)
tests/                                # 测试文件
```

## 验证体系

```
每次代码变更后运行:

1. 编译验证:   zig build           (必须 0 error)
2. 测试验证:   zig build test      (必须全通过)
3. API 验证:   zmodu verify        (对比预期响应)
4. Schema 验证: zmodu verify --schema  (对比原始 DDL)
5. 增量更新:   zmodu diff old.sql new.sql  (SQL diff 分析)
6. 目录验证:   zmodu verify [dir]  (验证项目完整性)
```

## MCP 集成

`zmodu mcp` 启动 MCP Server，供 AI Agent 集成使用。

### 可用工具

| 工具 | 功能 |
|------|------|
| zmodu_scaffold | 从 SQL 生成项目骨架 |
| zmodu_module | 添加新模块 |
| zmodu_version | 获取 zmodu 版本信息 |
| zmodu_verify | 验证项目完整性 |
| zmodu_diff | SQL diff 分析 |

### AI Agent 配置

```json
{
  "mcpServers": {
    "zmodu": {
      "command": "zmodu",
      "args": ["mcp"]
    }
  }
}
```

## 效能指标

```
目标: zmodu 生成 > 80% 代码, AI 补足 < 20%

Greenfield:  90% 生成 + 10% AI (业务逻辑)
Brownfield:  85% 生成 + 15% AI (自定义查询)
Migration:   70% 生成 + 30% AI (差异翻译)
```
