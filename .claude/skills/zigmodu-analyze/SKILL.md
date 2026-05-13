---
name: zigmodu-analyze
description: Analyze Java Spring Boot or PHP Laravel project to extract schema, API routes, module boundaries, and configuration. Use when migrating a legacy backend to ZigModu.
allowed-tools: Read, Bash, Grep, Glob, Write
---

# Analyze Legacy Backend for Migration

## Phase 1 of Migration Harness

Purpose: Extract structured project image from Java/PHP source code.

## Step 1: Identify Project Type

```bash
# Detect framework
find . -name "pom.xml" -o -name "build.gradle" | head -1  # → Spring Boot
find . -name "composer.json" -o -name "artisan" | head -1  # → Laravel
find . -name "symfony.lock" | head -1                       # → Symfony
```

## Step 2: Extract Database Schema

### Spring Boot (JPA/Hibernate)
```bash
# Find entity classes
grep -rn "@Entity\|@Table" src/main/java --include="*.java" -l

# Extract DDL (if Flyway/Liquibase)
find . -path "*/db/migration/*.sql" -o -path "*/liquibase/*.xml"

# Or dump from running DB
mysqldump --no-data --compact --skip-triggers db_name > schema.sql
```

### Laravel
```bash
# Find migrations
ls database/migrations/

# Extract schema from migrations
php artisan schema:dump

# OR find Eloquent models
grep -rn "extends Model" app/Models --include="*.php" -l
```

## Step 3: Extract API Routes

### Spring Boot
```bash
grep -rn "@GetMapping\|@PostMapping\|@PutMapping\|@DeleteMapping\|@RequestMapping" \
  src/main/java --include="*.java" -A2 | \
  grep -E "method|value|path" > routes.txt
```

### Laravel
```bash
# From routes/api.php
cat routes/api.php | grep "Route::" > routes.txt

# List all routes with php artisan
php artisan route:list --json > routes.json
```

## Step 4: Map Module Boundaries

### Spring Boot package → Modulith module
```
com.example.order.*       → order module
com.example.user.*        → user module
com.example.payment.*     → payment module

Rule: top-level package = module. Sub-packages = internal.
```

### Laravel namespace → Modulith module
```
App\Models\Order          → order module (model)
App\Http\Controllers\OrderController → order module (api)
App\Services\OrderService  → order module (service)
```

## Step 5: Identify Middleware Chain

### Spring Boot
```bash
grep -rn "addFilter\|@Bean.*Filter\|SecurityFilterChain\|WebMvcConfigurer" \
  src/main/java --include="*.java"
```

Map:
```
SecurityFilterChain       → zigmodu.security.auth
CorsFilter                → http_middleware.cors()
RateLimiter               → zigmodu.RateLimiter
OncePerRequestFilter      → server.addMiddleware()
```

### Laravel
```bash
grep -rn "'middleware' =>" routes/api.php
grep -rn "$middleware" app/Http/Kernel.php
```

## Step 6: Generate Analysis Output

Create `analysis.json`:
```json
{
  "source": "java|php",
  "framework": "spring-boot|laravel|symfony",
  "tables": ["table1", "table2", ...],
  "routes": [
    {"method": "GET", "path": "/api/users", "controller": "UserController.list"},
    ...
  ],
  "modules": {
    "order": {"tables": ["orders", "order_items"], "deps": ["user", "product"]},
    ...
  },
  "middleware": ["cors", "auth-jwt", "rate-limit"],
  "config": {
    "DB_HOST": "${DB_HOST:localhost}",
    ...
  },
  "auth": {
    "type": "jwt",
    "token_header": "Authorization",
    "token_prefix": "Bearer "
  }
}
```

## Step 7: Generate SQL DDL

```bash
# From analysis.json → schema.sql
zmodu analyze --source java --input ./legacy/ --output analysis.json
# Also outputs: schema.sql, routes.json, modules.json
```

## Phase Transition

After analysis, proceed to Phase 2 with:
```bash
zmodu harness --analysis analysis.json --output ./new-backend/
```
