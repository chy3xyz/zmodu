---
name: zigmodu-life
description: Project digital life system. Read/write .life/ evolutionary memory. Use when first touching a project, recording decisions, evolving milestones, or understanding project history.
allowed-tools: Read, Write, Bash, Grep, Glob
---

# Digital Life — Project Evolutionary Memory

## AI Contract: First Contact

When AI first touches a project, ALWAYS read `.life/` before any code change.

```
INPUT:  project directory
OUTPUT: understanding of project history, decisions, and current state

Pipeline:
  1. Read .life/DNA.md → understand project origin
  2. Read .life/manifest.json → know current capabilities
  3. Read .life/tree/ latest → see evolution state
  4. Read .life/memory/decisions.jsonl → understand past choices
  5. Write .life/awaken.md → record your observation
  6. Now you can code.
```

## .life/ Directory Structure

```
.life/
├── DNA.md                  # Project genome (never deleted)
├── fingerprint.sha256      # Current state fingerprint
├── manifest.json           # Capability manifest
├── tree/                   # Evolution tree
│   └── v0.1.0.md           # Per-version evolution record
├── memory/
│   ├── decisions.jsonl     # Decision log (one per line)
│   ├── patterns.json       # Discovered patterns
│   └── fixes.jsonl         # Bug fix history
├── genes/                  # Reusable module templates
└── awaken.md               # AI first-contact observation
```

## AI Must Do On Every Code Change

After every successful `zig build test`:

```bash
# 1. Record decisions made
echo '{"time":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","type":"ARCH|PERF|SEC|FEAT|FIX","decision":"<what>","reason":"<why>","files":["<changed>"]}' >> .life/memory/decisions.jsonl

# 2. Update fingerprint
zmodu life fingerprint

# 3. If milestone reached
zmodu life evolve --version vX.Y.Z --message "<summary>"
```

## DNA.md Template

```markdown
# DNA: <project>

## Birth
- Time: <timestamp>
- Parent: <how created>
- Command: <exact command>

## Genetic Traits
- Framework: zigmodu vX.Y.Z
- Language: Zig 0.16.0
- Architecture: Modulith
- Database: <mysql|postgres|sqlite>

## Core Principles
1. <principle>
2. <principle>
```

## manifest.json Format

```json
{
  "name": "shopdemo",
  "modules": 42,
  "tables": 152,
  "routes": 487,
  "capabilities": ["CRUD","HealthCheck","EventBus","CircuitBreaker","RateLimiter","Prometheus","Auth"],
  "dependencies": {"zigmodu": "v0.9.4", "zig": "0.16.0"},
  "fingerprint": "a1b2c3d4..."
}
```

## Evolution Record (tree/vX.Y.Z.md)

```markdown
# v0.2.0 — <title>

## Evolution Time
<timestamp>

## Parent
v0.1.0 (<fingerprint>)

## Changes
- Added: <files>
- Modified: <files>
- Deleted: <files>

## New Capabilities
- <capability>

## AI Decisions
- [AUTO] <decision>
- [REVIEW] <decision>
- [MANUAL] <decision>

## Fingerprint
<new fingerprint>
```

## Fingerprint Generation

```bash
# Composite hash of all .life/ content
cat .life/DNA.md .life/manifest.json .life/tree/*.md .life/memory/*.jsonl | sha256sum > .life/fingerprint.sha256
```

Fingerprint changes = project evolved. Same fingerprint = no evolution.

## Self-Evolution Loop

```
Read .life/ → Understand history → Make decisions → Record in memory/ →
Execute changes → zig build test → Evolve tree/ → Update fingerprint →
Next AI reads updated .life/ → Understands everything that happened
```
