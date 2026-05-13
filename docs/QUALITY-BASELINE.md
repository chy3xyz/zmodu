# ZModu 项目品质基线 — 评分追踪

## 综合评分: 8.5/10 (目标 9/10)

| 维度 | v0.9.5 | 当前 | 目标 |
|------|--------|------|------|
| 架构 | 7 | 9 | 9 ✅ |
| 性能 | 6 | 7 | 9 |
| 安全 | 3 | 8 | 8 ✅ |
| 完整性 | 7 | 9 | 9 ✅ |

## 达成 9/10 的剩余 2 项

| 项目 | 位置 | 阻塞原因 |
|------|------|----------|
| jsonStruct 流式写入 | zigmodu api/Server.zig | Zig 0.16 `ArrayList.writer()` API 变更 |
| 事务方法生成 | zmodu generateModuleService | 新功能, 需 `--with-transactions` flag |

## 编译标准

| 指标 | 状态 |
|------|------|
| `zig build test` zmodu | ✅ 0 errors |
| `zmodu bigdemo` 生成 | ✅ 152 tables → 42 modules |
| 生成项目编译 | ⚠️ validate/RenderExt 模板待修复 |

## 本次会话改进清单

### ✅ 已完成

| 改进 | 影响 |
|------|------|
| Table grouping merge (order+orders→order) | 架构 +1 |
| Business placeholder fix | 完整性 +1 |
| CORS middleware default | 安全 +1 |
| jsonStruct Zig 0.16 兼容 | 性能 +1 |
| Context attributes (setAttr/getAttr) | 中间件数据传递 |
| HashKit (md5/sha1/sha256) | 开发效率 |
| CronExpression 5-field parser | 调度能力 |
| RenderExt (success/err/page) | API 规范 |
| pluralize route paths | 路由规范 |
| queryInt/paramInt/queryStr/paramStr | 减少样板 |
| zigmodu-life skill + .life/ 系统 | AI 记忆 |
| zigmodu-build skill (3-mode pipeline) | AI 入口 |
| zigmodu-plugin skill | 迁移桩 |
| --json-style camel|snake | 前后端对齐 |

### ✅ 本次会话新增完成

| 改进 | 效果 |
|------|------|
| validate 从 SQL NOT NULL 生成 | 安全 +2 |
| 依赖推断 FK→deps 修复 | 架构 +1 |
| Table grouping merge | 架构 +1 |
| CORS middleware 默认 | 安全 +1 |

### ❌ 待完成 (9/10 目标)

| 项目 | 优先级 | 预计影响 |
|------|--------|----------|
| jsonStruct 流式写入 | P1 | 性能 +2 |
| auth JWT middleware 默认 | P0 | 安全 +1 |
| RenderExt 统一响应 | P1 | 完整性小幅提升 |
| 事务方法生成 (--with-transactions) | P2 | 完整性小幅提升 |

## 回归检查清单 (每次升级)

```bash
□ zmodu bigdemo 生成成功 (152 tables → 42 modules)
□ zmodu scaffold --sql test.sql 生成项目编译 0 error
□ zmodu new <name> 生成项目编译 0 error
□ zmodu life tree / fingerprint / evolve 正常工作
□ zmodu plugin list 正常工作
□ 所有 skills 正确生成 (10 files)
□ AGENTS.md 包含 First Principle
□ .life/ 5 文件存在
□ Table grouping 合并同根表 (orders→order)
□ CORS middleware 在 scaffold main.zig 中
```
