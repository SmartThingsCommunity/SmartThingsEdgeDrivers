---
name: understanding-lua-libraries
description: Understanding the SmartThings Edge Driver Lua libraries - driver lifecycle, message dispatchers, default handlers, and protocol message objects
---

# SmartThings Edge Driver Lua Library Architecture

## 1. Driver Initialization and Run Loop

A driver is created by calling `Driver("name", template)` (or a protocol-specific variant like `ZigbeeDriver("name", template)`). The template is a Lua table containing handler tables and configuration.

The base `Driver.init` (in `lua_libs/st/driver.lua`) does the following:
- Sets `out_driver.NAME` from the name argument
- Initializes handler tables: `capability_handlers`, `lifecycle_handlers`, `message_handlers`
- Opens communication channels via cosock sockets: `capability_channel`, `environment_channel`, `lifecycle_channel`, `driver_lifecycle_channel`, and optionally `discovery_channel`
- Initializes a datastore and device cache tables
- Calls `Driver.standardize_sub_drivers()` to normalize the `sub_drivers` list
- Builds the `lifecycle_dispatcher` and `capability_dispatcher` from handlers + sub_drivers
- Registers channel handlers so inbound messages get routed to the correct handler function

The `driver:run()` call starts the cosock event loop, which runs forever processing messages from all registered channels.

## 2. Message Dispatchers

The dispatcher system (`lua_libs/st/dispatcher.lua`) is a hierarchical message routing tree. The base class `MessageDispatcher` provides:

- **`default_handlers`** - handlers at this level of the hierarchy.
- **`child_dispatchers`** - sub-dispatchers (from sub_drivers) that may override defaults
- **`can_handle(driver, device, ...)`** - returns true if this dispatcher or a child can handle the message
- **`dispatch(driver, device, ...)`** - finds and executes the matching handler

### Dispatch logic

1. The dispatcher calls `can_handle` on each child dispatcher
2. If any children can handle: **only the children handle it** (parent defaults are NOT called)
3. If multiple children match: ALL matching children receive the message
4. If NO children match: parent defaults are used
5. This is recursive -- sub-drivers can have sub-drivers

### Dispatcher types

| Dispatcher | Class | Handles |
|------------|-------|---------|
| `capability_dispatcher` | `CapabilityCommandDispatcher` | Capability commands from the platform (on, off, setLevel, etc.) |
| `lifecycle_dispatcher` | `DeviceLifecycleDispatcher` | Device lifecycle events (added, init, removed, etc.) |
| `zigbee_message_dispatcher` | `ZigbeeMessageDispatcher` | Incoming Zigbee messages (attribute reports, cluster commands, ZDO) |
| `zwave_dispatcher` | `ZwaveDispatcher` | Incoming Z-Wave commands |
| `matter_dispatcher` | `MatterMessageDispatcher` | Incoming Matter interaction responses |
| `secret_data_dispatcher` | `SecretDataDispatcher` | Security/secret data events |

Each protocol-specific driver (ZigbeeDriver, ZwaveDriver, MatterDriver) adds its own dispatcher on top of the base Driver's capability and lifecycle dispatchers.

**Zigbee handler structure:**
```lua
zigbee_handlers = {
  attr = {    -- attribute reports / read responses
    [ClusterID] = {
      [AttributeID] = handler_function,
    }
  },
  global = {  -- global ZCL commands
    [ClusterID] = {
      [CommandID] = handler_function,
    }
  },
  cluster = { -- cluster-specific commands
    [ClusterID] = {
      [CommandID] = handler_function,
    }
  },
  zdo = {     -- ZDO commands
    [ClusterID] = handler_function,
  }
}
```

**Z-Wave handler structure:**
```lua
zwave_handlers = {
  [cc.SWITCH_BINARY] = {          -- command class
    [SwitchBinary.REPORT] = handler_function,  -- command ID
  },
}
```

**Matter handler structure:**
```lua
matter_handlers = {
  attr = {
    [ClusterID] = {
      [AttributeID] = handler_function,
    }
  },
  cmd_response = { ... },
  event = { ... },
  fallback = handler_function,
}
```

**Capability handler structure:**
```lua
capability_handlers = {
  [capabilities.switch.ID] = {
    [capabilities.switch.commands.on.NAME] = handle_on,
    [capabilities.switch.commands.off.NAME] = handle_off,
  },
  [capabilities.switchLevel.ID] = {
    [capabilities.switchLevel.commands.setLevel.NAME] = handle_set_level,
  },
}
```

## 3. Sub-Drivers Pattern

Sub-drivers allow device-specific behavior overrides gated by a `can_handle` function. A sub-driver is a table with:
- `NAME` (string)
- `can_handle(opts, driver, device, ...) -> boolean`
- Protocol handlers (zigbee_handlers, zwave_handlers, matter_handlers)
- `capability_handlers`, `lifecycle_handlers`
- Optional nested `sub_drivers`

In practice, sub-drivers are often organized as separate files under `src/sub_drivers/` for clarity, and required in the main driver template.


### Dispatch Logic

1. The dispatcher calls `can_handle` on each child dispatcher
2. If any children can handle: **only the children handle it** (parent defaults are NOT called)
3. If multiple children match: ALL matching children receive the message
4. If NO children match: parent defaults are used
5. This is recursive -- sub-drivers can have sub-drivers

### Lazy Loading

Sub-drivers support lazy loading for memory optimization:
- `Driver.lazy_load_sub_driver(sub_driver)`: Strips handlers, keeps only `can_handle` and `NAME`
- `Driver.lazy_load_sub_driver_v2(require_path)`: Even more efficient; only requires `can_handle` and `sub_drivers` modules separately
- A sub-driver with no handlers defined is automatically treated as lazy-loadable

New sub-drivers must be:
1. Listed in the parent's `sub_drivers.lua` (or the equivalent sub_drivers table)
2. Have a `can_handle.lua` that correctly identifies the target devices
3. Have an `init.lua` that returns the sub-driver table

If any of these are missing, the sub-driver will not be loaded.


## 4. Lifecycle Events

Device lifecycle events are dispatched through the `DeviceLifecycleDispatcher`. The key events:

1. **`init`** -- Called for every device on driver startup (existing devices) and after `added` for new devices. Used for setting up component/endpoint mappings and device fields.
2. **`added`** -- Called only when a device is first paired. NOT called for existing devices when a driver is updated. After `added`, a synthetic `init` is automatically dispatched.
3. **`doConfigure`** -- Called when the device needs configuration (typically after pairing).
4. **`infoChanged`** -- Called when device metadata changes (e.g., preferences updated). Receives `args.old_st_store` for comparison.
5. **`removed`** -- Called when device is removed.
6. **`driverSwitched`** -- Called when device switches to this driver.

Register lifecycle handlers in the template:
```lua
lifecycle_handlers = {
  init = device_init,
  added = device_added,
  removed = device_removed,
  doConfigure = device_do_configure,
  infoChanged = info_changed_handler,
}
```

Handler signature: `function(driver, device, event, args)`

**Default behaviors provided by the framework:**
- `driverSwitched`: Base Driver marks device as `NONFUNCTIONAL`. ZigbeeDriver overrides this to check capability matching and marks as `PROVISIONED` if all capabilities match.
- `doConfigure`: ZigbeeDriver defaults to `device_management.configure` which sends attribute reporting configuration.
- `added`: After a successful `added` callback, the framework automatically queues a synthetic `init` event.
- `doConfigure`: After success, the framework transitions the device to `PROVISIONED` state.
- Unhandled lifecycle events log a trace message and are otherwise ignored (fallback handler).

**Critical timing knowledge for lifecycle events**

1. **`init` on driver startup**. After hub restart the radio may not be ready and sending Zigbee/Z-Wave commands in `init` can fail.
2. **`added` is NOT called for existing devices** on driver update. Only called on first pair. Code that must run for existing devices should go in `init` (for non-radio operations) or use `driverSwitched`.
3. **`doConfigure` is called any time a device is added with the TYPED provisioning state** and is the right place for device-specific configuration commands.
4. **`infoChanged` receives `args.old_st_store`** for comparing old vs new preferences. Drivers should check if a preference actually changed before acting on it.

## 5. Key Imports and Require Paths

```lua
-- Base driver (for virtual/LAN devices)
local Driver = require "st.driver"

-- Protocol-specific drivers
local ZigbeeDriver = require "st.zigbee"
local ZwaveDriver = require "st.zwave.driver"
local MatterDriver = require "st.matter.driver"

-- Capabilities
local capabilities = require "st.capabilities"

-- Zigbee defaults (pre-built handlers for common capabilities)
local defaults = require "st.zigbee.defaults"

-- Zigbee clusters (for building commands/reading attributes)
local zcl_clusters = require "st.zigbee.zcl"

-- Z-Wave command classes
local cc = require "st.zwave.CommandClass"
local SwitchBinary = require "st.zwave.CommandClass.SwitchBinary"

-- Matter clusters
local clusters = require "st.matter.clusters"

-- Utilities
local utils = require "st.utils"
local json = require "st.json"
local log = require "log"

-- Coroutine runtime
local cosock = require "cosock"

-- LAN utils
local socket = cosock.socket
local luncheon = require "luncheon"
local luxure = require "luxure"
local lustre = require "lustre"
```

### Zigbee driver example (from zigbee-switch)

```lua
local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"

local template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.colorControl,
    capabilities.colorTemperature,
  },
  sub_drivers = require("sub_drivers"),
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
  },
}

-- Register default Zigbee handlers for all supported capabilities
defaults.register_for_default_handlers(template,
  template.supported_capabilities,
  {native_capability_cmds_enabled = true, native_capability_attrs_enabled = true}
)

local driver = ZigbeeDriver("zigbee_switch", template)
driver:run()
```

This pattern - declare supported capabilities, register defaults, add overrides via sub_drivers and lifecycle_handlers, then construct and run - is the standard structure
for all protocol-based Edge drivers.

## 6. Default Handlers and Protocol-Specific Default Functionality

When a driver declares `supported_capabilities` in its template, the framework automatically registers default handlers for each capability. The registration uses `or`-merge
logic: **driver-defined handlers always take precedence over defaults.** If the driver already registered a handler for a given cluster/attribute/command slot, the default
is silently skipped.

Registration happens in `st.{zigbee,zwave,matter}.defaults.init.lua` via `register_for_default_handlers(driver, capabilities, opts)`:
1. Iterates `supported_capabilities`
2. For each capability, requires the corresponding defaults module
3. Merges `zigbee_handlers`, `zwave_handlers`, or `matter_handlers` (only where driver hasn't defined one)
4. Also merges `attribute_configurations` (Zigbee), `get_refresh_commands` (Z-Wave), or `subscribed_attributes` (Matter)

### Zigbee specific default functionality

The default `doConfigure` handler (`device_management.configure`):
1. Sends a `refresh` command (reads all configured attributes)
2. Calls `device:configure()` which iterates all configured attributes and for each:
   - Sends a ZDO Bind Request
   - Sends a Configure Reporting command with the attribute's min/max interval, data type, and reportable change
3. Also handles IAS Zone enrollment if the device supports cluster `0x0500`

### Z-Wave specific default functionality

doConfigure calls `device:default_configure()` which calls `device:refresh()`. The default refresh iterates `get_refresh_commands` from all default capability modules and sends Get commands for each supported CC.
Refresh collects `get_refresh_commands` from all default modules, sends Get commands

### Matter specific default functionality

TODO

## 7. Unit Test Framework

Load the `testing-edge-drivers` skill for details on the built in unit test framework for to test Zigbee, Z-Wave, and Matter drivers.

