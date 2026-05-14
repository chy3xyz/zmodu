---
name: zigmodu-life
description: Project digital life system. Use zmodu life CLI for all .life/ operations. Read .life/ on first contact. Record decisions via JSONL. Evolve milestones via tree/.
allowed-tools: Read, Write, Bash, Grep, Glob
---

# Digital Life — Always Use CLI

**NEVER write .life/ files manually. ALWAYS use `zmodu life` commands.**

## First Contact (mandatory, before any code change)

```bash
cat .life/DNA.md                    # understand project origin
cat .life/manifest.json             # know capabilities
zmodu life tree                     # see evolution history
cat .life/memory/decisions.jsonl    # understand past choices
```

## Recording Decisions (after every code change)

```bash
# Append one-line JSONL decision record
echo '{"t":"FEAT|FIX|ARCH|PERF|SEC","d":"<what>","r":"<why>","f":["<file>"]}' >> .life/memory/decisions.jsonl
```

Key abbreviations:
- `t` = type (FEAT/FIX/ARCH/PERF/SEC)
- `d` = decision (what was done)
- `r` = reason (why)
- `f` = files changed (array)

## Recording Milestones

```bash
# When significant evolution occurs (new capability, major refactor, phase complete)
zmodu life evolve v0.2.0 "order state machine complete"

# Check evolution tree
zmodu life tree

# Verify fingerprint changed
zmodu life fingerprint
```

## Fingerprint

```bash
zmodu life fingerprint
# Output: fingerprint: a1b2c3d4e5f6...
# Fingerprint changes = project evolved. Same = no change.
```

## AI Workflow

```
1. First contact → cat .life/DNA.md + zmodu life tree
2. Read decisions → cat .life/memory/decisions.jsonl
3. Make changes → zig build test
4. Record → echo '{...}' >> .life/memory/decisions.jsonl
5. Milestone? → zmodu life evolve vX.Y.Z "summary"
6. Verify → zmodu life fingerprint
```

## NEVER do this

```
❌ vim .life/tree/v0.2.0.md     # use zmodu life evolve instead
❌ echo "v0.2.0" > .life/fingerprint.sha256  # use zmodu life fingerprint
❌ rm .life/*                    # never delete evolutionary memory
```
