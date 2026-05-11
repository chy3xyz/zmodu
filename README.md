# zmodu

Code generation CLI for the [ZigModu](https://github.com/chy3xyz/zigmodu) framework. Modulith-style architecture scaffolding.

## Installation

```bash
# npm (recommended)
npm install -g @chy3xyz/zmodu

# From source
git clone https://github.com/chy3xyz/zmodu.git
cd zmodu
zig build install-zmodu

# Manual download
# See: https://github.com/chy3xyz/zmodu/releases
```

## Commands

```bash
zmodu new <name>            # Create new ZigModu project
zmodu module <name>         # Generate module boilerplate
zmodu event <name>          # Generate event handler
zmodu api <name>            # Generate API endpoint
zmodu orm --sql <file>      # Generate ORM modules from SQL DDL
zmodu migration <name>      # Generate Flyway-style migration file
zmodu health                # Generate health check endpoint
zmodu config --keys k1,k2   # Generate config validator
zmodu scaffold --sql <file> # SQL -> full project with wiring
zmodu generate <target>     # Unified generator alias
zmodu help                  # Show help
zmodu version               # Show version
```

## Examples

```bash
zmodu new myapp
zmodu module user
zmodu orm --sql schema.sql --out src/modules --force
zmodu migration add-users-table
zmodu health --out src/modules/app
zmodu config --keys DB_HOST,DB_PORT,DB_NAME
```

## Generated Module Structure (SQLx)

```
src/modules/{module}/
├── root.zig          # Barrel re-exports
├── module.zig        # Module metadata & lifecycle
├── model.zig         # Domain models
├── persistence.zig   # Repository layer
├── service.zig       # Business logic
└── api.zig           # HTTP handlers
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Unknown command or I/O error |
| 2 | Invalid arguments (missing flag values, empty SQL, etc.) |
| 3 | Refuse overwrite (use `--force`) |

## License

MIT
