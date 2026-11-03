# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **SmartThings Edge Driver** written in Lua that integrates DEEPSMART KNX gateways (called "Wiser" bridges) with Samsung SmartThings. It discovers bridges via SSDP, communicates over HTTPS REST APIs, and translates KNX telegrams to SmartThings capability events.

There is no build system, package manager, or test suite — this is a pure source project deployed directly to the SmartThings Edge platform.

## Architecture

```
src/
├── init.lua                  # Driver entry point — registers capabilities, lifecycle/command handlers, starts the IP-check schedule
├── config.lua                # Device type enums (AC=3, HEATER=4, NEWFAN=53, SWITCH=14, SLIDER=16, HUE=25), address type constants
├── discovery.lua             # SSDP-based bridge discovery. Callback spawns bridge creation and device loading
├── lifecycles.lua            # init/added/removed handlers for both bridge devices and child (edge) devices
├── commands.lua              # Translates SmartThings capability commands → Wisers.control() calls with appropriate addrtypes
├── ssdp.lua                  # Raw UDP SSDP M-SEARCH broadcast, parses responses for UUID+IP
├── utils.lua                 # Socket builder (TCP+SSL via cosock), backoff generator, deep table comparison
├── selfSignedRoot.crt        # CA certificate for bridge HTTPS connections
├── deepsmart/
│   ├── wisers.lua            # Central orchestrator: bridge lifecycle (add/del/reload/refresh), KNX↔SmartThings translation, 2s poll loop
│   ├── api.lua               # HTTPS REST client wrapping lunchbox.rest: load_config, load_dp2knx, load_dpenum, query, control
│   ├── devices.lua           # Parses bridge JSON config into device/protocol/address index. Maps KNX group addresses → device DP IDs
│   ├── dp2knx.lua            # Maps productId → device type + DP ID ↔ address-type associations
│   └── dpenum.lua            # Enum value conversion: SmartThings values (cool/heat/auto) ↔ DEEPSMART integer values
└── lunchbox/
    ├── init.lua              # Module re-export: RestClient, EventSource
    ├── rest.lua              # Full-featured HTTPS client with connection pooling, retry/backoff, chunked transfer support
    ├── sse/eventsource.lua   # Server-Sent Events client
    └── util.lua              # URL parsing helpers, read-only table proxy
```

## How It Works — Data Flow

### Discovery & Setup
1. User scans for devices → `discovery.start()` sends SSDP M-SEARCH for `DEEPSMART-ARM`
2. Each bridge UUID+IP is passed to `wisers.add_wiser()`, which creates a bridge device and fetches all configs (devices, dp2knx, dpenum) from the bridge's HTTPS API
3. Every 2 seconds, `wiser_loop()` polls the bridge for changed devices — this keeps device state in sync

### Command Path (SmartThings → KNX)
1. SmartThings app sends command → `commands.lua` handler
2. Handler determines `addrtypes` based on device type (e.g., AC mode = addrtype 1)
3. Calls `wisers.control(device, command, addrtypes)` which:
   - Looks up the DP ID for the product + addrtype via `dp2knx`
   - Finds the KNX send address(es) from `devices`
   - Converts SmartThings values to DEEPSMART values via `dpenum`
   - Posts `control` API call to bridge

### Response Path (KNX → SmartThings)
1. `wiser_loop()` polls `/homecontroller/api/v1/config/changeddevs` every 2s
2. For changed devices, calls `query_deviceid()` which reads all KNX feedback addresses
3. KNX values are translated back to SmartThings values via `dpenum` and `dp2knx`
4. `driver:set_switch()`, `driver:ac_report()`, etc. emit SmartThings capability events

### Device Addressing
- `device_network_id` format: `wiser:pid:id[_idx]` (e.g., `abc123:cekfhkz5:42_1`)
- One physical DEEPSMART device can map to multiple SmartThings child devices (`idx` suffix)
- Bridge devices have `parent_assigned_child_key == nil`; child devices always have one

## Key Files for Common Changes

- **Adding a new device type**: Add the enum to `config.lua`, create a profile YAML in `profiles/`, add PID mapping in `dp2knx.lua`, add command handling in `commands.lua`, add response handling in `wisers.lua:knx_response()`
- **Changing API endpoints**: Edit `src/deepsmart/api.lua`
- **Changing discovery behavior**: Edit `src/discovery.lua` or `src/ssdp.lua`
- **Changing device lifecycle behavior**: Edit `src/lifecycles.lua`

## SmartThings Platform Constraints

- Runs on SmartThings Edge Lua runtime — `require('st.driver')`, `require('st.capabilities')`, etc. are platform-provided
- Uses `cosock` for TCP/SSL sockets (not standard Lua socket)
- The `luncheon` library provides HTTP Request/Response objects
- Driver data is persisted via `device:set_field(key, value, {persist = true})`
- Bridge configuration (devices, dp2knx, dpenum) are stored as persisted fields on the bridge device

## Device Types and Their Capabilities

| Type | Enum | Profile | Capabilities |
|------|------|---------|--------------|
| AC | 3 | Ac.v1 | switch, temperatureMeasurement, thermostatHeatingSetpoint, airConditionerMode, airConditionerFanMode |
| Heater | 4 | Heater.v1 | thermostatMode, thermostatOperatingState, thermostatHeatingSetpoint, temperatureMeasurement |
| NewFan | 53 | Newfan.v1 | switch, airConditionerFanMode |
| Switch | 14 | Light.v1 | switch |
| Slider | 16 | Slider.v1 | switch, switchLevel |
| Hue | 25 | Hue.v1 | switch, switchLevel, colorTemperature |
| Bridge | — | Deepsmart-bridge.v1 | refresh |

## Scheduling

- **Every 600 seconds**: `check_ip()` SSDP scan to detect bridge IP changes (e.g., DHCP renewal)
- **Every 2 seconds**: `wiser_loop()` polls bridge for changed device states and keeps the poll connection alive
