---
name: zigmodu-translate
description: Translate Java/PHP code to ZigModu Zig. Use when converting services, controllers, or domain logic.
---

# Translate Legacy Code

## Phase 3 of Migration Harness

## Type Mapping
| Java/PHP | Zig |
|-----------|-----|
| String | `[]const u8` |
| int/Integer/long | `i64` |
| double/Double | `f64` |
| boolean | `bool` |
| Optional\<T\> | `?T` |
| List\<T\> | `[]T` |
| CompletableFuture\<T\> | `EventBus` publish/subscribe |

## Confidence Tags
- `[AUTO]` Simple CRUD, no review needed
- `[REVIEW]` Business rules preserved, needs human confirmation
- `[MANUAL]` Complex logic, rewrite with SagaOrchestrator

## Pattern: @Transactional → repo.transact()
```zig
try repo.transact(R, struct {{
    fn doTx(tx: *data.orm.Tx(data.SqlxBackend)) !R {{
        // transactional logic here
    }}
}}.doTx);
```

## Exception → Error Union
`throw BusinessException("msg")` → `return error.BusinessError`
`@Autowired` fields → explicit `init()` wiring
`@Value` config → `ExternalizedConfig` or env vars
