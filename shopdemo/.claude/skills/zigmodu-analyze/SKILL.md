---
name: zigmodu-analyze
description: Analyze Java/PHP project to extract schema, routes, module boundaries. Use when migrating legacy backend to ZigModu.
---

# Analyze Legacy Backend

## Phase 1 of Migration Harness

## Detect Framework
```bash
find . -name "pom.xml" | head -1  # Spring Boot
find . -name "composer.json" | head -1  # Laravel
```

## Extract Schema
Spring Boot: `grep -rn "@Entity\|@Table" src/main/java -l`
Laravel: `ls database/migrations/`

## Extract API Routes
Spring Boot: `grep -rn "@GetMapping\|@PostMapping" src/main/java -A2`
Laravel: `php artisan route:list --json`

## Output: analysis.json
Run `zmodu analyze --source java|php --input ./legacy/ --output analysis.json`
to produce structured project image for Phase 2 scaffold.
