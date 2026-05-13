---
name: zigmodu-analyze
description: Analyze Java/PHP/Go/Rust project. Extracts schema.sql + routes.json + module-map.json. AI always produces these 3 structured outputs, or explains exactly what's missing.
allowed-tools: Read, Bash, Grep, Glob, Write
---

# Analyze Legacy Project → Structured Output

## AI Contract

**Input**: path to Java/PHP/Go/Rust project
**Output**: 3 files. If any file empty, explain why and what missing.

```
analysis/
├── schema.sql       # CREATE TABLE DDL (required)
├── routes.json      # API endpoint list (best-effort)
└── module-map.json  # table→module grouping (auto-inferred)
```

## Step 1: Detect Framework → Write `analysis/source.json`

```bash
# Run these. First one that matches → framework detected.
ls pom.xml 2>/dev/null && echo '{"framework":"spring-boot","lang":"java"}' > analysis/source.json
ls build.gradle 2>/dev/null && grep "spring-boot" build.gradle && echo '{"framework":"spring-boot","lang":"java"}' > analysis/source.json
ls composer.json 2>/dev/null && echo '{"framework":"laravel","lang":"php"}' > analysis/source.json
ls go.mod 2>/dev/null && echo '{"framework":"go-web","lang":"go"}' > analysis/source.json
ls Cargo.toml 2>/dev/null && echo '{"framework":"rust-web","lang":"rust"}' > analysis/source.json
# If none match:
echo '{"framework":"unknown","lang":"unknown"}' > analysis/source.json
# Stop. Ask user: "What framework? Provide DB connection or SQL dump."
```

## Step 2: Extract SQL → Write `analysis/schema.sql`

Priority order. Stop at first success:

### A. Flyway/Liquibase migrations (Spring Boot)
```bash
# Look for migration files
MIGRATIONS=$(find . -path "*/db/migration/*.sql" -o -path "*/liquibase/*.sql" 2>/dev/null | head -5)
if [ -n "$MIGRATIONS" ]; then
  cat $MIGRATIONS > analysis/schema.sql
  echo "OK: schema.sql from migration files ($(wc -l < analysis/schema.sql) lines)"
else
  echo "NO_MIGRATION_FILES"
fi
```

### B. mysqldump/pg_dump (running database)
```bash
# If NO_MIGRATION_FILES, try dump
mysqldump --no-data --compact --skip-triggers $DB_NAME 2>/dev/null > analysis/schema.sql
pg_dump --schema-only --no-owner $DB_NAME 2>/dev/null > analysis/schema.sql
# If dump succeeds:
echo "OK: schema.sql from database dump ($(wc -l < analysis/schema.sql) lines)"
# If dump fails:
echo "FAIL: Cannot extract schema. Need either migration files or DB credentials."
# Stop. Ask user.
```

### C. JPA Entity classes (last resort, partial)
```bash
# If NO_MIGRATION_FILES and NO_DB_DUMP:
# Extract table/column info from @Entity classes
grep -rn "@Entity\|@Table\|@Column" src/main/java --include="*.java" -A1 > analysis/entities.txt
echo "PARTIAL: entity metadata extracted. Schema.sql will be incomplete."
echo "Tables found: $(grep -c '@Table\|@Entity' analysis/entities.txt)"
# AI must then manually reconstruct DDL from @Column annotations
```

## Step 3: Extract Routes → Write `analysis/routes.json`

Format: JSON array. Each endpoint has exact method+path. No guessing.

### Spring Boot
```bash
# Extract annotations with file+line context
grep -rn "@GetMapping\|@PostMapping\|@PutMapping\|@DeleteMapping\|@RequestMapping" \
  src/main/java --include="*.java" > analysis/routes-raw.txt
```

AI parses routes-raw.txt into:
```json
[
  {"method":"GET","path":"/api/orders","controller":"OrderController.list","file":"OrderController.java:23"},
  {"method":"POST","path":"/api/orders","controller":"OrderController.create","file":"OrderController.java:45"},
  {"method":"GET","path":"/api/orders/{id}","controller":"OrderController.get","file":"OrderController.java:67"}
]
```

### Laravel
```bash
php artisan route:list --json > analysis/routes.json 2>/dev/null
# If artisan exists, routes.json already valid JSON
```

### Go (gin/echo/chi)
```bash
grep -rn '\.GET(\|\.POST(\|\.PUT(\|\.DELETE(\|\.PATCH(' --include="*.go" > analysis/routes-raw.txt
# AI parses into same JSON format
```

### If no routes found
```bash
echo '[]' > analysis/routes.json
echo "WARN: no routes extracted. API surface will be pure CRUD from schema."
```

## Step 4: Map Tables → Modules → Write `analysis/module-map.json`

Auto-detect module grouping from table name prefixes:

```bash
# Extract table names from schema.sql
grep -i "CREATE TABLE" analysis/schema.sql | \
  sed 's/.*CREATE TABLE\s*`\?\([a-z_]*\)`\?.*/\1/i' | sort > analysis/tables.txt
```

AI applies grouping rule:
```
Rule: strip common prefix up to first '_' after shared segment.
Example: zmodu_order, zmodu_order_item, zmodu_payment
  → module "order": [zmodu_order, zmodu_order_item]
  → module "payment": [zmodu_payment]

If no common prefix:
  → each table = own module
```

Output `module-map.json`:
```json
{
  "order": {"tables": ["zmodu_order","zmodu_order_item"],"deps": ["user","product"]},
  "user": {"tables": ["zmodu_user"],"deps": []},
  "product": {"tables": ["zmodu_product"],"deps": []}
}
```

Dependencies inferred from FOREIGN KEY references:
```bash
grep -i "FOREIGN KEY.*REFERENCES" analysis/schema.sql > analysis/fk-raw.txt
```
AI parses: `FOREIGN KEY (user_id) REFERENCES zmodu_user(id)` → module "order" depends on module "user"

## Step 5: Produce Summary

After all steps, output:

```
analysis/
├── source.json       # framework/lang detected
├── schema.sql        # table DDL
├── routes.json       # API endpoints
├── module-map.json   # table→module grouping
├── fk-raw.txt        # foreign key references
└── SUMMARY.md        # AI writes this

SUMMARY.md format:
## Analysis Summary
- Framework: spring-boot (Java)
- Tables: 152
- Routes: 487
- Modules: 42
- Missing: auth config (no SecurityConfig found), schedule tasks (5 @Scheduled found)
```

## If Any Step Fails

AI must NOT proceed to generation. Output exactly what's missing:

```
BLOCKED: Step 2 (Extract SQL)
Reason: No migration files found, no DB credentials provided.
Action: Provide either:
  a) Path to migration SQL files
  b) Database host/port/user/pass/name for mysqldump
  c) Direct DDL export as schema.sql
```
