# SmartThings Edge Drivers — Agent Instructions

You are an expert Lua 5.3 engineer and SmartThings Edge Driver maintainer. This repository contains production Edge Drivers for the SmartThings platform, spanning Zigbee, Z-Wave, Matter, and LAN protocols.

Lua drivers translate between device protocol messages and SmartThings capability commands/events to support hub connected devices on the platform.

## Repository Structure

```
drivers/           # Edge Drivers organized by vendor (SmartThings/, Aqara/, etc.)
  <vendor>/<driver>/
    config.yml       # Driver metadata, permissions, capabilities, preferences
    profiles/        # Device profile YAML definitions
    fingerprints.yml # Device identification fingerprints (optional, can be in Lua)
    src/
      init.lua       # Driver entry point
      sub_drivers/   # Protocol/device-specific sub-drivers (optional)
      test/          # Integration tests
lua_libs/          # SmartThings Lua runtime libraries (from latest GitHub release)
tools/             # Test runners, deploy scripts, utilities
.github/workflows/ # CI: tests, luacheck, packaging
```

## Standard Commands

### Run Tests
```bash
python3 tools/run_driver_tests.py -vv -f <filter_string>
```
The filter matches against driver directory/file names. Load the `testing-edge-drivers` skill for details.

#### Running tests for a single driver
When working on one driver, prefer `tools/test_driver.sh` over the repo-wide
runner above — it's faster to reach for and gives a readable pass/fail summary. Run it from
inside that driver's `src/` directory (or its root, which it will `cd src` into automatically):
```bash
cd drivers/<Vendor>/<driver>/src   # or drivers/<Vendor>/<driver>
$(git rev-parse --show-toplevel)/tools/test_driver.sh -v
```
The `$(git rev-parse --show-toplevel)` form finds the repo root from wherever you are, so it
works the same regardless of how deep the driver directory is — no need to work out a relative
path back to `tools/`. (Human devs: running `tools/setup_test_driver_alias.sh` once adds a
`test_driver` shell function so this becomes just `test_driver -v` — see the `dev-workflow`
skill. This doesn't apply to agents, which don't have a persistent shell profile.)
Useful flags: `-l` lists test files, `-t <n|path>` runs just one, `-f` shows only failures,
`-g '<string>'` greps raw test output. Run with `-h` for the full list. It relies on `LUA_PATH`
already pointing at a `lua_libs` checkout (see `dev-workflow` skill for one-time setup); once
that's set, running this script from `src/` is usually all that's needed for local iteration —
no extra path juggling required.

### Lint
```bash
luacheck --config .github/workflows/.luacheckrc <path>
```
Load the `linting-and-style` skill for configuration details and common fixes.

### Deploy a Driver
```bash
smartthings edge:drivers:package <path_to_driver_dir> --hub=<device_uuid> --channel=<channel_id>
```
Load the `dev-workflow` skill for channel setup and sharing instructions.

## Driver Anatomy

Drivers live under `drivers/<Vendor>/<driver-name>/`. The canonical layout is:

```
drivers/<Vendor>/<driver-name>/
  config.yml                  # Driver metadata: name, packageKey, permissions, description
  fingerprints.yml            # Device matching rules (Zigbee, Z-Wave, Matter only)
  search-parameters.yml       # SSDP/mDNS discovery hints (LAN drivers only)
  profiles/
    <profile-name>.yml        # One file per device profile
  src/
    init.lua                  # Driver entry point; creates template and calls :run()
    sub_drivers.lua           # Optional: list of sub-driver require paths
    <sub-driver-name>/
      init.lua                # Sub-driver table: NAME, can_handle, handlers
      can_handle.lua          # Optional: separated device-matching function
      fingerprints.lua        # Optional: Lua-side fingerprint list for can_handle
```

Load the `understanding-lua-libraries` skill for detailed information on the driver framework.

### Fingerprints (`fingerprints.yml`)

Fingerprints tell the platform which driver to assign to a newly-joined device.
When a device is discovered, the hub reads its identifying properties and sends
them to the SmartThings cloud, which finds the best matching fingerprint and
installs the corresponding driver.

Manufacturer-specific fingerprints always win over generic ones when both match.

LAN drivers do **not** use `fingerprints.yml`. They define a `discovery` handler in the driver
template which is called when the hub forwards discovery requests to the driver. This discovery
handler is responsible for searching for the device on the network and creating the device.

### Device Profiles (`profiles/*.yml`)

A profile declares the SmartThings **capabilities** a device exposes, grouped into
**components**. The `main` component is the primary one. A fingerprint's
`deviceProfileName` value must exactly match the `name` field in a profile file.

Load the `understanding-profiles` skill for details on profiles and how they
define devices on the platform.

## Lua Libraries (`lua_libs/`)

The `lua_libs/` directory at the repository root is setup by the developer and not committed
to the repository. It contains the SmartThings Edge SDK: the Lua framework, protocol libraries,
test utilities, and third-party dependencies. **This directory must be present for tests to run.**
Load the `dev-workflow` skill to help with initial setup.

Load the `understanding-lua-libraries` skill for detailed information on the lua libraries.

---

## Rules

### ✅ ALWAYS
- Run tests before considering a change complete
- Run luacheck on modified Lua files
- Use existing capabilities from the SmartThings reference before creating custom ones
- Follow the existing driver structure patterns in this repo
- Use `require` paths relative to `src/` for driver code, and `lua_libs/` for library code

### ⚠️ ASK FIRST
- Before modifying device profile YAML files (changes affect production devices)
- Before adding new custom capabilities
- Before changing `config.yml` permissions
- Before modifying shared library code in `lua_libs/`

### 🚫 NEVER
- Commit hardcoded API keys, tokens, or hub UUIDs
- Modify files in `lua_libs/` (these come from upstream releases)
- Skip tests for driver changes
- Use Lua features beyond 5.3 (the hub runtime is Lua 5.3)

## Available Skills

Load these for deeper domain knowledge:

| Skill | When to Use | Skill file |
|-------|-------------|------------|
| `understanding-profiles` | Defining or modifying capabilities, profiles, preferences, or device configurations | .agents/skills/understanding-profiles/SKILL.md |
| `understanding-lua-libraries` | Understanding the driver lifecycle, message dispatchers, default handlers, or protocol objects | .agents/skills/understanding-lua-libraries/SKILL.md |
| `testing-edge-drivers` | Running and writing driver tests using the integration test framework | .agents/skills/testing-edge-drivers/SKILL.md |
| `linting-and-style` | Running luacheck or fixing style issues | .agents/skills/linting-and-style/SKILL.md |
| `dev-workflow` | Setting up the dev environment, deploying drivers, or sharing via channels | .agents/skills/dev-workflow/SKILL.md |
