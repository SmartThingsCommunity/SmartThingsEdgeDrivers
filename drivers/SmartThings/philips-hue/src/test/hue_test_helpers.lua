-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"

-- File-level test modes for every Hue test file, which all require this module before the driver
-- loads: LAN driver tests run with test coroutine priority, and the driver is tested on the
-- batched capability receive path that current hubs always provide.
test.set_test_coroutine_priority(true)
test.set_capability_batch_receive(true)
local connection_scenario = require "integration_test.connection_scenario"
local http = require "integration_test.connection_scenario_http"
local capabilities = require "st.capabilities"

local HueApi = require "hue.api"

--- Shared fixture helpers for building a "known, already paired" Hue bridge + child device(s)
--- for integration tests.
---
--- The fixtures pre-populate what an earlier discovery and pairing would have left behind (the
--- bridge's network info and API key in the driver's datastore, each child's resource state in
--- `disco`'s `device_state_disco_cache`), so that the real `added`/`init` lifecycle handlers
--- resolve without discovery (covered separately in test_hue_bridge_discovery.lua). Everything
--- after that runs for real against the mock LAN socket: the bridge's network init connects its
--- event stream, and each child refreshes its state from the bridge.
---
--- `HueDeviceBuilder` builds the bridge and child devices; `create_hue_scenario` builds the
--- ConnectionScenario (the REST and SSE connections to the bridge) and the
--- `setup_*_init_expectations` helpers register what each device type requests while it
--- initializes; `wait_for_init` waits for all of that. SSE event builders (`button_event`,
--- `motion_event`, ...) build the payloads to queue with `connection_scenario_http.queue_sse_event`.
---
--- Every test also fails if a driver handler raised an error that was caught and only logged (see
--- `fail_on_caught_handler_errors`).

-- `samsungim.hueSyncMode` is defined by the platform, not the driver package; its definition
-- (fetched from the SmartThings API) lets the driver emit Hue sync mode events in tests.
test.add_capability_definition("fixtures/capabilities/samsungim.hueSyncMode.json")

local M = {}

M.BRIDGE_IP = "192.168.1.15"
M.BRIDGE_DNI = "AA:BB:CC:DD:EE:FF"
M.API_KEY = "test-api-key"

--- Errors a driver handler raised that were caught and only logged, so a test can't otherwise see
--- them: the driver's own `utils.safe_wrap_handler` and light event emitter catch errors from
--- capability command handlers and light state updates, the dispatcher catches errors from a
--- sub-driver's `can_handle`, and a device thread catches errors from its watched-socket handlers.
--- (Errors in lifecycle handlers and cosock threads already fail the test, since the test framework
--- runs the driver with `_fail_on_error`.)
local CAUGHT_HANDLER_ERROR_PATTERNS = {
  "Failed to invoke capability command handler",
  "Failed to invoke emit light status handler",
  "Encountered error calling can_handle",
  "handler on .- thread encountered error",
}

-- The caught handler errors logged during the current test, and the patterns of the ones it
-- expects (see `allow_handler_errors`).
local caught_handler_errors = {}
local allowed_handler_errors = {}

local function is_allowed_handler_error(message)
  for _, pattern in ipairs(allowed_handler_errors) do
    if message:find(pattern) then return true end
  end
  return false
end

-- Every log call reaches `log.log`: the driver's logjam module routes each level function through
-- it once the driver loads, keeping the `log.log` it found as the real printer. Wrap it before
-- the driver loads (every Hue test file requires this module first) so this sees them all.
do
  local log = require "log"
  local original_log = log.log
  log.log = function(opts, level, ...)
    if level == "error" or level == "warn" then
      local parts = table.pack(...)
      for i = 1, parts.n do parts[i] = tostring(parts[i]) end
      local message = table.concat(parts, " ", 1, parts.n)
      for _, pattern in ipairs(CAUGHT_HANDLER_ERROR_PATTERNS) do
        if message:find(pattern) and not is_allowed_handler_error(message) then
          table.insert(caught_handler_errors, message)
          break
        end
      end
    end
    return original_log(opts, level, ...)
  end
end

--- Fail the current test at its end if a driver handler raised an error that the driver or the
--- framework caught and only logged. Called from every fixture's `test_init`, so there is no need
--- to call it directly unless a test file builds its fixture by hand.
function M.fail_on_caught_handler_errors()
  caught_handler_errors = {}
  allowed_handler_errors = {}
  test.mock_lan_socket.add_end_of_test_check("hue caught handler errors", function()
    local problems = {}
    for _, message in ipairs(caught_handler_errors) do
      table.insert(problems, "a driver handler raised an error that was caught and logged: " .. message)
    end
    return problems
  end)
end

--- Let the current test's driver handlers raise errors matching `pattern` (a Lua pattern matched
--- against the logged message) without failing it, for a test that expects one.
---
--- @param pattern string
function M.allow_handler_errors(pattern)
  table.insert(allowed_handler_errors, pattern)
end


--- Whether a profile file declares a capability on any component.
local function profile_has_capability(profile_filename, capability_id)
  for _, component in pairs(t_utils.get_profile_definition(profile_filename).components or {}) do
    for _, capability in pairs(component.capabilities or {}) do
      if capability.id == capability_id then return true end
    end
  end
  return false
end

--- Expect the levelRange event `LightLifecycleHandlers.init` emits on every light's first init,
--- whether or not the light was onboarded. A light whose profile has no switchLevel (e.g. a smart
--- plug) drops the event, so nothing is expected for it. HueDeviceBuilder's `test_init` already
--- does this for its lights; only call it directly for a light device built by hand.
---
--- Must be called from `test_init` (before the driver starts), not from a test body.
---
--- @param mock_light table
--- @param profile_filename string|nil the light's profile (default: "white-and-color-ambiance.yml")
function M.expect_light_init_events(mock_light, profile_filename)
  if profile_has_capability(profile_filename or "white-and-color-ambiance.yml", capabilities.switchLevel.ID) then
    test.socket.capability:__expect_send(
      mock_light:generate_test_message("main", capabilities.switchLevel.levelRange({ minimum = 1, maximum = 100 }))
    )
  end
end

--- A Hue room resource, as the bridge reports it: its children are the Hue devices (`rtype`
--- "device") that own its lights, and its `grouped_light` service controls them together.
---
--- @param rid string the room's resource ID
--- @param grouped_light_rid string resource ID of the room's grouped_light service
--- @param device_ids string[] Hue device IDs in the room
--- @param name string|nil room name (default "Test Room")
--- @return table
function M.room_resource(rid, grouped_light_rid, device_ids, name)
  local children = {}
  for _, device_id in ipairs(device_ids) do
    table.insert(children, { rid = device_id, rtype = "device" })
  end
  return {
    id = rid,
    type = "room",
    metadata = { name = name or "Test Room", archetype = "living_room" },
    children = children,
    services = { { rid = grouped_light_rid, rtype = "grouped_light" } },
  }
end

--- A Hue zone resource, as the bridge reports it: unlike a room, its children are light resources
--- (`rtype` "light"), and its `grouped_light` service controls them together.
---
--- @param rid string the zone's resource ID
--- @param grouped_light_rid string resource ID of the zone's grouped_light service
--- @param light_rids string[] light resource IDs in the zone
--- @param name string|nil zone name (default "Test Zone")
--- @return table
function M.zone_resource(rid, grouped_light_rid, light_rids, name)
  local children = {}
  for _, light_rid in ipairs(light_rids) do
    table.insert(children, { rid = light_rid, rtype = "light" })
  end
  return {
    id = rid,
    type = "zone",
    metadata = { name = name or "Test Zone", archetype = "lounge" },
    children = children,
    services = { { rid = grouped_light_rid, rtype = "grouped_light" } },
  }
end

--- The events one refresh of a light emits for the given light resource state: its sync mode,
--- switch and level. Colour and colour temperature events aren't derived here; a light with
--- colour state passes its own `refresh_events` to `with_light`.
local function derived_light_refresh_events(state, profile)
  assert(state.color == nil and state.color_temperature == nil,
    "with_light: pass `refresh_events` for a light with colour state")
  local events = {}
  if state.mode then
    table.insert(events, capabilities["samsungim.hueSyncMode"].mode(state.mode))
  end
  if state.on then
    table.insert(events, state.on.on and capabilities.switch.switch.on() or capabilities.switch.switch.off())
  end
  if state.dimming and profile_has_capability(profile, capabilities.switchLevel.ID) then
    table.insert(events, capabilities.switchLevel.level(state.dimming.brightness))
  end
  return events
end

--- @class HueDeviceBuilder
--- Fluent API for building Hue test fixtures with sensible defaults.
--- Provides a clean, declarative way to set up bridge + child devices for tests.
local HueDeviceBuilder = {}
HueDeviceBuilder.__index = HueDeviceBuilder

--- Create a new HueDeviceBuilder instance.
---
--- @return HueDeviceBuilder
local function new_builder()
  local instance = {
    bridge_ip = M.BRIDGE_IP,
    bridge_dni = M.BRIDGE_DNI,
    api_key = M.API_KEY,
    children = {},  -- Array of child device configs
    rooms = {},
    zones = {},
  }
  return setmetatable(instance, HueDeviceBuilder)
end

M.HueDeviceBuilder = { new = new_builder }

--- Configure the bridge (optional - uses sensible defaults).
---
--- @param ip string|nil bridge IP (default: hue_test_helpers.BRIDGE_IP)
--- @param dni string|nil device network ID (default: hue_test_helpers.BRIDGE_DNI)
--- @param key string|nil API key (default: hue_test_helpers.API_KEY)
--- @return HueDeviceBuilder self for chaining
function HueDeviceBuilder:with_bridge(ip, dni, key)
  if ip then self.bridge_ip = ip end
  if dni then self.bridge_dni = dni end
  if key then self.api_key = key end
  return self
end

--- Add a light device to the fixture.
---
--- @param rid string Hue resource ID for the light
--- @param state table|nil initial state with fields matching Hue API format:
---   - on: table with 'on' field (default: {on=true})
---   - dimming: table with 'brightness' field (default: {brightness=100})
---   - color: table with xy and gamut (optional)
---   - color_temperature: table with mirek and schema (optional)
---   - mode: string (default: "normal")
---   - hue_device_id: string (default: rid.."-device")
---   - zigbee_rid: the device's zigbee_connectivity resource ID (default: rid.."-zigbee")
---   - label: string (default: "Hue Light")
---   - refresh_events: function(first_refresh) returning the capability events one refresh of the
---     light emits (default: derived from mode/on/dimming; required for a light with colour state)
--- @param profile string|nil profile filename (default: "white-and-color-ambiance.yml")
--- @return HueDeviceBuilder self for chaining
function HueDeviceBuilder:with_light(rid, state, profile)
  state = state or {}
  local device_id = state.hue_device_id or (rid .. "-device")
  profile = profile or "white-and-color-ambiance.yml"

  -- Build discovery cache state for the light
  local disco_state = {
    hue_provided_name = state.label or "Hue Light",
    id = rid,
    on = state.on or { on = true },
    color = state.color,
    dimming = state.dimming or { brightness = 100 },
    color_temperature = state.color_temperature,
    mode = state.mode or "normal",
    hue_device_id = device_id,
    hue_device_data = {
      product_data = {
        manufacturer_name = "Signify Netherlands B.V.",
        model_id = "TEST",
        product_name = state.label or "Hue Light",
      },
    },
  }

  local refresh_events = state.refresh_events
  if not refresh_events then
    refresh_events = function() return derived_light_refresh_events(disco_state, profile) end
  end

  table.insert(self.children, {
    type = "light",
    rid = rid,
    profile = profile,
    state = disco_state,
    zigbee_rid = state.zigbee_rid or (rid .. "-zigbee"),
    refresh_events = refresh_events,
  })
  return self
end

--- Add a button device to the fixture.
---
--- @param rid string Hue resource ID for the first button
--- @param config table configuration with:
---   - num_buttons: number of buttons (default 1)
---   - battery: battery level (default 85)
---   - label: device label (default "Hue Button")
---   - device_id: device ID (default: rid .. "-device")
---   - power_rid: power resource ID (default: rid .. "-power")
---   - zigbee_rid: zigbee_connectivity resource ID (default: rid .. "-zigbee")
---   - button_rids: array of button RIDs (default: {rid, ...})
--- @param profile string|nil profile filename (auto-selected based on num_buttons)
--- @return HueDeviceBuilder self for chaining
function HueDeviceBuilder:with_button(rid, config, profile)
  config = config or {}
  local num_buttons = config.num_buttons or 1
  local device_id = config.device_id or (rid .. "-device")
  local power_rid = config.power_rid or (rid .. "-power")

  -- Build button RIDs array
  local button_rids = config.button_rids or {rid}
  if #button_rids < num_buttons then
    for i = #button_rids + 1, num_buttons do
      table.insert(button_rids, rid .. "-button" .. i)
    end
  end

  -- Auto-select profile based on number of buttons
  if not profile then
    if num_buttons == 1 then
      profile = "single-button.yml"
    elseif num_buttons == 4 then
      profile = "4-button-remote.yml"
    else
      profile = "single-button.yml"  -- fallback
    end
  end

  -- Build state table
  local state = {
    id = rid,
    hue_provided_name = config.label or "Hue Button",
    hue_device_id = device_id,
    num_buttons = num_buttons,
    power_state = { battery_level = config.battery or 85 },
    power_id = power_rid,
  }

  -- Add button-specific fields
  for i = 1, num_buttons do
    state["button" .. i] = {
      event_values = config.event_values or { "short_release", "long_press", "long_release" }
    }
    state["button" .. i .. "_id"] = button_rids[i]
  end

  table.insert(self.children, {
    type = "button",
    rid = rid,
    profile = profile,
    state = state,
    num_buttons = num_buttons,
    battery = config.battery or 85,
    zigbee_rid = config.zigbee_rid or (rid .. "-zigbee"),
  })
  return self
end

--- Add a motion sensor to the fixture.
---
--- @param rid string Hue resource ID for the motion sensor
--- @param config table|nil configuration with:
---   - battery: battery level (default 85)
---   - motion: initial motion state (default false)
---   - temperature: temperature in Celsius (default 20.0)
---   - light_level: light level (default 30000)
---   - label: device label (default "Hue Motion Sensor")
---   - device_id: device ID (default: rid .. "-device")
---   - power_rid: power resource ID (default: rid .. "-power")
---   - zigbee_rid: zigbee_connectivity resource ID (default: rid .. "-zigbee")
---   - temperature_rid: temperature resource ID (default: rid .. "-temp")
---   - light_level_rid: light level resource ID (default: rid .. "-light")
--- @return HueDeviceBuilder self for chaining
function HueDeviceBuilder:with_motion(rid, config)
  config = config or {}
  local device_id = config.device_id or (rid .. "-device")
  local power_rid = config.power_rid or (rid .. "-power")
  local temperature_rid = config.temperature_rid or (rid .. "-temp")
  local light_level_rid = config.light_level_rid or (rid .. "-light")

  -- Build discovery cache state for the motion sensor
  local state = {
    id = rid,
    hue_provided_name = config.label or "Hue Motion Sensor",
    hue_device_id = device_id,
    motion = { motion = config.motion or false, motion_valid = true },
    motion_enabled = true,
    temperature = { temperature = config.temperature or 20.0, temperature_valid = true },
    temperature_id = temperature_rid,
    temperature_enabled = true,
    light = { light_level = config.light_level or 30000, light_level_valid = true },
    light_level_id = light_level_rid,
    light_level_enabled = true,
    power_state = { battery_level = config.battery or 85 },
    power_id = power_rid,
    sensor_list = {
      id = "motion",
      power_id = "device_power",
      temperature_id = "temperature",
      light_level_id = "light_level"
    }
  }

  table.insert(self.children, {
    type = "motion",
    rid = rid,
    profile = "motion-sensor.yml",
    state = state,
    battery = config.battery or 85,
    motion = config.motion or false,
    temperature = config.temperature or 20.0,
    light_level = config.light_level or 30000,
    zigbee_rid = config.zigbee_rid or (rid .. "-zigbee"),
  })
  return self
end

--- Add a contact sensor to the fixture.
---
--- @param rid string Hue resource ID for the contact sensor
--- @param config table|nil configuration with:
---   - battery: battery level (default 85)
---   - contact_state: initial contact state "contact"=closed, "no_contact"=open (default "contact")
---   - tamper: tamper state (default "not_tampered")
---   - label: device label (default "Hue Contact Sensor")
---   - device_id: device ID (default: rid .. "-device")
---   - power_rid: power resource ID (default: rid .. "-power")
---   - zigbee_rid: zigbee_connectivity resource ID (default: rid .. "-zigbee")
---   - tamper_rid: tamper resource ID (default: rid .. "-tamper")
--- @return HueDeviceBuilder self for chaining
function HueDeviceBuilder:with_contact(rid, config)
  config = config or {}
  local device_id = config.device_id or (rid .. "-device")
  local power_rid = config.power_rid or (rid .. "-power")
  local tamper_rid = config.tamper_rid or (rid .. "-tamper")

  -- Build discovery cache state for the contact sensor
  local state = {
    id = rid,
    hue_provided_name = config.label or "Hue Contact Sensor",
    hue_device_id = device_id,
    contact_report = { state = config.contact_state or "contact" },  -- "contact" = closed, "no_contact" = open
    contact_enabled = true,
    tamper_reports = { { state = config.tamper or "not_tampered" } },
    tamper_id = tamper_rid,
    power_state = { battery_level = config.battery or 85 },
    power_id = power_rid,
    sensor_list = {
      id = "contact",
      power_id = "device_power",
      tamper_id = "tamper"
    }
  }

  table.insert(self.children, {
    type = "contact",
    rid = rid,
    profile = "contact-sensor.yml",
    state = state,
    battery = config.battery or 85,
    contact_state = config.contact_state or "contact",
    tamper = config.tamper or "not_tampered",
    zigbee_rid = config.zigbee_rid or (rid .. "-zigbee"),
  })
  return self
end

--- Add a Hue room containing some of this fixture's lights. The bridge reports it (as
--- `fixtures.rooms`, for `create_hue_scenario`'s `rooms` option) to the driver's room scan.
---
--- @param rid string Hue resource ID for the room
--- @param grouped_light_rid string resource ID of the room's grouped_light service
--- @param light_rids string[] resource IDs of lights (added with `with_light`) in the room
--- @param name string|nil room name (default "Test Room")
--- @return HueDeviceBuilder self for chaining
function HueDeviceBuilder:with_room(rid, grouped_light_rid, light_rids, name)
  table.insert(self.rooms, { rid = rid, grouped_light_rid = grouped_light_rid, light_rids = light_rids, name = name })
  return self
end

--- Add a Hue zone containing some of this fixture's lights. The bridge reports it (as
--- `fixtures.zones`, for `create_hue_scenario`'s `zones` option) to the driver's zone scan.
---
--- @param rid string Hue resource ID for the zone
--- @param grouped_light_rid string resource ID of the zone's grouped_light service
--- @param light_rids string[] resource IDs of lights (added with `with_light`) in the zone
--- @param name string|nil zone name (default "Test Zone")
--- @return HueDeviceBuilder self for chaining
function HueDeviceBuilder:with_zone(rid, grouped_light_rid, light_rids, name)
  table.insert(self.zones, { rid = rid, grouped_light_rid = grouped_light_rid, light_rids = light_rids, name = name })
  return self
end

--- Have the fixture's `test_init` expect the events of the refreshes each light's `added` and
--- `init` handlers inject (see `with_light`'s `refresh_events`), for a test that answers them with
--- `setup_light_init_expectations`. Without it the test registers those events itself.
---
--- @return HueDeviceBuilder self for chaining
function HueDeviceBuilder:expect_light_init_refreshes()
  self.light_init_refreshes = true
  return self
end

--- Build the fixture and return a structured fixtures object.
---
--- The bridge is one the driver has already found and paired with: its network info (with a
--- software version that supports the CLIP v2 API) and API key are in the driver's datastore, so
--- its `init` runs the real network init right away, which connects the bridge's event stream.
--- Each child's resource state is in the discovery cache, so its `added` and `init` resolve
--- without discovery; they then refresh it from the bridge as in production. The test's
--- ConnectionScenario must answer all of that (`create_hue_scenario`, `setup_sse_expectations`
--- and the `setup_*_init_expectations` / `expect_light_init_refreshes` helpers).
---
--- @return table fixtures with fields:
---   - bridge: mock bridge device
---   - devices: array of mock child devices
---   - test_init: function to pass to test.set_test_init_function
---   - configs: table of device configs by type (button, light, motion, contact)
---   - rooms, zones: the bridge's room and zone resources (see `with_room`, `with_zone`)
---   - driver_device: function(mock_device) returning the driver's own device object
function HueDeviceBuilder:start()
  local mock_bridge = test.mock_device.build_test_lan_device({
    label = "Hue Bridge",
    profile = t_utils.get_profile_definition("hue-bridge.yml"),
    device_network_id = self.bridge_dni,
  })

  local mock_children = {}
  for _, child_config in ipairs(self.children) do
    local child_template = {
      label = child_config.state.hue_provided_name,
      profile = t_utils.get_profile_definition(child_config.profile),
      parent_assigned_child_key = child_config.type .. ":" .. child_config.rid,
      parent_device_id = mock_bridge.id,
    }
    table.insert(mock_children, test.mock_device.build_test_lan_device(child_template))
  end

  local driver_under_test = nil
  test.add_test_env_setup_func(function(driver)
    driver_under_test = driver
    driver.datastore.bridge_netinfo = driver.datastore.bridge_netinfo or {}
    driver.datastore.bridge_netinfo[self.bridge_dni] = {
      ip = self.bridge_ip,
      swversion = tostring(HueApi.MIN_CLIP_V2_SWVERSION),
      modelid = "BSB002"
    }
    -- The bridge was found on the network during this run of the driver (as when it has just
    -- been onboarded), so its init doesn't have to wait for its network info.
    driver.joined_bridges[self.bridge_dni] = true
    driver.datastore.api_keys = driver.datastore.api_keys or {}
    driver.datastore.api_keys[self.bridge_dni] = self.api_key

    local disco = require "disco"
    disco.disco_api_instances = {}
    -- Discovery is still running (as when the devices have just been onboarded), so the event
    -- stream connecting doesn't also start a scan of every device on the bridge.
    disco.discovery_active = true

    -- Populate disco cache with child device states
    for _, child_config in ipairs(self.children) do
      child_config.state.parent_device_id = mock_bridge.id
      disco.device_state_disco_cache[child_config.rid] = child_config.state
    end
  end)

  local function expect_events(mock_device, events)
    for _, event in ipairs(events) do
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", event))
    end
  end

  local function test_init()
    M.fail_on_caught_handler_errors()
    test.mock_device.add_test_device(mock_bridge)
    for _, mock_child in ipairs(mock_children) do
      test.mock_device.add_test_device(mock_child)
    end

    -- The events each child emits while it initializes.
    for i, child_config in ipairs(self.children) do
      local mock_child = mock_children[i]

      if child_config.type == "button" then
        -- supportedButtonValues for each button's component, then the refresh's battery level.
        local components = {"main"}
        for j = 2, child_config.num_buttons do
          table.insert(components, "button" .. j)
        end
        for _, component in ipairs(components) do
          test.socket.capability:__expect_send(
            mock_child:generate_test_message(component,
              capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false } })
            )
          )
        end
        expect_events(mock_child, { capabilities.battery.battery(child_config.battery) })

      elseif child_config.type == "motion" then
        -- The refresh's state, in the order the driver emits it. Illuminance from light_level: lux = round(10^((light_level - 1) / 10000)).
        local lux = math.floor(10 ^ ((child_config.light_level - 1) / 10000) + 0.5)
        expect_events(mock_child, {
          capabilities.battery.battery(child_config.battery),
          capabilities.temperatureMeasurement.temperature({ value = child_config.temperature, unit = "C" }),
          capabilities.illuminanceMeasurement.illuminance(lux),
          capabilities.motionSensor.motion[child_config.motion and "active" or "inactive"](),
        })

      elseif child_config.type == "contact" then
        -- The refresh's state, in the order the driver emits it.
        expect_events(mock_child, {
          capabilities.battery.battery(child_config.battery),
          capabilities.tamperAlert.tamper[child_config.tamper == "tampered" and "detected" or "clear"](),
          capabilities.contactSensor.contact[child_config.contact_state == "no_contact" and "open" or "closed"](),
        })

      elseif child_config.type == "light" then
        -- Unless the test registers them itself, the refreshes the light's `added` and `init`
        -- inject, around init's levelRange.
        if self.light_init_refreshes then
          expect_events(mock_child, child_config.refresh_events(true))
        end
        M.expect_light_init_events(mock_child, child_config.profile)
        if self.light_init_refreshes then
          expect_events(mock_child, child_config.refresh_events(false))
        end
      end
    end
  end

  -- Build configuration objects for each device type
  local configs = {}
  for _, child_config in ipairs(self.children) do
    local device_key = child_config.type
    if not configs[device_key] then
      configs[device_key] = {}
    end

    -- Build config based on device type
    if child_config.type == "button" then
      local button_rids = {}
      for j = 1, child_config.num_buttons do
        table.insert(button_rids, child_config.state["button" .. j .. "_id"])
      end
      table.insert(configs[device_key], {
        rid = child_config.rid,
        device_id = child_config.state.hue_device_id,
        label = child_config.state.hue_provided_name,
        num_buttons = child_config.num_buttons,
        battery = child_config.battery,
        power_rid = child_config.state.power_id,
        zigbee_rid = child_config.zigbee_rid,
        button_rids = button_rids,
      })

    elseif child_config.type == "light" then
      table.insert(configs[device_key], {
        rid = child_config.rid,
        device_id = child_config.state.hue_device_id,
        label = child_config.state.hue_provided_name,
        zigbee_rid = child_config.zigbee_rid,
        on = child_config.state.on,
        dimming = child_config.state.dimming,
        color = child_config.state.color,
        color_temperature = child_config.state.color_temperature,
        mode = child_config.state.mode
      })

    elseif child_config.type == "motion" then
      table.insert(configs[device_key], {
        rid = child_config.rid,
        device_id = child_config.state.hue_device_id,
        label = child_config.state.hue_provided_name,
        battery = child_config.battery,
        motion = child_config.motion,
        temperature = child_config.temperature,
        light_level = child_config.light_level,
        power_rid = child_config.state.power_id,
        zigbee_rid = child_config.zigbee_rid,
        temperature_rid = child_config.state.temperature_id,
        light_level_rid = child_config.state.light_level_id
      })

    elseif child_config.type == "contact" then
      table.insert(configs[device_key], {
        rid = child_config.rid,
        device_id = child_config.state.hue_device_id,
        label = child_config.state.hue_provided_name,
        battery = child_config.battery,
        contact_state = child_config.contact_state,
        tamper = child_config.tamper,
        power_rid = child_config.state.power_id,
        zigbee_rid = child_config.zigbee_rid,
        tamper_rid = child_config.state.tamper_id
      })
    end
  end

  local hue_device_id_by_rid = {}
  for _, child_config in ipairs(self.children) do
    hue_device_id_by_rid[child_config.rid] = child_config.state.hue_device_id
  end

  local room_resources = {}
  for _, room in ipairs(self.rooms) do
    local device_ids = {}
    for _, light_rid in ipairs(room.light_rids) do
      table.insert(device_ids, (assert(hue_device_id_by_rid[light_rid], "with_room: unknown light " .. light_rid)))
    end
    table.insert(room_resources, M.room_resource(room.rid, room.grouped_light_rid, device_ids, room.name))
  end
  local zone_resources = {}
  for _, zone in ipairs(self.zones) do
    table.insert(zone_resources, M.zone_resource(zone.rid, zone.grouped_light_rid, zone.light_rids, zone.name))
  end

  --- The driver's own device object for a mock device, e.g. to inspect its device fields.
  --- Must be called from within a test.
  local function driver_device(mock_device)
    return driver_under_test:get_device_info(mock_device.id)
  end

  -- Return structured fixtures object
  return {
    bridge = mock_bridge,
    devices = mock_children,
    test_init = test_init,
    configs = configs,
    rooms = room_resources,
    zones = zone_resources,
    driver_device = driver_device,
  }
end

--- ConnectionScenario helpers

--- Create a ConnectionScenario for the fixture's bridge: a REST connection for its CLIP v2
--- resources and the SSE connection for its event stream.
---
--- @param options table|nil Configuration options:
---   - host: Bridge IP (default: hue_test_helpers.BRIDGE_IP)
---   - port: Bridge port (default: 443)
---   - rooms: Hue room resources the bridge reports to the driver's group scans (default: none),
---     e.g. `fixtures.rooms` from a HueDeviceBuilder with `with_room`
---   - zones: Hue zone resources, likewise (e.g. `fixtures.zones`)
--- @return table scenario The ConnectionScenario instance
--- @return table connections `{ rest = ..., sse = ... }`
function M.create_hue_scenario(options)
  options = options or {}

  local scenario = connection_scenario.new({
    host = options.host or M.BRIDGE_IP,
    port = options.port or 443
  })

  local connections = {}
  connections.rest = scenario:connection("rest", {
    matcher = http.matcher({ "GET", "PUT" }, "^/clip/v2/resource/"),
    ordering = "relaxed"
  })
  -- The driver scans the bridge's rooms and zones (debounced) after lights are added and after
  -- the event stream connects.
  http.expect_request(connections.rest, "GET", "/clip/v2/resource/room", {
    body = { errors = {}, data = options.rooms or {} },
    reusable = true,
  })
  http.expect_request(connections.rest, "GET", "/clip/v2/resource/zone", {
    body = { errors = {}, data = options.zones or {} },
    reusable = true,
  })
  connections.sse = scenario:connection("sse", {
    matcher = http.matcher("GET", "^/eventstream/clip/v2")
  })

  return scenario, connections
end

--- Setup test_init function with scenario activation.
---
--- @param base_test_init function The base test_init function returned by HueDeviceBuilder
--- @param scenario table The ConnectionScenario instance
--- @param additional_setup function|nil Optional additional setup to run after scenario:activate()
---   (so expectations it registers are test-scoped)
function M.setup_scenario_test_init(base_test_init, scenario, additional_setup)
  local function test_init()
    base_test_init()
    scenario:activate()
    if additional_setup then
      additional_setup()
    end
  end
  test.set_test_init_function(test_init)
end

--- Expect a GET of one of the bridge's CLIP v2 resources (GET /clip/v2/resource/{rtype}/{rid}),
--- answered with that resource.
---
--- @param connection table The REST connection handle
--- @param rtype string The resource type, e.g. "device", "zigbee_connectivity", "light"
--- @param rid string The resource ID
--- @param data table|nil The resource's fields besides `type` and `id`, e.g. `{ on = { on = true } }`
--- @param options table|nil Options:
---   - status: HTTP status (default: 200)
---   - reusable: Make expectation reusable (default: false)
---   - times: How many requests a single-use expectation answers (default: 1)
function M.expect_resource(connection, rtype, rid, data, options)
  options = options or {}
  local resource = { type = rtype, id = rid }
  for k, v in pairs(data or {}) do resource[k] = v end
  return http.expect_request(connection, "GET", "/clip/v2/resource/" .. rtype .. "/" .. rid, {
    status = options.status or 200,
    body = { errors = {}, data = { resource } },
    reusable = options.reusable,
    times = options.times,
  })
end

--- Expect a GET of a Hue device (GET /clip/v2/resource/device/{id}), as a refresh makes to find the
--- device's zigbee_connectivity service.
---
--- @param connection table The REST connection handle
--- @param device_id string The Hue device ID
--- @param services table Array of the device's services, e.g. `{ { rtype = "light", rid = ... } }`
--- @param options table|nil `expect_resource` options, plus `name` and `product_data`
function M.expect_device_info(connection, device_id, services, options)
  options = options or {}
  return M.expect_resource(connection, "device", device_id, {
    metadata = { name = options.name or "Device" },
    product_data = options.product_data,
    services = services,
  }, options)
end

--- Expect a GET of a Hue device's zigbee_connectivity resource, reporting it connected.
---
--- @param connection table The REST connection handle
--- @param zigbee_rid string The zigbee_connectivity resource ID
--- @param owner string The ID of the Hue device that owns it
--- @param options table|nil `expect_resource` options, plus `status_value` (default "connected")
function M.expect_zigbee_connectivity(connection, zigbee_rid, owner, options)
  options = options or {}
  return M.expect_resource(connection, "zigbee_connectivity", zigbee_rid, {
    owner = { rid = owner, rtype = "device" },
    status = options.status_value or "connected",
  }, options)
end

--- A light resource response (`{ errors = {}, data = { light } }`) for a light added with
--- `with_light`, from its `fixtures.configs.light` entry.
---
--- @param light_config table
--- @return table
function M.light_resource(light_config)
  return { errors = {}, data = { {
    type = "light",
    id = light_config.rid,
    owner = { rid = light_config.device_id, rtype = "device" },
    metadata = { name = light_config.label },
    on = light_config.on,
    dimming = light_config.dimming,
    color = light_config.color,
    color_temperature = light_config.color_temperature,
    mode = light_config.mode,
  } } }
end

--- Wait until the fixture's devices have initialized: the bridge's event stream has connected
--- (which marks the bridge online) and every request expected so far (the scenario's single-use
--- expectations, e.g. those registered by the `setup_*_init_expectations` helpers) has been made.
---
--- @param scenario table The ConnectionScenario instance
--- @param mock_bridge table
function M.wait_for_init(scenario, mock_bridge)
  local function all_requests_made()
    for _, label in ipairs({ "rest", "sse" }) do
      if #scenario:get_connection(label):unsatisfied_expectations() > 0 then return false end
    end
    return true
  end
  test.wait_until(function()
    return test.mock_devices_api.__is_device_online(mock_bridge.id) == true and all_requests_made()
  end, { message = "the bridge's event stream connecting and the devices' init requests being made" })
  scenario:get_connection("sse"):assert_sent("^GET /eventstream/clip/v2 HTTP/1.1\r\n")
  test.wait_for_events()
end

--- Setup SSE connection expectations: the handshake and the connectivity scan the driver makes
--- once the stream connects.
---
--- @param sse_connection table The SSE connection handle
--- @param rest_connection table The REST connection handle
--- @param options table|nil Options:
---   - handshake_reusable: Make handshake expectation reusable (default: true)
---   - poll_reusable: Make connectivity poll expectation reusable (default: false)
function M.setup_sse_expectations(sse_connection, rest_connection, options)
  options = options or {}
  -- SSE handshake
  http.expect_sse_handshake(sse_connection, "/eventstream/clip/v2", options.handshake_reusable ~= false)

  -- Connectivity poll after SSE opens
  http.expect_request(rest_connection, "GET", "/clip/v2/resource/zigbee_connectivity", {
    status = 200,
    body = {
      errors = {},
      data = {{ type = "zigbee_connectivity", status = "connected" }}
    },
    reusable = options.poll_reusable
  })
end

--- SSE Event Builders
--- These helpers create properly structured SSE event tables

--- Create a button SSE event.
---
--- @param button_rid string The button resource ID
--- @param event_type string Event type: "short_release", "long_press", "long_release", etc.
--- @param options table|nil Options:
---   - timestamp: Event timestamp (default: "2024-01-01T12:00:00Z")
---   - update_type: Event type wrapper (default: "update")
--- @return table SSE event structure
function M.button_event(button_rid, event_type, options)
  options = options or {}

  local button_data = {
    type = "button",
    id = button_rid,
    button = {
      button_report = {
        event = event_type,
        updated = options.timestamp or "2024-01-01T12:00:00Z"
      }
    }
  }

  return {
    type = options.update_type or "update",
    data = { button_data }
  }
end

--- Create a motion sensor SSE event.
---
--- @param motion_rid string The motion sensor resource ID
--- @param is_active boolean Motion detected state
--- @param options table|nil Options:
---   - motion_valid: Motion valid flag (default: true)
---   - update_type: Event type wrapper (default: "update")
--- @return table SSE event structure
function M.motion_event(motion_rid, is_active, options)
  options = options or {}

  local motion_data = {
    type = "motion",
    id = motion_rid,
    motion = {
      motion = is_active,
      motion_valid = options.motion_valid ~= false
    }
  }

  return {
    type = options.update_type or "update",
    data = { motion_data }
  }
end

--- Create a contact sensor SSE event.
---
--- @param contact_rid string The contact sensor resource ID
--- @param state string Contact state: "contact" (closed) or "no_contact" (open)
--- @param options table|nil Options:
---   - tamper_state: Include tamper state in event
---   - update_type: Event type wrapper (default: "update")
--- @return table SSE event structure
function M.contact_event(contact_rid, state, options)
  options = options or {}

  local contact_data = {
    type = "contact",
    id = contact_rid,
    contact_report = { state = state }
  }

  if options.tamper_state then
    contact_data.tamper_reports = {{ state = options.tamper_state }}
  end

  return {
    type = options.update_type or "update",
    data = { contact_data }
  }
end

--- Create a tamper sensor SSE event.
---
--- @param tamper_rid string The tamper sensor resource ID
--- @param state string Tamper state: "tampered" or "not_tampered"
--- @param options table|nil Options:
---   - update_type: Event type wrapper (default: "update")
--- @return table SSE event structure
function M.tamper_event(tamper_rid, state, options)
  options = options or {}

  return {
    type = options.update_type or "update",
    data = {{
      type = "tamper",
      id = tamper_rid,
      tamper_reports = {{ state = state }}
    }}
  }
end

--- Create a light SSE event.
---
--- Like the bridge's own updates, it only carries what changed: pass `nil` for `on_state` (or
--- `brightness`) to leave it out, e.g. for a dimming-only update.
---
--- @param light_rid string The light resource ID
--- @param on_state boolean|nil Light on/off state, or nil to leave it out
--- @param brightness number|nil Brightness level (0-100)
--- @param options table|nil Options:
---   - color: Color object with xy coordinates
---   - color_temperature: Color temperature object with mirek
---   - update_type: Event type wrapper (default: "update")
--- @return table SSE event structure
function M.light_event(light_rid, on_state, brightness, options)
  options = options or {}

  local light_data = {
    type = "light",
    id = light_rid,
  }

  if on_state ~= nil then
    light_data.on = { on = on_state }
  end

  if brightness then
    light_data.dimming = { brightness = brightness }
  end

  if options.color then
    light_data.color = options.color
  end

  if options.color_temperature then
    light_data.color_temperature = options.color_temperature
  end

  return {
    type = options.update_type or "update",
    data = { light_data }
  }
end

--- Create a device power (battery) SSE event. Battery levels come from a sensor's `device_power`
--- resource, not from its button, motion or contact resource.
---
--- @param power_rid string The device power resource ID
--- @param owner_device_id string The Hue device ID that owns the resource
--- @param battery_level number Battery level (0-100)
--- @param options table|nil Options:
---   - battery_state: Battery state (default: "normal")
---   - update_type: Event type wrapper (default: "update")
--- @return table SSE event structure
function M.device_power_event(power_rid, owner_device_id, battery_level, options)
  options = options or {}

  return {
    type = options.update_type or "update",
    data = {{
      type = "device_power",
      id = power_rid,
      owner = { rid = owner_device_id, rtype = "device" },
      power_state = { battery_level = battery_level, battery_state = options.battery_state or "normal" },
    }}
  }
end

--- Combine several SSE events of the same type into one, as the bridge does when several of a
--- device's resources change together (e.g. a sensor's motion and battery level).
---
--- @param ... table SSE events from the builders above
--- @return table SSE event structure
function M.combined_event(...)
  local combined = { type = nil, data = {} }
  for _, event in ipairs({ ... }) do
    combined.type = combined.type or event.type
    assert(event.type == combined.type, "only events of the same type can be combined")
    for _, resource in ipairs(event.data) do
      table.insert(combined.data, resource)
    end
  end
  return combined
end

--- Create a temperature sensor SSE event.
---
--- @param temperature_rid string The temperature sensor resource ID
--- @param temperature number Temperature in Celsius
--- @param options table|nil Options:
---   - temperature_valid: Temperature valid flag (default: true)
---   - update_type: Event type wrapper (default: "update")
--- @return table SSE event structure
function M.temperature_event(temperature_rid, temperature, options)
  options = options or {}

  return {
    type = options.update_type or "update",
    data = {{
      type = "temperature",
      id = temperature_rid,
      temperature = {
        temperature = temperature,
        temperature_valid = options.temperature_valid ~= false
      }
    }}
  }
end

--- Create a light level sensor SSE event.
---
--- @param light_level_rid string The light level sensor resource ID
--- @param light_level number Light level value
--- @param options table|nil Options:
---   - light_level_valid: Light level valid flag (default: true)
---   - update_type: Event type wrapper (default: "update")
--- @return table SSE event structure
function M.light_level_event(light_level_rid, light_level, options)
  options = options or {}

  return {
    type = options.update_type or "update",
    data = {{
      type = "light_level",
      id = light_level_rid,
      light = {
        light_level = light_level,
        light_level_valid = options.light_level_valid ~= false
      }
    }}
  }
end

--- Helper to escape a Hue UUID for use in Lua pattern matching.
--- Converts: "11111111-1111-1111-1111-111111111111"
--- To: "11111111%-1111%-1111%-1111%-111111111111"
---
--- @param uuid string The UUID to escape
--- @return string Escaped UUID suitable for Lua patterns
function M.escape_uuid(uuid)
  return uuid:gsub("%-", "%%-")
end

--- Device-Type-Specific Init Expectation Setup Helpers
--- Each registers the requests a device of that type makes while it initializes, answered with the
--- state its `fixtures.configs` entry describes. Register them at file level.

--- A device's device_power resource fields.
local function device_power(config)
  return {
    owner = { rid = config.device_id, rtype = "device" },
    power_state = { battery_level = config.battery, battery_state = "normal" },
  }
end

--- Setup the init-time requests for a light: its two refreshes (injected by its `added` and
--- `init` handlers), each a GET of its device, its zigbee_connectivity and its light resource.
--- Pair with the builder's `expect_light_init_refreshes` for the events they emit.
---
--- @param rest_connection table The REST connection handle
--- @param light_config table The light's `fixtures.configs.light` entry
--- @param options table|nil Options:
---   - light_resource: the light resource response (default: `light_resource(light_config)`)
function M.setup_light_init_expectations(rest_connection, light_config, options)
  options = options or {}
  -- Reusable: a later refresh makes these requests too.
  M.expect_device_info(rest_connection, light_config.device_id, {
    { rtype = "zigbee_connectivity", rid = light_config.zigbee_rid },
    { rtype = "light", rid = light_config.rid },
  }, { name = light_config.label, reusable = true })
  M.expect_zigbee_connectivity(rest_connection, light_config.zigbee_rid, light_config.device_id, { reusable = true })
  http.expect_request(rest_connection, "GET", "/clip/v2/resource/light/" .. light_config.rid, {
    body = options.light_resource or M.light_resource(light_config),
    times = 2,
  })
end

--- Setup the init-time requests for a button device: its device, zigbee connectivity, button
--- resources and device power, plus the event stream's (if `sse_connection` is given).
---
--- @param rest_connection table The REST connection handle
--- @param sse_connection table|nil The SSE connection handle, to also expect the event stream
--- @param button_config table The button's `fixtures.configs.button` entry
function M.setup_button_init_expectations(rest_connection, sse_connection, button_config)
  local services = {
    { rtype = "zigbee_connectivity", rid = button_config.zigbee_rid },
    { rtype = "device_power", rid = button_config.power_rid },
  }
  for _, button_rid in ipairs(button_config.button_rids) do
    table.insert(services, { rtype = "button", rid = button_rid })
  end
  M.expect_device_info(rest_connection, button_config.device_id, services, {
    name = button_config.label,
    product_data = { product_name = button_config.label },
    reusable = true,
  })
  M.expect_zigbee_connectivity(rest_connection, button_config.zigbee_rid, button_config.device_id)
  for i, button_rid in ipairs(button_config.button_rids) do
    M.expect_resource(rest_connection, "button", button_rid, {
      owner = { rid = button_config.device_id, rtype = "device" },
      metadata = { control_id = i },
      button = {
        button_report = { event = "initial_press", updated = "2024-01-01T00:00:00Z" },
        event_values = { "short_release", "long_press", "long_release" },
      },
    })
  end
  M.expect_resource(rest_connection, "device_power", button_config.power_rid, device_power(button_config))
  if sse_connection then
    M.setup_sse_expectations(sse_connection, rest_connection)
  end
end

--- Setup the init-time requests for a motion sensor: its device, zigbee connectivity, motion,
--- temperature, light level and device power resources, plus the event stream's (if
--- `sse_connection` is given).
---
--- @param rest_connection table The REST connection handle
--- @param sse_connection table|nil The SSE connection handle, to also expect the event stream
--- @param motion_config table The sensor's `fixtures.configs.motion` entry
function M.setup_motion_init_expectations(rest_connection, sse_connection, motion_config)
  local owner = { rid = motion_config.device_id, rtype = "device" }
  M.expect_device_info(rest_connection, motion_config.device_id, {
    { rtype = "zigbee_connectivity", rid = motion_config.zigbee_rid },
    { rtype = "motion", rid = motion_config.rid },
    { rtype = "temperature", rid = motion_config.temperature_rid },
    { rtype = "light_level", rid = motion_config.light_level_rid },
    { rtype = "device_power", rid = motion_config.power_rid },
  }, { name = motion_config.label, reusable = true })
  M.expect_zigbee_connectivity(rest_connection, motion_config.zigbee_rid, motion_config.device_id)
  M.expect_resource(rest_connection, "motion", motion_config.rid,
    { owner = owner, enabled = true, motion = { motion = motion_config.motion, motion_valid = true } })
  M.expect_resource(rest_connection, "temperature", motion_config.temperature_rid,
    { owner = owner, enabled = true, temperature = { temperature = motion_config.temperature, temperature_valid = true } })
  M.expect_resource(rest_connection, "light_level", motion_config.light_level_rid,
    { owner = owner, enabled = true, light = { light_level = motion_config.light_level, light_level_valid = true } })
  M.expect_resource(rest_connection, "device_power", motion_config.power_rid, device_power(motion_config))
  if sse_connection then
    M.setup_sse_expectations(sse_connection, rest_connection)
  end
end

--- Setup the init-time requests for a contact sensor: its device, zigbee connectivity, contact,
--- tamper and device power resources, plus the event stream's (if `sse_connection` is given).
---
--- @param rest_connection table The REST connection handle
--- @param sse_connection table|nil The SSE connection handle, to also expect the event stream
--- @param contact_config table The sensor's `fixtures.configs.contact` entry
function M.setup_contact_init_expectations(rest_connection, sse_connection, contact_config)
  local owner = { rid = contact_config.device_id, rtype = "device" }
  M.expect_device_info(rest_connection, contact_config.device_id, {
    { rtype = "zigbee_connectivity", rid = contact_config.zigbee_rid },
    { rtype = "contact", rid = contact_config.rid },
    { rtype = "tamper", rid = contact_config.tamper_rid },
    { rtype = "device_power", rid = contact_config.power_rid },
  }, { name = contact_config.label, reusable = true })
  M.expect_zigbee_connectivity(rest_connection, contact_config.zigbee_rid, contact_config.device_id)
  M.expect_resource(rest_connection, "contact", contact_config.rid,
    { owner = owner, enabled = true, contact_report = { state = contact_config.contact_state } })
  M.expect_resource(rest_connection, "tamper", contact_config.tamper_rid,
    { owner = owner, tamper_reports = { { state = contact_config.tamper } } })
  M.expect_resource(rest_connection, "device_power", contact_config.power_rid, device_power(contact_config))
  if sse_connection then
    M.setup_sse_expectations(sse_connection, rest_connection)
  end
end

return M
