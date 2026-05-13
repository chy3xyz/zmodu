---
name: zigmodu-build
description: Build complete ZigModu backend — greenfield, from SQL, or from legacy Java/PHP/Go/Rust. zmodu generates everything possible, AI only fills what zmodu cannot generate. Always start here.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# ZigModu Build — 第一性原理

**zmodu 生成所有能生成的，AI 只编写 zmodu 无法生成的。**

## 模式选择

```
有数据库 SQL 脚本？
  ├─ YES → 模式 2: Brownfield (已有 SQL)
  └─ NO  → 有参考项目 (Java/PHP/Go/Rust)？
            ├─ YES → 模式 3: Migration (参考项目)
            └─ NO  → 模式 1: Greenfield (原始需求)
```

## 模式 1: 原始需求 (Greenfield)

没有 SQL，没有参考代码。从需求到完整项目。

```bash
# Step 1: 数据库建模 (AI 辅助)
# 根据需求描述，设计 CREATE TABLE 语句
# 输出: schema.sql

# Step 2: zmodu 全量生成
zmodu scaffold --sql schema.sql --name <project> \
  --with-events --with-resilience --with-metrics

# Step 3: 编译验证 (必须 0 error)
cd <project> && zig build

# Step 4: AI 补足
# - 业务规则 → src/modules/<name>/service_ext.zig
# - 自定义端点 → src/modules/<name>/api_ext.zig
# - 跨模块逻辑 → src/business/
# - 原则: 只写 _ext 文件，不修改 zmodu 生成的文件

# Step 5: 验证
zig build test
```

## 模式 2: 已有 SQL (Brownfield)

有建表脚本，直接生成完整项目。

```bash
# Step 1: 确认 SQL 完整性
grep -c "CREATE TABLE" schema.sql  # 表数量
grep -c "FOREIGN KEY" schema.sql  # FK 关系数

# Step 2: zmodu 全量生成
zmodu scaffold --sql schema.sql --name <project> \
  --with-events --with-resilience --with-metrics --with-auth

# Step 3: 编译验证
cd <project> && zig build

# Step 4: AI 分析并补足
# - 检查: 哪些表需要 JOIN 查询？→ 自定义 Repository 方法
# - 检查: 哪些端点需要权限？→ 添加 auth 中间件
# - 检查: 哪些操作需要事务？→ SagaOrchestrator
# - 原则: 优先扩展 service.zig，通过 _ext 文件添加

# Step 5: 验证
zig build test
```

## 模式 3: 参考项目迁移 (Migration)

有 Java/PHP/Go/Rust 项目，完整迁移。

```bash
# Step 1: 分析源项目
# Java Spring Boot:
find src/main/java -name "*.java" | head -20
grep -rn "@Entity\|@Table" src/main/java -l
grep -rn "@GetMapping\|@PostMapping" src/main/java -A2

# Laravel:
php artisan route:list --json
php artisan schema:dump

# Go:
grep -rn "func.*Handler\|router\." --include="*.go" -l

# Rust (Actix/Rocket):
grep -rn "#\[get\|#\[post" --include="*.rs" -l

# Step 2: 提取 SQL
# 从 ORM entity/migration/model 文件提取 CREATE TABLE DDL
# 输出: schema.sql

# Step 3: 提取 API 路由
# 从 Controller/Handler 提取路由清单
# 输出: routes.json (method, path, params, response)

# Step 4: zmodu 全量生成
zmodu scaffold --sql schema.sql --name <project>

# Step 5: 路径匹配 (保持 API 兼容)
# 修改生成的路由，匹配原始 API 路径
# 修改 api.zig 中的 registerRoutes()

# Step 6: 编译验证
cd <project> && zig build

# Step 7: AI 翻译差异
# 对比原项目响应 vs 新项目响应
# 标记: [AUTO] 直接翻译 / [REVIEW] 需确认 / [MANUAL] 重写
# 写入: src/modules/<name>/service_ext.zig

# Step 8: Harness 验证
zmodu verify --old http://localhost:8080 --new http://localhost:8081
```

## AI 编辑边界

### ✅ 可以编辑 (不会被 zmodu regenerate 覆盖)

```
src/modules/<name>/service_ext.zig   # 自定义业务逻辑
src/modules/<name>/api_ext.zig       # 自定义 API 端点
src/business/                         # 跨模块逻辑
src/compat/                           # 兼容层 (迁移模式)
tests/                                # 测试文件
.env.example                          # 环境变量
AGENTS.md                             # AI 开发指南
```

### ❌ 绝对不能编辑 (zmodu regenerate 会覆盖)

```
src/modules/<name>/model.zig         # zmodu 生成 (表→struct)
src/modules/<name>/persistence.zig   # zmodu 生成 (ORM repo)
src/modules/<name>/service.zig       # zmodu 生成 (CRUD)
src/modules/<name>/api.zig           # zmodu 生成 (REST handlers)
src/modules/<name>/module.zig        # zmodu 生成 (声明)
src/modules/<name>/root.zig          # zmodu 生成 (导出)
src/main.zig                         # zmodu 生成 (织入)
build.zig / build.zig.zon            # zmodu 生成 (构建)
```

## 验证检查清单

```bash
# 每次 AI 修改后运行
zig build              # 必须 0 error
zig build test         # 必须全通过

# Schema 变更后
zmodu scaffold --sql schema.sql --name <project> --force --dry-run
# 对比差异，确认生成文件变化

# API 变更后 (迁移模式)
zmodu verify --old :8080 --new :8081
```

## 效能指标

```
Greenfield:  zmodu 生成 90% + AI 补 10% (业务规则)
Brownfield:  zmodu 生成 85% + AI 补 15% (JOIN/聚合)
Migration:   zmodu 生成 70% + AI 补 30% (差异翻译+兼容层)
```
