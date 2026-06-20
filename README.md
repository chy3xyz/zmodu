# zmodu v0.15.0

Code generation CLI for [zigmodu](https://github.com/chy3xyz/zigmodu). Modulith architecture scaffolding with AI-assisted development via MCP protocol. Zig 0.17+.

## Install

```bash
git clone https://github.com/chy3xyz/zmodu.git && cd zmodu && zig build
```

## Quick Start

```bash
zmodu scaffold --sql schema.sql --name myapp
cd myapp && zig build run
```

## Commands

```bash
zmodu scaffold --sql <file> --name <n>   # SQL → full project [primary]
zmodu scaffold --from-db <dsn> --name <n> # Introspect live database
zmodu orm --sql <file> [--out <dir>]      # ORM modules only
zmodu module <name>                        # empty module skeleton
zmodu api <name>                           # standalone API template
zmodu event <name>                         # event handler template
zmodu verify [dir]                         # verify project compiles + structure
zmodu diff <old.sql> <new.sql>             # compare SQL schemas (table-level)
zmodu mcp                                  # start MCP server (AI agent integration)
zmodu plugin stub --name <n>              # dependency stub for migration
zmodu life                                 # project evolutionary memory
```

## MCP Integration

AI agents (Kimi, Claude, etc.) can call zmodu directly via MCP protocol:

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

Available tools: `zmodu_scaffold`, `zmodu_module`, `zmodu_version`, `zmodu_verify`, `zmodu_diff`.

## Scaffold Flags

```
--sql <file>          --name <name>         required
--from-db <dsn>       --out <dir>          optional
--json-style camel    --force --dry-run

Features:
--with-events         EventBus publish on CUD ops
--with-auth           JWT authentication
--with-resilience     CircuitBreaker + RateLimiter
--with-metrics        Prometheus /metrics
--with-transactions   SagaOrchestrator
--with-redis          Redis cache layer
--with-websocket      IM real-time messaging
--with-aichat         AI Chat (multi-turn LLM)
--with-agent          AI Agent (ReAct + SkillRegistry)
--with-web4           DID + x402 payment
```

## Generated Project

```
src/
├── main.zig              # DB dispatch + module wiring + providers
├── shared/
│   ├── types.zig        # cross-module types
│   ├── errors.zig       # AppError + BizCode enum
│   ├── events.zig       # EventBus catalog (--with-events)
│   └── response.zig     # wrapOk/wrapErr/wrapList + BizCode
├── business/root.zig
└── modules/<name>/
    ├── module.zig         # lifecycle + barrel re-exports
    ├── model.zig          # struct(sql_table_name) + `= null`
    ├── persistence.zig    # ORM Repository(T)
    ├── service.zig        # CRUD + validation + EventBus + tenant
    └── api.zig            # REST handlers + {id} routes + resolve()
```

## @initialized Model

All files use `//! @initialized by zmodu — AI may modify freely`. No `ext/` directory. AI edits generated files directly. Re-scaffold with `--force` to overwrite; omit for `.gen.new` diff.

## Key Patterns

**Tenant isolation**: tables with `tenant_id` column auto-generate `listByTenant(page, size, tenant_id)` and `getByTenant(id, tenant_id)`.

**EventBus**: `--with-events` generates typed event catalog + `publish(.XXXCreated/Updated/Deleted)` on create/update/delete.

**Typed errors**: `BizCode` enum replaces magic numbers — `wrapErr(ctx, .not_found, "msg")`.

**Validation**: email format check, numeric range for price/amount/stock, enum TODO for status/role/type.

**AI Chat** (`--with-aichat`): multi-turn context, cache-optimized messages, SSE streaming, cross-session MemoryStore.

**Router**: Radix-tree with `{param}`, `*` wildcard, path rewriter callback.

## Development

```bash
zig build && zig build test
```

## License

MIT
