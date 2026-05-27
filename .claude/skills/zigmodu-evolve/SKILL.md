---
name: zigmodu-evolve
description: Self-evolving development skill — captures lessons learned and applies them to zigmodu/zmodu upgrades. Run before any code change to check known pitfalls.
---

# ZigModu Evolve — Self-Improving Development Guide

## When to Use

ALWAYS run before making changes to zigmodu or zmodu. This skill captures cumulative development experience and prevents repeating known mistakes.

## Quick Pre-Flight Checklist

```bash
# Before ANY code change:
zig build                    # Must pass (0 errors)

# Zig 0.17 checks:
grep -rn '\*\*' src/ --include="*.zig" | grep -v '//'  # Array mult removed → use @splat
grep -rn '\.dupeZ(' src/ --include="*.zig"              # dupeZ removed → use allocSentinel
grep -rn 'bufPrintZ' src/ --include="*.zig"             # bufPrintZ removed → use bufPrint + sentinel
grep -rn '@cImport' src/ --include="*.zig"              # @cImport removed → use addTranslateC

# Zig 0.16 checks (still relevant for legacy code):
grep -rn "ArrayList.*\.init(" src/ | grep -v test
grep -rn "\.writeAll(" src/ | grep -v test | grep -v interface
grep -rn "std\.time\.timestamp\|nanoTimestamp" src/ | grep -v test
grep -rn "std\.fs\.accessAbsolute\|std\.fs\.cwd" src/ | grep -v test
grep -rn "\.toOwnedSlice()" src/ | grep -v test | grep -v allocator
```

## Zig 0.17 Migration Patterns (Added 2026-05-27)

### Array Multiplication `**` — REMOVED, use `@splat()`

```zig
// ❌ Zig 0.16 — REMOVED in 0.17
const arr: [32]u8 = [_]u8{0} ** 32;
const flags: [60]bool = [_]bool{false} ** 60;
const nils: [10]?usize = [_]?usize{null} ** 10;

// ✅ Zig 0.17
const arr: [32]u8 = @splat(0);
const flags: [60]bool = @splat(false);
const nils: [10]?usize = @splat(@as(?usize, null));

// @splat works with runtime expressions:
const v: [10]u16 = @splat(someFn());
// Multi-dimensional:
const grid: [4][5]f32 = @splat(@splat(0));
```

### allocator.dupeZ — REMOVED, use allocSentinel + @memcpy

```zig
// ❌ Zig 0.16 — REMOVED in 0.17
const c_str = try allocator.dupeZ(u8, s);
const c_str2 = allocator.dupeZ(u8, path) catch return error.Fail;

// ✅ Zig 0.17 — helper pattern
fn allocZ(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const result = try allocator.allocSentinel(u8, s.len, 0);
    @memcpy(result, s);
    return result;
}
const c_str = try allocZ(allocator, s);

// allocSentinel returns [:0]T — sentinel is at [len], not included in .len
// Data is uninitialized before @memcpy — MUST copy source data
```

### std.fmt.bufPrintZ — REMOVED, use bufPrint + manual sentinel

```zig
// ❌ Zig 0.16 — REMOVED in 0.17
const port_str = try std.fmt.bufPrintZ(buf, "{d}", .{port});

// ✅ Zig 0.17 — helper pattern
fn bufPrintZ(buf: []u8, comptime fmt: []const u8, args: anytype) ![:0]u8 {
    const written = try std.fmt.bufPrint(buf, fmt, args);
    buf[written.len] = 0;
    return buf[0..written.len :0];
}
const port_str = try bufPrintZ(&buf, "{d}", .{port});
```

### Uri.Component — no longer coerces to []const u8

```zig
// ❌ Zig 0.16 — direct coercion worked
const host = parsed_url.host orelse return error.Invalid;
try something(host, port); // host used as []const u8

// ✅ Zig 0.17 — must extract raw string
const host_component = parsed_url.host orelse return error.Invalid;
var host_buf: [256]u8 = undefined;
const host = host_component.toRaw(&host_buf) catch return error.Invalid;
try something(host, port);

// Same pattern for .path, .query, .fragment
```

### @cImport — REMOVED, use build.zig addTranslateC

```zig
// ❌ Zig 0.16
const c = @cImport({ @cInclude("sqlite3.h"); });

// ✅ Zig 0.17 — in build.zig:
const translate_c = b.addTranslateC(.{
    .root_source_file = b.path("c/sqlite3.h"),
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("sqlite3_c", translate_c.createModule());
```

### ** Whitespace Rule — symmetric whitespace required

```zig
// ❌ Zig 0.17 — asymmetric whitespace on ** operator
const x = a ** b;   // ERROR if one side has whitespace and other doesn't
const y = a**b;     // OK — symmetric (no whitespace either side)
const z = a ** b;   // OK — symmetric (whitespace both sides)
```

## Zig 0.16 Migration Patterns (Still Relevant)

### ArrayList API — VERIFIED against Zig 0.16 source
`.empty` is the only universal creation method. All mutations need explicit gpa.

```zig
// ❌ Zig 0.15 — ALL removed in 0.16+
var list = std.ArrayList(u8).init(allocator);
list.append(item);
list.deinit();
list.toOwnedSlice();

// ✅ Zig 0.16/0.17 — definitive pattern
var list = std.ArrayList(u8).empty;
defer list.deinit(allocator);
try list.append(allocator, item);
try list.insert(allocator, 0, item);
return list.toOwnedSlice(allocator);

// Struct field initialization
.{ .field = std.ArrayList(T).empty, }

// initCapacity: pre-allocates but still needs explicit gpa
var list = try std.ArrayList(T).initCapacity(gpa, 10);
defer list.deinit(gpa);
list.append(gpa, item);
```

### Stream Writer API
```zig
// ❌ Zig 0.15
w.writeAll(data);

// ✅ Zig 0.16/0.17
w.interface.writeAll(data);
```

### Time API
```zig
// ❌ Removed in 0.16
std.time.timestamp()
std.time.nanoTimestamp()

// ✅ Use zigmodu's Time module
const Time = @import("core/Time.zig");
Time.monotonicNowSeconds()
Time.monotonicNowMilliseconds()
```

### File System API
```zig
// ❌ Removed in 0.16
std.fs.accessAbsolute(path, .{})
std.fs.cwd().openFile(...)

// ✅ Use std.Io.Dir
std.Io.Dir.cwd().openFile(io, path, .{})
std.Io.Dir.accessAbsolute(io, path, .{})
```

### Process / Environ API
```zig
// ✅ Correct patterns (0.16/0.17)
var environ = std.process.Environ.empty;
var map = try environ.createMap(alloc);
var iter = map.iterator();

var child = std.process.Child.init(&.{...}, alloc);
try child.spawn();
const term = try child.wait(io);
```

### HashMap API
```zig
// StringContext is zero-sized — init(alloc) works
var map = std.StringHashMap(T).init(allocator);
map.put(key, value);
map.deinit();

// Non-String HashMap needs initContext
var map = std.HashMap(K, V, Ctx, ...).initContext(allocator, ctx);
```

### Comptime Patterns
```zig
// ❌ SEGV risk: comptime ++ on slices with '/' in names
const names = comptime blk: {
    var result: []const []const u8 = &[_][]const u8{};
    for (modules) |mod| result = result ++ [_][]const u8{mod.name};
    break :blk result;
};

// ✅ Safe: use runtime sort instead
var sorted = std.ArrayList([]const u8).empty;
var visited = std.StringHashMap(void).init(allocator);
defer visited.deinit();
```

## Bug Detection — Systematic Scan Commands

### Round 1: API Compatibility (0.17)
```bash
grep -rn '\*\*' src/ --include="*.zig" | grep -v '//' | grep -v '\.zig-cache'
grep -rn '\.dupeZ(' src/ --include="*.zig"
grep -rn 'bufPrintZ' src/ --include="*.zig"
grep -rn '@cImport' src/ --include="*.zig"
grep -rn '\.writeAll(' src/ --include="*.zig" | grep -v interface
```

### Round 2: Memory Safety
```bash
grep -rn "\.toOwnedSlice()" src/ | grep -v test | grep -v allocator
grep -rn "\.deinit()" src/ | grep -v test | grep -v allocator
grep -rn "@ptrCast.*@alignCast" src/
```

### Round 3: Type Correctness
```bash
grep -rn "\.put(" src/ | grep -v test | grep -v allocator
grep -rn "@hasDecl(" src/ | grep -v test
grep -rn "\.len\b" src/ | grep "alloc\|buf\["
```

## Code Generation Philosophy

### Golden Rule
**@initialized, not @generated.** AI modifies generated files directly. No ext/ needed.

```zig
// ✅ Correct header
//! @initialized by zmodu — AI may modify freely

// ❌ Old header (removed)
//! ⛔ @generated by zmodu — DO NOT EDIT
```

### Safe Write Pattern
```zig
// safeWrite: file exists → .gen.new, file not exists → direct write
// This NEVER loses user code.
```

## Module Architecture Patterns

### AI Module (v0.13.0+)
```
zigmodu/src/ai/
├── ai.zig:         Barrel exports (Tool, SkillRegistry, AiProvider, MemoryStore)
├── skill.zig:      Tool/SkillContext/SkillRegistry for Agent tool calling
├── provider.zig:   AiProvider — cache-optimized messages, HTTP pool, rate limit, metrics
├── memory.zig:     MemoryStore — remember/recall/forget, thread-safe, LRU eviction
├── tokenizer.zig:  Fast token estimator (CJK-aware, no allocation)

Generated (--with-aichat):
src/modules/ai/chat/
├── provider.zig:   Re-exports zigmodu.ai.AiProvider
├── sse.zig:        Re-exports zigmodu.http.SseWriter
├── service.zig:    Multi-turn context, memory, token budget, auto-summarize
├── api.zig:        REST + SSE streaming endpoints
├── model.zig:      AiConversation, AiMessage
└── persistence.zig

Generated (--with-agent):
src/modules/ai/agent/
├── agent.zig:      ReAct loop (think→act→observe), parseToolCall, AgentResult
├── service.zig:    AgentService with SkillRegistry dispatch
└── api.zig:        POST /ai/agent/run, GET /ai/agent/runs
```

### IM Module
```
src/modules/im/
├── model.zig:       Message, Conversation, Participant
├── persistence.zig: Repository(T) × 3
├── service.zig:     CRUD + send() + relay
├── api.zig:         REST endpoints
├── gateway.zig:     WS upgrade + session mgmt
├── relay.zig:       DB write + online push
└── tests.zig:       16 integration tests
```

### Web4 Module
```
src/modules/web4/
├── did.zig (framework): did:key Ed25519 + VC
├── x402.zig (framework): HTTP 402 payment protocol
├── service.zig:         createIdentity + createInvoice
└── api.zig:             REST endpoints
```

## SSE (Server-Sent Events)

```zig
// zigmodu.http.SseWriter — direct socket I/O, no buffering
var sse = try zigmodu.http.SseWriter.init(ctx);
try sse.sendEvent("message", "hello");       // Named event
try sse.sendData("{json}");                  // Data-only (default "message" type)
try sse.sendMultiLine("result", &.{l1, l2}); // Multi-line data
sse.setId("42");                             // Last-Event-ID for reconnect
try sse.sendRetry(3000);                     // Client reconnection ms
try sse.heartbeat();                         // ": ping" keep-alive
try sse.done();                              // event: done, data: [DONE]
try sse.sendError("something went wrong");   // Error event
```

## DeepSeek V4 Cache Optimization

Cache is implicit prefix-based. Static content FIRST in message array:

```
[system prompt]  ← always cached (static)
[memories]       ← session-cached (semi-static)
[history 0..N]   ← prefix-stable (dynamic)
[user query]     ← only uncached part
```

- `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` in API response
- 90% cheaper on cache hits
- 1M token context window (V4 Pro/Flash)

## Performance Patterns

### WebSocket High-Concurrency
- BufferPool: shared 4KB pool, not per-connection stack
- ConnectionRegistry: 64-way sharded locks by userId
- TCP tuning: SO_RCVBUF/SO_SNDBUF=2048, TCP_NODELAY
- SO_REUSEPORT: multi-process scaling without shared state
- io_uring: Linux 5.1+ fiber elimination (16KB→0 per connection)

### AI Provider High-Concurrency
- HttpClient connection pool (reuse connections to LLM API)
- RateLimiter: token bucket with mutex (per-provider)
- MemoryStore: mutex-protected HashMap, LRU eviction
- Tokenizer: lock-free, no allocation, ±20% accuracy

## Testing Patterns

### Per-Module Test Template
```zig
test "model defaults" { ... }       // Struct field defaults
test "service validation" { ... }   // Reject empty, accept valid
test "gateway lifecycle" { ... }    // init/deinit/cleanup
test "registry CRUD" { ... }        // register/unregister/lookup
test "end-to-end flow" { ... }      // Full pipeline with mocks
```

### Framework Test Template
```zig
test "parse simple CSV" { ... }     // Happy path
test "parse quoted fields" { ... }  // Edge case: embedded delimiters
test "encode round-trip" { ... }    // Encode → decode matches
test "write row with comma" { ... } // Edge case: quoting needed
```

## Git Workflow

```bash
# Commit format
<type>(<scope>): <subject>
# Types: feat, fix, docs, test, refactor, perf, chore
# Scopes: im, ai, web4, server, config, security

# Tagging
git tag -a v0.X.0 -m "v0.X.0: <summary>"
git push origin v0.X.0

# Version sync: tag MUST match build.zig.zon version
grep version build.zig.zon
git describe --tags
```

## Evolution Log

### 2026-05-27: Zig 0.17 migration + AI module consolidation
- **Array multiplication `**` removed** — replaced by `@splat()` across 6 files (13 occurrences)
- **`allocator.dupeZ` removed** — replaced with `allocSentinel` + `@memcpy` helper
- **`std.fmt.bufPrintZ` removed** — replaced with `bufPrint` + manual null terminator
- **`Uri.Component`** no longer coerces to `[]const u8` — use `.toRaw(&buf)`
- **`writeAll` → `interface.writeAll`** — Stream.Writer wrapper in 0.16, still required in 0.17
- **HttpClient.zig pre-existing bugs fixed** — Uri.Component + writeAll in generated path
- **`@cImport`** reported as removed (build.zig `addTranslateC` replacement)
- **AI modules added** — provider, memory, tokenizer, SSE writer (4 new framework files)
- **Generated AI Chat upgraded** — multi-turn context, cache-optimized, memory integration
- **Comments standardized** — all Chinese translated to English across 50 files
- **Releases**: zigmodu v0.13.0, zmodu v0.14.0

### 2026-05-25: Lessons from session with 150+ commits
- Zig 0.16 API: ArrayList, Stream, fs, time, Environ all changed
- Comptime ++ with module names containing '/' causes SEGV → use runtime sort
- ext/ mechanism removed in favor of @initialized + direct AI editing
- safeWrite: .gen.new pattern prevents user code loss
- DeepScan built for IM performance (ConnectionRegistry sharding, BufferPool, io_uring)
- SkillRegistry foundation for AI Agent tool calling
- Module names with '/' in topological sort: comptime edge case → runtime fix

### Pattern: When adding new features to zigmodu
1. Add framework module (src/<domain>/)
2. Export from root.zig (and domain barrel like ai/ai.zig, http.zig)
3. Add zmodu --with-<name> flag
4. Generate module in zmodu scaffold
5. Wire into generated main.zig
6. Add tests + README
7. Build + scaffold + compile test
