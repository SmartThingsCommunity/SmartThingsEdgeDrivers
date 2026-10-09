---
name: linting-and-style
description: Running luacheck for Lua linting and following code style conventions in Edge Driver development
---

# Linting and Code Style for Edge Drivers

## Running Luacheck

```bash
luacheck --config .github/workflows/.luacheckrc <path>
```

### Examples

```bash
# Lint a specific driver
luacheck --config .github/workflows/.luacheckrc drivers/SmartThings/zigbee-switch/

# Lint a single file
luacheck --config .github/workflows/.luacheckrc drivers/SmartThings/zigbee-switch/src/init.lua

# Lint the entire repo
luacheck --config .github/workflows/.luacheckrc .
```

Luacheck runs automatically in CI on pull requests that modify files under `drivers/` (see `.github/workflows/luacheck.yml`).

## Code Style Conventions

These conventions are observed across the Edge Driver codebase:

### General

- **Indentation**: 2 spaces, no tabs
- **Strings**: Use double quotes `"string"` for module requires and general strings
- **Local variables**: Always use `local` for variables and functions at module scope
- **Line length**: No enforced limit, but most code stays under 120 characters

### Naming

- **Variables and functions**: `snake_case` (e.g., `local mock_device`, `local function test_init()`)
- **Constants**: `UPPER_SNAKE_CASE` for true constants (e.g., `SENSOR_BINARY`)
- **Modules**: Return a table at the end of the file (`return module_name`)

### Requires and Imports

```lua
-- Standard library requires first
local capabilities = require "st.capabilities"
local zw = require "st.zwave"

-- Then test/integration requires
local test = require "integration_test"
local t_utils = require "integration_test.utils"

-- Then protocol-specific requires
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
```

### Function Style

- Prefer `local function name()` over `local name = function()`
- Handler functions typically receive `(driver, device, ...)` arguments
- Use early returns for guard clauses

### Tables

- Trailing commas are common and acceptable in multi-line tables
- Align table entries for readability in test manifests

### Comments

- Use `--` for single-line comments
- Minimal inline comments; code should be self-documenting

Copyright header at the top of every file:
```lua
-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
```

### File Organization for Drivers

```
driver-name/
  src/
    init.lua           -- Main driver entry point
    <sub_modules>.lua  -- Additional driver modules
    test/
      test_*.lua       -- Test files (must start with test_)
  profiles/
    *.yml              -- Device profiles
  fingerprints.yml     -- Device fingerprints
  config.yml           -- Driver configuration
```
