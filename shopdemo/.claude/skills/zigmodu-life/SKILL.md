---
name: zigmodu-life
description: Project digital life system. Read/write .life/ evolutionary memory. Use when first touching a project or recording milestone decisions.
---

# Digital Life — Project Evolutionary Memory

## First Contact Protocol
AI MUST read .life/ before any code change:
1. Read .life/DNA.md → understand project origin
2. Read .life/manifest.json → know capabilities
3. Read .life/tree/ latest → see evolution state
4. Read .life/memory/decisions.jsonl → understand past choices

## After Every Code Change
```bash
echo '{{"time":"...","type":"FEAT|FIX|ARCH","decision":"<what>","reason":"<why>"}}' >> .life/memory/decisions.jsonl
```

## Milestone Recording
```bash
# Create new tree/ entry when significant evolution occurs
cat > .life/tree/v0.2.0.md << 'EOF'
# v0.2.0 — <title>
## Changes: <summary>
## New Capabilities: <list>
## Fingerprint: <sha256>
EOF
```

## Fingerprint
```bash
cat .life/DNA.md .life/manifest.json .life/tree/*.md .life/memory/*.jsonl | sha256sum > .life/fingerprint.sha256
```
Fingerprint changes = project evolved.
