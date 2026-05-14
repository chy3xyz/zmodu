---
name: zigmodu-life
description: Project digital life system. Use zmodu life CLI for all .life/ operations. Read .life/ on first contact. Record decisions via JSONL. Evolve milestones via tree/.
---

# Digital Life — Use CLI, not manual file ops

## First Contact (BEFORE any code change)
```bash
cat .life/DNA.md && zmodu life tree && cat .life/memory/decisions.jsonl
```

## Record Decision (after every code change)
```bash
echo '{{"t":"FEAT|FIX|ARCH|PERF|SEC","d":"<what>","r":"<why>","f":["<file>"]}}' >> .life/memory/decisions.jsonl
```

## Record Milestone
```bash
zmodu life evolve v0.2.0 "order state machine complete"
zmodu life tree        # verify
zmodu life fingerprint  # verify fingerprint changed
```

## NEVER do this
`vim .life/tree/v0.2.0.md`  → use `zmodu life evolve`
`echo "x" > .life/fingerprint.sha256` → use `zmodu life fingerprint`
`rm .life/*` → never delete evolutionary memory
