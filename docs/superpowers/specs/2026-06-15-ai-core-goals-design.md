# zmodu AI-First 核心目标设计

> **日期**: 2026-06-15
> **状态**: 待审批
> **范围**: P0 — AI 核心能力 (MCP Server + verify + 增量生成)
> **当前评分**: 80.25/100 | **目标评分**: 90/100

---

## 1. 背景与动机

### 1.1 当前状态

zmodu (v0.14.9) 是一个高完成度的代码生成器：
- 核心代码生成: **88/100** — 152 表 → 43 模块 → 341 文件，全量 scaffold 验证通过
- AI 集成: **75/100** — 有 Prompt 模板和文档，但 AI 无法程序化调用 zmodu

### 1.2 核心矛盾

zmodu 的第一性原理是 *"生成一切可生成的；AI 只写无法生成的部分"*，但当前 AI 的集成停留在**文档/Prompt 层面**——AI agent 无法通过协议直接调用 `zmodu scaffold`、无法验证生成结果、无法增量更新。

### 1.3 文件边界现状

经过代码验证，当前实际的文件边界模型是 **"AI 直接修改生成文件"**：
- `src/main.zig` 中 ext 文件生成已被 `if (false)` 禁用
- 生成的 `api.zig` / `service.zig` 不引用任何 ext 文件
- `shopdemo` 中的 `*_ext.zig` 是历史残留的孤儿文件
- 文档 (`ZMODU-FIRST-PRINCIPLE.md`, `AGENTS.md`) 仍描述旧的 ext 模型，需要更新

---

## 2. 目标总览

### 2.1 总目标

将 zmodu 从 "有 AI 文档的代码生成器" 升级为 **"AI agent 可直接调用的代码生成框架"**。

### 2.2 量化指标

| 维度 | 当前 | 目标 | 变化 |
|------|------|------|------|
| AI 集成评分 | 75 | **92** | +17 |
| 核心生成 | 88 | **90** | +2 |
| 架构 | 82 | **82** | 不变 |
| 性能 | 85 | **85** | 不变 |
| 安全 | 78 | **78** | 不变 |
| 生态 | 70 | **72** | +2 |
| **总分** | **80.25** | **~90** | +9.75 |

### 2.3 三阶段交付物

| 阶段 | 交付物 | 成功标准 |
|------|--------|----------|
| P1: MCP Server | `zmodu mcp` 命令 + MCP tools | AI agent 通过 MCP 协议调用 scaffold/orm/module/version 成功生成项目 |
| P2: Verify | `zmodu verify` 命令 + MCP tool | scaffold 后自动编译 + 返回结构化 JSON 报告 (pass/fail + 错误定位) |
| P3: 增量生成 | SQL diff + 增量 scaffold | 修改 SQL 中一个表 → 只重新生成该模块，AI 的修改不被覆盖 |

### 2.4 端到端验收场景

```
用户: "用这个 SQL 建一个电商后端"
  → AI → MCP → zmodu scaffold (全量生成 43 模块)
  → AI → MCP → zmodu verify (自动验证，返回 pass)

用户: "给 orders 表加一个 discount 字段"
  → AI → MCP → zmodu scaffold --diff old.sql (增量生成，只更新 order 模块)
  → AI → MCP → zmodu verify (验证通过，AI 修改的文件未被覆盖)
```

---

## 3. P1: MCP Server (`zmodu mcp`)

### 3.1 什么是 MCP

MCP (Model Context Protocol) 是 AI tool 调用的开放协议。MCP Server 暴露若干 tools，AI agent 通过 JSON-RPC 2.0 over stdio 调用。

### 3.2 架构

```
┌─────────────┐    JSON-RPC (stdio)    ┌──────────────┐
│  AI Agent   │ ◄────────────────────► │  zmodu mcp   │
│ (Kimi/      │                        │              │
│  Claude)    │                        │  MCP Server  │
└─────────────┘                        └──────┬───────┘
                                              │
                                     ┌────────▼────────┐
                                     │  现有 CLI 命令   │
                                     │  scaffold/orm/  │
                                     │  module/verify  │
                                     └─────────────────┘
```

**关键原则**: MCP Server 是现有 CLI 命令的**薄包装层**，不重新实现业务逻辑。每个 MCP tool 内部调用已有的命令函数。

### 3.3 暴露的 Tools

| Tool 名 | 参数 | 返回值 | 对应 CLI |
|---------|------|--------|---------|
| `zmodu_scaffold` | `sql_path: string, output_dir: string, orm_backend?: "sqlx"\|"zent"` | `{ success, modules[], files_created, errors[] }` | `zmodu scaffold` |
| `zmodu_orm` | `sql_path: string, module_name: string, backend?: "sqlx"\|"zent"` | `{ success, files[], errors[] }` | `zmodu orm` |
| `zmodu_module` | `name: string, output_dir?: string` | `{ success, files[] }` | `zmodu module` |
| `zmodu_verify` | `project_dir: string` | `{ pass, errors: VerifyError[], warnings[] }` | `zmodu verify` (P2) |
| `zmodu_version` | 无 | `{ version, zig_version }` | `zmodu version` |
| `zmodu_diff` | `old_sql: string, new_sql: string` | `{ changed_tables: TableDiff[] }` | `zmodu diff` (P3) |

### 3.4 MCP 协议实现

**传输层**: stdio (MCP 标准传输)

**协议层**: JSON-RPC 2.0，核心流程:
1. `stdin` 读 JSON-RPC request
2. 解析 `method` + `params`
3. 路由到对应 CLI 命令函数
4. 捕获输出 → 结构化 JSON response
5. `stdout` 写 JSON-RPC response

**MCP 初始化握手**:
- `initialize` → 返回 server info + capabilities
- `tools/list` → 返回所有 tool 的 JSON Schema 定义
- `tools/call` → 执行具体 tool

### 3.5 新增文件

| 文件 | 职责 |
|------|------|
| `src/mcp_server.zig` | MCP 协议处理 + tool 注册 + request dispatch |
| `src/mcp_types.zig` | JSON-RPC 2.0 + MCP 协议类型定义 |

**main.zig 改动**: 新增 `mcp` 子命令，调用 `mcp_server.start(allocator)`.

### 3.6 AI Agent 接入

AI agent 配置文件添加:

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

添加后 AI agent 即可发现并调用所有 zmodu tools。

---

## 4. P2: `zmodu verify`

### 4.1 检查项

| 检查 | 说明 | 级别 |
|------|------|------|
| **编译通过** | `zig build` 返回 0 errors | P0 必须 |
| **编译警告** | `zig build` warnings 列表 | P1 报告 |
| **模块完整性** | 每个模块是否有 model/persistence/service/api/module/root 6 文件 | P0 必须 |
| **import 一致性** | 所有 `@import` 的文件是否存在 | P0 必须 |
| **表→模块映射** | SQL 中的表是否都有对应模块 (可选，需传入 SQL 路径) | P1 报告 |

### 4.2 输出格式

```json
{
  "pass": true,
  "checks": [
    { "name": "compile", "status": "pass", "duration_ms": 3200 },
    { "name": "module_integrity", "status": "pass", "modules_checked": 43 },
    { "name": "import_consistency", "status": "warn", "missing": ["shared/cache.zig"] }
  ],
  "errors": [],
  "warnings": ["shared/cache.zig not found"],
  "summary": "3 checks: 2 pass, 1 warn, 0 fail"
}
```

status 取值: `"pass"` | `"fail"` | `"warn"` | `"skip"` (依赖未满足时)

### 4.3 实现

**新增文件**: `src/verify.zig` — verify 逻辑

**编译检查实现**: 调用 `zig build` 子进程，捕获 stdout/stderr，解析错误/警告。

**模块完整性实现**: 扫描 `src/modules/` 目录，检查每个子目录是否包含必需的 6 个文件。

**import 一致性实现**: 正则扫描所有 `.zig` 文件中的 `@import("...")`，检查引用的文件是否存在。

### 4.4 MCP 集成

verify 作为 `zmodu_verify` tool 暴露。AI 可在 scaffold 后自动调用 verify，根据结果决定是否修复后重试。

---

## 5. P3: 增量生成 (`zmodu scaffold --diff`)

### 5.1 核心问题

当前 `zmodu scaffold` 是全量生成。在 "AI 直接改" 模型下，全量生成会覆盖 AI 的工作。

### 5.2 SQL Diff 引擎

**输入**: old SQL 文件路径 + new SQL 文件路径

**处理**:
1. 两个 SQL 文件各自通过 `parseSqlSchema()` 得到 `TableDef[]`
2. 按表名匹配，计算 diff:
   - 新表 → `added`
   - 删除的表 → `removed`
   - 字段变化的表 → `modified` (含 column_changes 详情)
3. 输出 `TableDiff[]`

**TableDiff 结构**:
```zig
const TableDiff = struct {
    table_name: []const u8,
    change_type: enum { added, removed, modified },
    column_changes: []ColumnChange, // only for modified
};

const ColumnChange = struct {
    column_name: []const u8,
    change_type: enum { added, removed, type_changed },
    old_type: ?[]const u8,
    new_type: ?[]const u8,
};
```

### 5.3 增量 Scaffold

```
for each TableDiff:
  if added    → 全量生成新模块 (6 文件)
  if removed  → 仅报告，不删除 (安全优先)
  if modified → 重新生成该模块，但逐文件检查:
    磁盘文件 SHA256 == generated_hashes.json 中的记录
      → 文件未被 AI 改过 → 安全覆盖
    磁盘文件 SHA256 != 记录
      → AI 改过 → 跳过 + 报告冲突
```

### 5.4 Hash 追踪文件

**位置**: `<project>/.zmodu/generated_hashes.json`

每次 scaffold (全量或增量) 完成后写入:

```json
{
  "generated_at": "2026-06-15T10:00:00Z",
  "zmodu_version": "0.14.9",
  "files": {
    "src/modules/order/service.zig": "sha256:abc123...",
    "src/modules/order/api.zig": "sha256:def456..."
  }
}
```

**SHA256 计算时机**: 写入文件后立即计算，确保记录的是"生成时的原始内容"。

### 5.5 冲突报告

```json
{
  "regenerated": ["order", "product"],
  "skipped_conflict": ["user/service.zig"],
  "added": ["discount"],
  "not_deleted": ["legacy_table"]
}
```

### 5.6 MCP 集成

`zmodu_diff` tool 返回 TableDiff 列表，AI 可先查看变更再决定是否执行增量 scaffold。
`scaffold --diff` 的冲突报告也通过 MCP 返回，AI 可逐个处理冲突文件。

### 5.7 新增文件

| 文件 | 职责 |
|------|------|
| `src/sql_diff.zig` | SQL AST diff 引擎 |
| `src/incremental.zig` | 增量 scaffold 逻辑 + hash 追踪 |

---

## 6. 附带工作: 文档清理

在 P0 开发过程中同步修复过时文档:

| 文件 | 清理内容 |
|------|----------|
| `docs/ZMODU-FIRST-PRINCIPLE.md` | 移除 ext 文件边界描述，更新为 "AI 直接修改" 模型；加入 MCP 调用方式 |
| `shopdemo/AGENTS.md` | 更新 "Safe to edit" 列表，移除 ext 引用，加入 MCP 工作流 |
| `docs/AI-DEVELOP-PROMPT.md` | 更新 AI 工作流，加入 MCP 调用方式 |
| `docs/AI-MIGRATION-PROMPT.md` | 加入 MCP 调用方式 |

---

## 7. 阶段依赖与执行顺序

```
P1: MCP Server ──────► P2: verify (MCP tool) ──────► P3: 增量生成 (MCP tool)
    │                        │                              │
    ▼                        ▼                              ▼
  AI 可调用 zmodu      AI 可验证结果               AI 可增量更新不丢工作
```

三个阶段**严格串行**: P2 和 P3 都依赖 P1 的 MCP 基础设施。

---

## 8. 风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| MCP 协议实现复杂度 | 中 | P1 延期 | 先实现最小 viable MCP (仅 initialize + tools/list + tools/call)，后续扩展 |
| SQL diff 引擎遗漏边缘情况 | 中 | P3 不准确 | 先支持 ADD COLUMN / MODIFY COLUMN，逐步覆盖 RENAME / DROP |
| zig build 子进程调用在 verify 中超时 | 低 | P2 体验差 | 设置超时 (60s)，超时返回 partial 结果 |
| generated_hashes.json 被 .gitignore 排除 | 低 | 增量失效 | 明确文档说明不应忽略此文件 |

---

## 9. 不在范围内

以下内容**明确不在本次目标范围内**:

- 拆分 main.zig (P1 架构改进，后续跟进)
- 真实测试覆盖 (P1，后续跟进)
- npm/CLI 版本同步 (P1，后续跟进)
- 独立文档站 (P2)
- `zmodu doctor` (P2)
- PostgreSQL/SQLite DDL 语法 (P2)
- 插件系统激活 (P2)
- 自然语言→SQL (远期)
