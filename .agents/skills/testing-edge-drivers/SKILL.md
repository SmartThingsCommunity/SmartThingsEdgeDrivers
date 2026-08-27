---
name: testing-edge-drivers
description: Running and writing integration tests for SmartThings Edge Drivers using the Python test harness and Lua integration test framework
---

# Testing SmartThings Edge Drivers

## Running Tests

Tests are run via the Python test harness:

```bash
python3 tools/run_driver_tests.py [options]
```

### Options

| Flag | Description |
|------|-------------|
| `-v` | Print individual test names and pass/fail status |
| `-vv` | Print test names, status, and full logs on failures (recommended) |
| `-vvv` | Print all logs from all tests |
| `-f <filter>` | Only run tests whose file path matches the regex filter |
| `-j <file>` | Output JUnit XML results to the specified file |
| `-c [files]` | Run with luacov code coverage |
| `--html` | Generate HTML coverage reports (use with `-c`) |

### Filter Examples

```bash
# Run all tests for a specific driver
python3 tools/run_driver_tests.py -vv -f "zwave-smoke-alarm"

# Run a specific test file
python3 tools/run_driver_tests.py -vv -f "test_zwave_smoke_detector"

# Run all zigbee switch tests
python3 tools/run_driver_tests.py -vv -f "zigbee-switch"

# Run all virtual device tests
python3 tools/run_driver_tests.py -vv -f "virtual"
```

The filter is a regex applied to the full file path. The harness searches for files matching `drivers/*/*/src/test/test_*.lua`.

### Python Requirements

Install dependencies before running tests:

```bash
pip install -r tools/requirements.txt
```

Required packages: `junit_xml`, `requests`, `PyYAML`, `regex`.

### How Tests Execute

The Python harness (`tools/run_driver_tests.py`):
1. Globs for all `test_*.lua` files under `drivers/*/src/test/`
2. Filters by the `-f` regex if provided
3. Changes directory to the driver's `src/` directory (two levels up from the test file)
4. Runs each test file with `lua <test_file>`
5. Parses stdout for `Running test`, `PASSED`, `FAILED`, and summary lines
6. Reports totals and exits with code 1 if any tests failed

## Integration Test Framework

The framework lives in `lua_libs/integration_test/` and is required as `integration_test` in test files. It provides:

### Core Modules

| Module | Purpose |
|--------|---------|
| `integration_test` (init.lua) | Main test runner, registration, mock device builder |
| `integration_test.utils` | Utility functions like `get_profile_definition()` |
| `integration_test.mock_device` | Build mock Zigbee, Z-Wave, Matter, or generic devices |
| `integration_test.zwave_test_utils` | Z-Wave specific helpers (e.g., `zwave_test_build_receive_command`) |
| `integration_test.zigbee_test_utils` | Zigbee specific helpers |
| `integration_test.mock_socket` | Mock socket layer with channel-based message routing |

### Channels

The test framework uses channels to simulate communication between the driver and the platform:

- `zwave` - Z-Wave protocol messages
- `zigbee` - Zigbee protocol messages
- `matter` - Matter protocol messages
- `capability` - SmartThings capability events (commands from cloud, events to cloud)
- `device_lifecycle` - Device lifecycle events (init, added, removed, etc.)
- `driver_lifecycle` - Driver lifecycle events
- `timer` - Timer-related events

Each channel supports two directions:
- `receive` - Messages sent TO the driver (incoming commands, device reports)
- `send` - Messages sent FROM the driver (capability events, protocol commands)

## Writing Tests

### Test File Structure

Every test file follows this pattern:

```lua
local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

-- 1. Build mock device(s)
local mock_device = test.mock_device.build_test_generic_device({
  profile = t_utils.get_profile_definition("my-profile.yml"),
})

-- 2. Define test init function (runs before each test)
local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

-- 3. Register tests (message tests or coroutine tests)

-- 4. Run all registered tests
test.run_registered_tests()
```

### Building Mock Devices

```lua
-- Generic device (no protocol)
local mock = test.mock_device.build_test_generic_device({
  profile = t_utils.get_profile_definition("profile-name.yml"),
  preferences = { ["certifiedpreferences.somePref"] = true },
})

-- Z-Wave device
local zw = require "st.zwave"
local mock = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("profile-name.yml"),
  zwave_endpoints = {
    {
      command_classes = {
        { value = zw.SENSOR_BINARY },
        { value = zw.NOTIFICATION },
      }
    }
  }
})

-- Zigbee device
local mock = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("profile-name.yml"),
  zigbee_endpoints = { ... }
})
```

### Message Tests (`register_message_test`)

Message tests define an ordered sequence of receive/send message pairs. Each receive triggers the driver handler, and the subsequent sends are the expected outputs.

```lua
test.register_message_test(
  "Test description",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  },
  {
    min_api_version = 17  -- optional version constraint
  }
)
```

The manifest is an array of message entries. The framework groups them into blocks: each block starts with a `receive` followed by zero or more `send` entries. The receives are queued on the mock channel; the sends are set as expectations. The driver processes the receive and the framework asserts the expected sends occurred.

### Coroutine Tests (`register_coroutine_test`)

For more complex test logic (multiple interactions, state changes, conditional assertions, timer manipulation):

```lua
test.register_coroutine_test(
  "Test with complex logic",
  function()
    -- Queue a lifecycle event
    test.socket.device_lifecycle():__queue_receive({ mock_device.id, "init" })
    test.socket.device_lifecycle():__queue_receive(
      mock_device:generate_info_changed({
        preferences = { ["certifiedpreferences.somePref"] = false }
      })
    )
    test.wait_for_events()

    -- Now send a capability command and expect a response
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", component = "main", command = "on", args = {} }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.switch.switch.on())
    )
  end,
  {
    min_api_version = 17
  }
)
```

Key coroutine test APIs:
- `test.socket.<channel>:__queue_receive(msg)` - Queue a message for the driver to receive
- `test.socket.<channel>:__expect_send(msg)` - Set an expectation for a message the driver should send
- `test.wait_for_events()` - Yield to let the driver process queued messages and check expectations
- `test.mock_time.advance_time(seconds)` - Advance the mock clock

### Real Example: Z-Wave Smoke Detector Test

From `drivers/SmartThings/zwave-smoke-alarm/src/test/test_zwave_smoke_detector.lua`:

```lua
local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"

local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })

local sensor_endpoints = {
  {
    command_classes = {
      { value = zw.SENSOR_BINARY },
      { value = zw.SENSOR_ALARM },
      { value = zw.NOTIFICATION },
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("smoke-battery-temperature-tamperalert-temperaturealarm.yml"),
  zwave_endpoints = sensor_endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Sensor Binary report (smoke) should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SensorBinary:Report({
            sensor_type = SensorBinary.sensor_type.SMOKE,
            sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.smokeDetector.smoke.detected())
    }
  },
  { min_api_version = 17 }
)

test.run_registered_tests()
```

## Common Test Patterns

### Testing Capability Commands (cloud -> device)

Receive on `capability` channel, expect protocol message on `zwave`/`zigbee`/`matter`:

```lua
{
  channel = "capability",
  direction = "receive",
  message = { mock_device.id, { capability = "switch", component = "main", command = "on", args = {} } }
},
{
  channel = "zwave",
  direction = "send",
  message = ...  -- expected Z-Wave command
}
```

### Testing Device Reports (device -> cloud)

Receive on protocol channel, expect capability event on `capability`:

```lua
{
  channel = "zwave",
  direction = "receive",
  message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(...) }
},
{
  channel = "capability",
  direction = "send",
  message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
}
```

### Testing Lifecycle Events

```lua
test.socket.device_lifecycle():__queue_receive({ mock_device.id, "added" })
test.socket.device_lifecycle():__queue_receive({ mock_device.id, "init" })
test.socket.device_lifecycle():__queue_receive({ mock_device.id, "doConfigure" })
```

### Testing Preference Changes

```lua
test.socket.device_lifecycle():__queue_receive(
  mock_device:generate_info_changed({
    preferences = { ["certifiedpreferences.myPref"] = new_value }
  })
)
```

### Optional Test Parameters

The `opts` table passed to `register_message_test` or `register_coroutine_test` supports:

| Field | Description |
|-------|-------------|
| `min_api_version` | Skip test if API version is below this (commonly set to 17) |
| `max_api_version` | Skip test if API version is above this |
| `test_init` | Per-test init function (overrides the global `set_test_init_function`) |
| `expected_error` | String or array of Lua patterns for expected errors |
| `inner_block_ordering` | Set to `"relaxed"` to allow sends in any order within a block |
