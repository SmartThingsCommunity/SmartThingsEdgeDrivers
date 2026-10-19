-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local connection_scenario = require "integration_test.connection_scenario"
local http = require "integration_test.connection_scenario_http"
local capabilities = require "st.capabilities"

local Fields = require "fields"
local HueApi = require "hue.api"

--- Shared fixture helpers for building a "known, already paired" Hue bridge + child device(s)
--- for integration tests.
---
--- The real `added`/`init` lifecycle handlers do substantial discovery/pairing work (scanning
--- for the bridge on the network, waiting for the Link Button, querying the bridge for each
--- light's initial state, ...) that runs for real against the mock LAN socket every time a
--- test device goes through lifecycle. These helpers pre-populate every cache/datastore field
--- that work depends on (`driver.datastore.bridge_netinfo`/`.api_keys`, `disco`'s
--- `device_state_disco_cache`, per-device fields) so that added/init resolve synchronously to
--- a steady, already-paired state instead of falling into their discovery/long-poll paths --
--- those paths are covered separately in test_hue_bridge_discovery.lua.
---
---
--- `HueDeviceBuilder` builds the bridge and child devices; `create_hue_scenario` builds the
--- ConnectionScenario (REST and optionally SSE connections to the bridge) and the
--- `setup_*_init_expectations` helpers register what each device type requests while it
--- initializes. SSE event builders (`button_event`, `motion_event`, ...) build the payloads to
--- queue with `connection_scenario_http.queue_sse_event`.
-- `samsungim.hueSyncMode` is defined by the platform, not the driver package; its definition
-- (fetched from the SmartThings API) lets the driver emit Hue sync mode events in tests.
test.add_capability_definition("fixtures/capabilities/samsungim.hueSyncMode.json")

local M = {}

M.BRIDGE_IP = "192.168.1.15"
M.BRIDGE_DNI = "AA:BB:CC:DD:EE:FF"
M.API_KEY = "test-api-key"


--- `LightLifecycleHandlers.init` unconditionally emits a levelRange event on every light's
--- first init, regardless of bridge/pairing state. HueDeviceBuilder's `test_init` already
--- calls this; only call it directly if building a fixture by hand.
---
--- Must be called from `test_init` (synchronous setup, before `require "init"` runs) rather
--- than from within a coroutine test body for proper event expectation timing.
---
--- @param mock_light table
function M.expect_light_init_events(mock_light)
  test.socket.capability:__expect_send(
    mock_light:generate_test_message("main", capabilities.switchLevel.levelRange({ minimum = 1, maximum = 100 }))
  )
end

--- Refresh (and other per-device flows) check that the bridge has finished initializing via
--- Fields._INIT, which is normally set inside do_bridge_network_init once bridge setup fully
--- completes -- the same step that creates the bridge's SSE EventSource. Since SSE connects to
--- the same host:port as REST calls, and the mock LAN socket models one connection per address,
--- letting do_bridge_network_init run for real would interleave the SSE connection's own bytes
--- into REST-focused assertions. Call this from within a test body (after the automatic
--- added/init lifecycle burst has already run -- i.e. as the first statement in the test, not
--- from test_init) to mark the bridge initialized directly instead.
---
--- @param mock_bridge table
function M.mark_bridge_initialized(mock_bridge)
  mock_bridge:set_field(Fields._INIT, true, {})
end


--- @class HueDeviceBuilder
--- Fluent API for building Hue test fixtures with sensible defaults.
--- Provides a clean, declarative way to set up bridge + child devices for tests.
local HueDeviceBuilder = {}
HueDeviceBuilder.__index = HueDeviceBuilder

--- Create a new HueDeviceBuilder instance.
---
--- @return HueDeviceBuilder
function M.HueDeviceBuilder_new()
  local instance = {
    bridge_ip = M.BRIDGE_IP,
    bridge_dni = M.BRIDGE_DNI,
    api_key = M.API_KEY,
    sse_enabled = false,  -- Use different name to avoid shadowing enable_sse() method
    children = {},  -- Array of child device configs
  }
  return setmetatable(instance, HueDeviceBuilder)
end

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
---   - label: string (default: "Hue Light")
--- @param profile string|nil profile filename (default: "white-and-color-ambiance.yml")
--- @return HueDeviceBuilder self for chaining
function HueDeviceBuilder:with_light(rid, state, profile)
  state = state or {}
  local device_id = state.hue_device_id or (rid .. "-device")

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

  table.insert(self.children, {
    type = "light",
    rid = rid,
    profile = profile or "white-and-color-ambiance.yml",
    state = disco_state,
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
    battery = config.battery or 85,  -- Store for later use in init_expectations
    -- init_expectations will be created in start() based on sse_enabled
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
    -- init_expectations will be created in start() based on sse_enabled
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
    -- init_expectations will be created in start() based on sse_enabled
  })
  return self
end

--- Add a Hue room containing some of this fixture's lights.
---
--- The driver only scans the bridge's rooms after its event stream connects, so for a fixture
--- without SSE they are applied after init by calling `fixtures.seed_groups()` from within a
--- test, which feeds Hue room resources through the driver's own `grouped_utils.group_add`.
---
--- @param rid string Hue resource ID for the room
--- @param grouped_light_rid string resource ID of the room's grouped_light service
--- @param light_rids string[] resource IDs of lights (added with `with_light`) in the room
--- @param name string|nil room name (default "Test Room")
--- @return HueDeviceBuilder self for chaining
function HueDeviceBuilder:with_room(rid, grouped_light_rid, light_rids, name)
  self.rooms = self.rooms or {}
  table.insert(self.rooms, {
    rid = rid,
    grouped_light_rid = grouped_light_rid,
    light_rids = light_rids,
    name = name or "Test Room",
  })
  return self
end

--- Enable SSE support for this fixture.
---
--- @return HueDeviceBuilder self for chaining
function HueDeviceBuilder:enable_sse()
  self.sse_enabled = true
  return self
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

--- Build the fixture and return a structured fixtures object.
--- This creates all mock devices and returns them with their configurations.
---
--- @return table fixtures with fields:
---   - bridge: mock bridge device
---   - devices: array of mock child devices
---   - test_init: function to pass to test.set_test_init_function
---   - configs: table of device configs by type (button, light, motion, contact)
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
    if self.sse_enabled then
      driver.datastore.bridge_netinfo[self.bridge_dni] = {
        ip = self.bridge_ip,
        swversion = tostring(HueApi.MIN_CLIP_V2_SWVERSION),
        modelid = "BSB002"
      }
      driver.joined_bridges[self.bridge_dni] = true
    else
      driver.datastore.bridge_netinfo[self.bridge_dni] = {
        ip = self.bridge_ip,
        swversion = "0",
        modelid = "BSB002"
      }
    end
    driver.datastore.api_keys = driver.datastore.api_keys or {}
    driver.datastore.api_keys[self.bridge_dni] = self.api_key

    local disco = require "disco"
    disco.disco_api_instances = {}
    disco.discovery_active = self.sse_enabled or false

    -- Populate disco cache with child device states
    for i, child_config in ipairs(self.children) do
      child_config.state.parent_device_id = mock_bridge.id
      disco.device_state_disco_cache[child_config.rid] = child_config.state
    end
  end)

  local function test_init()
    test.set_test_coroutine_priority(true)

    test.mock_device.add_test_device(mock_bridge)
    for _, mock_child in ipairs(mock_children) do
      test.mock_device.add_test_device(mock_child)
    end

    mock_bridge:set_field(Fields.DEVICE_TYPE, "bridge", {})
    mock_bridge:set_field(Fields.BRIDGE_ID, self.bridge_dni, {})
    mock_bridge:set_field(Fields.IPV4, self.bridge_ip, {})
    mock_bridge:set_field(HueApi.APPLICATION_KEY_HEADER, self.api_key, {})

    -- Check if we have any non-light children (buttons, sensors, etc.)
    -- These need the bridge marked as _ADDED to avoid being treated as stray devices
    local has_non_light_children = false
    for _, child_config in ipairs(self.children) do
      if child_config.type ~= "light" then
        has_non_light_children = true
        break
      end
    end

    if has_non_light_children then
      mock_bridge:set_field(Fields._ADDED, true, { persist = true })
      -- Don't mark _INIT yet if SSE is enabled - let do_bridge_network_init run to set up SSE
      if not self.sse_enabled then
        mock_bridge:set_field(Fields._INIT, true, { persist = true })
      end
    end

    -- Register init expectations for all children
    -- Generate init_expectations based on device type and SSE status
    for i, child_config in ipairs(self.children) do
      local mock_child = mock_children[i]

      if child_config.type == "button" then
        -- Button devices emit supportedButtonValues for each component
        local components = {"main"}
        for j = 2, child_config.num_buttons do
          table.insert(components, "button" .. j)
        end

        for _, component in ipairs(components) do
          test.socket.capability:__expect_send(
            mock_child:generate_test_message(component,
              capabilities.button.supportedButtonValues(
                { "pushed", "held" },
                { visibility = { displayed = false } }
              )
            )
          )
        end

        -- Battery event from refresh during init (only if SSE is enabled)
        if self.sse_enabled then
          test.socket.capability:__expect_send(
            mock_child:generate_test_message("main",
              capabilities.battery.battery(child_config.battery)
            )
          )
        end

      elseif child_config.type == "motion" then
        -- Motion sensors emit battery event from refresh during init (only if SSE enabled)
        if self.sse_enabled then
          test.socket.capability:__set_channel_ordering("relaxed")

          -- Motion state
          local motion_value = child_config.motion and "active" or "inactive"
          test.socket.capability:__expect_send(
            mock_child:generate_test_message("main",
              capabilities.motionSensor.motion[motion_value]()
            )
          )

          -- Temperature
          test.socket.capability:__expect_send(
            mock_child:generate_test_message("main",
              capabilities.temperatureMeasurement.temperature({
                value = child_config.temperature,
                unit = "C"
              })
            )
          )

          -- Illuminance (convert light_level to lux: lux = round(10^((light_level - 1) / 10000)))
          -- Note: round() is math.floor(val + 0.5) to match st.utils.round
          local lux = math.floor(10 ^ ((child_config.light_level - 1) / 10000) + 0.5)
          test.socket.capability:__expect_send(
            mock_child:generate_test_message("main",
              capabilities.illuminanceMeasurement.illuminance(lux)
            )
          )

          -- Battery
          test.socket.capability:__expect_send(
            mock_child:generate_test_message("main",
              capabilities.battery.battery(child_config.battery)
            )
          )
        end

      elseif child_config.type == "contact" then
        -- Contact sensors emit multiple events from refresh during init (only if SSE enabled)
        if self.sse_enabled then
          test.socket.capability:__set_channel_ordering("relaxed")

          -- Contact state
          local contact_value = (child_config.contact_state == "no_contact") and "open" or "closed"
          test.socket.capability:__expect_send(
            mock_child:generate_test_message("main",
              capabilities.contactSensor.contact[contact_value]()
            )
          )

          -- Tamper state
          local tamper_value = (child_config.tamper == "tampered") and "detected" or "clear"
          test.socket.capability:__expect_send(
            mock_child:generate_test_message("main",
              capabilities.tamperAlert.tamper[tamper_value]()
            )
          )

          -- Battery
          test.socket.capability:__expect_send(
            mock_child:generate_test_message("main",
              capabilities.battery.battery(child_config.battery)
            )
          )
        end

      elseif child_config.type == "light" then
        -- Light init emits levelRange; for a profile without switchLevel (e.g. a smart plug) the
        -- device drops the event, so nothing is sent.
        if profile_has_capability(child_config.profile, capabilities.switchLevel.ID) then
          test.socket.capability:__expect_send(
            mock_child:generate_test_message("main",
              capabilities.switchLevel.levelRange({ minimum = 1, maximum = 100 })
            )
          )
        end
      end
    end
  end

  -- Build configuration objects for each device type
  local configs = {}
  for i, child_config in ipairs(self.children) do
    local device_key = child_config.type
    if not configs[device_key] then
      configs[device_key] = {}
    end

    -- Build config based on device type
    if child_config.type == "button" then
      table.insert(configs[device_key], {
        rid = child_config.rid,
        device_id = child_config.state.hue_device_id,
        label = child_config.state.hue_provided_name,
        num_buttons = child_config.num_buttons,
        battery = child_config.battery,
        power_rid = child_config.state.power_id,
        zigbee_rid = child_config.state.zigbee_connectivity_id or (child_config.rid .. "-zigbee"),
        button_rids = {}  -- Will be populated if needed
      })
      -- Add button RIDs for multi-button devices
      for j = 1, child_config.num_buttons do
        table.insert(configs[device_key][#configs[device_key]].button_rids, child_config.state["button" .. j .. "_id"])
      end

    elseif child_config.type == "light" then
      table.insert(configs[device_key], {
        rid = child_config.rid,
        device_id = child_config.state.hue_device_id,
        label = child_config.state.hue_provided_name,
        zigbee_rid = child_config.state.zigbee_connectivity_id or (child_config.rid .. "-zigbee"),
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
        zigbee_rid = child_config.state.zigbee_connectivity_id or (child_config.rid .. "-zigbee"),
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
        zigbee_rid = child_config.state.zigbee_connectivity_id or (child_config.rid .. "-zigbee"),
        tamper_rid = child_config.state.tamper_id
      })
    end
  end

  local hue_device_id_by_rid = {}
  for _, child_config in ipairs(self.children) do
    hue_device_id_by_rid[child_config.rid] = child_config.state.hue_device_id
  end

  -- The rooms declared with `with_room`, as the bridge's room resources.
  local room_resources = {}
  for _, room in ipairs(self.rooms or {}) do
    local children = {}
    for _, light_rid in ipairs(room.light_rids) do
      table.insert(children, { rid = hue_device_id_by_rid[light_rid], rtype = "device" })
    end
    table.insert(room_resources, {
      id = room.rid,
      type = "room",
      metadata = { name = room.name },
      children = children,
      services = { { rid = room.grouped_light_rid, rtype = "grouped_light" } },
    })
  end

  --- Apply the rooms declared with `with_room` to the bridge. Must be called from within a test
  --- once the light children have been added (e.g. after `test.wait_for_events()`).
  local function seed_groups()
    local grouped_utils = require "utils.grouped_utils"
    local bridge_device = driver_under_test:get_device_info(mock_bridge.id)
    -- group_add expects the bridge's group list to already exist (normally set by a group scan).
    bridge_device:set_field(Fields.GROUPS, {})
    for _, room in ipairs(room_resources) do
      grouped_utils.group_add(driver_under_test, bridge_device, room)
    end
    return bridge_device:get_field(Fields.GROUPS)
  end

  --- The driver's own device object for a mock device, e.g. to inspect or seed device fields.
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
    seed_groups = seed_groups,
    driver_device = driver_device,
  }
end

-- Export HueDeviceBuilder via a constructor function
M.HueDeviceBuilder = {
  new = M.HueDeviceBuilder_new
}

--- ConnectionScenario 2.0 Test Helpers
--- These helpers reduce boilerplate when using the new connection_scenario framework

--- Create a ConnectionScenario configured for Hue bridge testing.
---
--- @param options table|nil Configuration options:
---   - host: Bridge IP (default: hue_test_helpers.BRIDGE_IP)
---   - port: Bridge port (default: 443)
---   - rooms: Hue room resources the bridge reports to the driver's group scans (default: none),
---     e.g. `fixtures.rooms` from a HueDeviceBuilder with `with_room`
---   - sse: Include the SSE event stream connection (default: false)
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
    body = { errors = {}, data = {} },
    reusable = true,
  })
  if options.sse then
    connections.sse = scenario:connection("sse", {
      matcher = http.matcher("GET", "^/eventstream/clip/v2")
    })
  end

  return scenario, connections
end

--- Setup test_init function with scenario activation.
---
--- @param base_test_init function The base test_init function returned by HueDeviceBuilder
--- @param scenario table The ConnectionScenario instance
--- @param additional_setup function|nil Optional additional setup to run before scenario:activate()
function M.setup_scenario_test_init(base_test_init, scenario, additional_setup)
  local function test_init()
    base_test_init()
    if additional_setup then
      additional_setup()
    end
    scenario:activate()
  end
  test.set_test_init_function(test_init)
end

--- Expect a Hue device info request (GET /clip/v2/resource/device/{id}).
---
--- @param connection table The connection handle
--- @param device_id string The device ID
--- @param services table Array of service objects
--- @param options table|nil Options:
---   - name: Device name (default: "Device")
---   - metadata: Full metadata table (overrides name)
---   - product_data: Product data table
---   - status: HTTP status (default: 200)
---   - reusable: Make expectation reusable (default: true)
function M.expect_device_info(connection, device_id, services, options)
  options = options or {}
  return http.expect_request(connection, "GET", "/clip/v2/resource/device/" .. device_id, {
    status = options.status or 200,
    body = {
      errors = {},
      data = {{
        type = "device",
        id = device_id,
        metadata = options.metadata or { name = options.name or "Device" },
        product_data = options.product_data,
        services = services
      }}
    },
    reusable = options.reusable ~= false
  })
end

--- Expect a Hue zigbee connectivity request (GET /clip/v2/resource/zigbee_connectivity/{id}).
---
--- @param connection table The connection handle
--- @param zigbee_rid string The zigbee connectivity resource ID
--- @param options table|nil Options:
---   - status: HTTP status (default: 200)
---   - connectivity_status: Connection status (default: "connected")
---   - owner: Owner resource ID
---   - reusable: Make expectation reusable (default: false)
function M.expect_zigbee_connectivity(connection, zigbee_rid, options)
  options = options or {}
  local data_entry = {
    type = "zigbee_connectivity",
    id = zigbee_rid,
    status = options.connectivity_status or "connected"
  }

  if options.owner then
    data_entry.owner = { rid = options.owner }
  end

  return http.expect_request(connection, "GET", "/clip/v2/resource/zigbee_connectivity/" .. zigbee_rid, {
    status = options.status or 200,
    body = {
      errors = {},
      data = { data_entry }
    },
    reusable = options.reusable
  })
end

--- Expect a Hue device power request (GET /clip/v2/resource/device_power/{id}).
---
--- @param connection table The connection handle
--- @param power_rid string The device power resource ID
--- @param battery_level number Battery level (0-100)
--- @param options table|nil Options:
---   - status: HTTP status (default: 200)
---   - reusable: Make expectation reusable (default: false)
function M.expect_device_power(connection, power_rid, battery_level, options)
  options = options or {}
  return http.expect_request(connection, "GET", "/clip/v2/resource/device_power/" .. power_rid, {
    status = options.status or 200,
    body = {
      errors = {},
      data = {{
        type = "device_power",
        id = power_rid,
        power_state = { battery_level = battery_level }
      }}
    },
    reusable = options.reusable
  })
end

--- Expect a Hue button resource request (GET /clip/v2/resource/button/{id}).
---
--- @param connection table The connection handle
--- @param button_rid string The button resource ID
--- @param options table|nil Options:
---   - control_id: Button control ID (default: 1)
---   - event_values: Array of supported event values (default: {"short_release", "long_press", "long_release"})
---   - status: HTTP status (default: 200)
---   - reusable: Make expectation reusable (default: false)
function M.expect_button_resource(connection, button_rid, options)
  options = options or {}
  return http.expect_request(connection, "GET", "/clip/v2/resource/button/" .. button_rid, {
    status = options.status or 200,
    body = {
      errors = {},
      data = {{
        type = "button",
        id = button_rid,
        metadata = { control_id = options.control_id or 1 },
        button = {
          button_report = { event = "initial_press", updated = "2024-01-01T00:00:00Z" },
          event_values = options.event_values or { "short_release", "long_press", "long_release" }
        }
      }}
    },
    reusable = options.reusable
  })
end

--- Expect a Hue motion sensor resource request (GET /clip/v2/resource/motion/{id}).
---
--- @param connection table The connection handle
--- @param motion_rid string The motion sensor resource ID
--- @param is_active boolean Motion detected state
--- @param options table|nil Options:
---   - status: HTTP status (default: 200)
---   - reusable: Make expectation reusable (default: false)
function M.expect_motion_resource(connection, motion_rid, is_active, options)
  options = options or {}
  return http.expect_request(connection, "GET", "/clip/v2/resource/motion/" .. motion_rid, {
    status = options.status or 200,
    body = {
      errors = {},
      data = {{
        type = "motion",
        id = motion_rid,
        motion = { motion = is_active, motion_valid = true },
        enabled = true
      }}
    },
    reusable = options.reusable
  })
end

--- Expect a Hue temperature sensor resource request (GET /clip/v2/resource/temperature/{id}).
---
--- @param connection table The connection handle
--- @param temperature_rid string The temperature sensor resource ID
--- @param temperature number Temperature in Celsius
--- @param options table|nil Options:
---   - status: HTTP status (default: 200)
---   - reusable: Make expectation reusable (default: false)
function M.expect_temperature_resource(connection, temperature_rid, temperature, options)
  options = options or {}
  return http.expect_request(connection, "GET", "/clip/v2/resource/temperature/" .. temperature_rid, {
    status = options.status or 200,
    body = {
      errors = {},
      data = {{
        type = "temperature",
        id = temperature_rid,
        temperature = { temperature = temperature, temperature_valid = true },
        enabled = true
      }}
    },
    reusable = options.reusable
  })
end

--- Expect a Hue light level sensor resource request (GET /clip/v2/resource/light_level/{id}).
---
--- @param connection table The connection handle
--- @param light_level_rid string The light level sensor resource ID
--- @param light_level number Light level value
--- @param options table|nil Options:
---   - status: HTTP status (default: 200)
---   - reusable: Make expectation reusable (default: false)
function M.expect_light_level_resource(connection, light_level_rid, light_level, options)
  options = options or {}
  return http.expect_request(connection, "GET", "/clip/v2/resource/light_level/" .. light_level_rid, {
    status = options.status or 200,
    body = {
      errors = {},
      data = {{
        type = "light_level",
        id = light_level_rid,
        light = { light_level = light_level, light_level_valid = true },
        enabled = true
      }}
    },
    reusable = options.reusable
  })
end

--- Expect a Hue contact sensor resource request (GET /clip/v2/resource/contact/{id}).
---
--- @param connection table The connection handle
--- @param contact_rid string The contact sensor resource ID
--- @param state string Contact state: "contact" (closed) or "no_contact" (open)
--- @param options table|nil Options:
---   - status: HTTP status (default: 200)
---   - reusable: Make expectation reusable (default: false)
function M.expect_contact_resource(connection, contact_rid, state, options)
  options = options or {}
  return http.expect_request(connection, "GET", "/clip/v2/resource/contact/" .. contact_rid, {
    status = options.status or 200,
    body = {
      errors = {},
      data = {{
        type = "contact",
        id = contact_rid,
        contact_report = { state = state },
        enabled = true
      }}
    },
    reusable = options.reusable
  })
end

--- Expect a Hue tamper sensor resource request (GET /clip/v2/resource/tamper/{id}).
---
--- @param connection table The connection handle
--- @param tamper_rid string The tamper sensor resource ID
--- @param state string Tamper state: "tampered" or "not_tampered"
--- @param options table|nil Options:
---   - status: HTTP status (default: 200)
---   - reusable: Make expectation reusable (default: false)
function M.expect_tamper_resource(connection, tamper_rid, state, options)
  options = options or {}
  return http.expect_request(connection, "GET", "/clip/v2/resource/tamper/" .. tamper_rid, {
    status = options.status or 200,
    body = {
      errors = {},
      data = {{
        type = "tamper",
        id = tamper_rid,
        tamper_reports = {{ state = state }}
      }}
    },
    reusable = options.reusable
  })
end

--- Expect a Hue light resource request (GET /clip/v2/resource/light/{id}).
---
--- @param connection table The connection handle
--- @param light_rid string The light resource ID
--- @param on_state boolean Light on/off state
--- @param brightness number|nil Brightness level (0-100)
--- @param options table|nil Options:
---   - status: HTTP status (default: 200)
---   - color: Color object with xy coordinates
---   - color_temperature: Color temperature object with mirek
---   - reusable: Make expectation reusable (default: false)
function M.expect_light_resource(connection, light_rid, on_state, brightness, options)
  options = options or {}
  local light_data = {
    type = "light",
    id = light_rid,
    on = { on = on_state }
  }

  if brightness then
    light_data.dimming = { brightness = brightness }
  end

  if options.color then
    light_data.color = options.color
  end

  if options.color_temperature then
    light_data.color_temperature = options.color_temperature
  end

  return http.expect_request(connection, "GET", "/clip/v2/resource/light/" .. light_rid, {
    status = options.status or 200,
    body = {
      errors = {},
      data = { light_data }
    },
    reusable = options.reusable
  })
end

--- Assert that the bridge's event stream connected: the bridge is marked online once it does, the
--- handshake went out on the SSE connection, and every request expected while the devices
--- initialize (the scenario's single-use expectations) was made.
---
--- @param scenario table The ConnectionScenario instance
--- @param mock_bridge table
function M.assert_event_stream_connected(scenario, mock_bridge)
  test.wait_until(function() return test.mock_devices_api.__is_device_online(mock_bridge.id) == true end,
    { message = "the bridge being marked online when its event stream connects" })
  scenario:get_connection("sse"):assert_sent("^GET /eventstream/clip/v2 HTTP/1.1\r\n")
  scenario:assert_all_satisfied()
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
--- These high-level helpers configure all standard init-time expectations for a device type.

--- Setup standard init-time expectations for a button device.
---
--- This configures expectations for:
--- - Device info query
--- - Zigbee connectivity query
--- - Button resource queries (one per button)
--- - Device power/battery query
--- - SSE handshake (if sse_connection provided)
---
--- @param rest_connection table The REST connection handle
--- @param sse_connection table|nil The SSE connection handle (optional, for SSE-enabled tests)
--- @param button_config table Button configuration with fields:
---   - device_id: Hue device ID
---   - label: Device label/name
---   - zigbee_rid: Zigbee connectivity resource ID
---   - button_rids: Array of button resource IDs
---   - power_rid: Device power resource ID
---   - battery: Battery level (0-100)
--- @param options table|nil Options:
---   - services: Override default services array
---   - reusable: Make device info reusable (default: true)
function M.setup_button_init_expectations(rest_connection, sse_connection, button_config, options)
  options = options or {}
  -- Default services if not provided
  local services = options.services or {
    { rtype = "zigbee_connectivity", rid = button_config.zigbee_rid },
    { rtype = "button", rid = button_config.button_rids[1] },
    { rtype = "device_power", rid = button_config.power_rid }
  }

  -- 1. Device info
  M.expect_device_info(rest_connection, button_config.device_id, services, {
    name = button_config.label,
    product_data = { product_name = button_config.label },
    reusable = options.reusable ~= false
  })

  -- 2. Zigbee connectivity
  M.expect_zigbee_connectivity(rest_connection, button_config.zigbee_rid)

  -- 3. Button resources (one per button)
  for _, button_rid in ipairs(button_config.button_rids) do
    M.expect_button_resource(rest_connection, button_rid)
  end

  -- 4. Device power
  M.expect_device_power(rest_connection, button_config.power_rid, button_config.battery)

  -- 5. SSE handshake (if SSE enabled)
  if sse_connection then
    M.setup_sse_expectations(sse_connection, rest_connection)
  end

end

--- Setup standard init-time expectations for a motion sensor device.
---
--- This configures expectations for:
--- - Device info query
--- - Zigbee connectivity query
--- - Motion sensor resource query
--- - Temperature sensor resource query
--- - Light level sensor resource query
--- - Device power/battery query
--- - SSE handshake (if sse_connection provided)
---
--- @param rest_connection table The REST connection handle
--- @param sse_connection table|nil The SSE connection handle (optional, for SSE-enabled tests)
--- @param motion_config table Motion sensor configuration with fields:
---   - device_id: Hue device ID
---   - rid: Motion sensor resource ID
---   - label: Device label/name
---   - zigbee_rid: Zigbee connectivity resource ID
---   - motion: Motion detected state (boolean)
---   - temperature: Temperature in Celsius
---   - temperature_rid: Temperature sensor resource ID
---   - light_level: Light level value
---   - light_level_rid: Light level sensor resource ID
---   - power_rid: Device power resource ID
---   - battery: Battery level (0-100)
--- @param options table|nil Options:
---   - services: Override default services array
---   - reusable: Make device info reusable (default: true)
function M.setup_motion_init_expectations(rest_connection, sse_connection, motion_config, options)
  options = options or {}
  -- Default services if not provided
  local services = options.services or {
    { rtype = "zigbee_connectivity", rid = motion_config.zigbee_rid },
    { rtype = "motion", rid = motion_config.rid },
    { rtype = "temperature", rid = motion_config.temperature_rid },
    { rtype = "light_level", rid = motion_config.light_level_rid },
    { rtype = "device_power", rid = motion_config.power_rid }
  }

  -- 1. Device info
  M.expect_device_info(rest_connection, motion_config.device_id, services, {
    name = motion_config.label,
    reusable = options.reusable ~= false
  })

  -- 2. Zigbee connectivity
  M.expect_zigbee_connectivity(rest_connection, motion_config.zigbee_rid)

  -- 3. Motion sensor resource
  M.expect_motion_resource(rest_connection, motion_config.rid, motion_config.motion)

  -- 4. Temperature sensor resource
  M.expect_temperature_resource(rest_connection, motion_config.temperature_rid, motion_config.temperature)

  -- 5. Light level sensor resource
  M.expect_light_level_resource(rest_connection, motion_config.light_level_rid, motion_config.light_level)

  -- 6. Device power
  M.expect_device_power(rest_connection, motion_config.power_rid, motion_config.battery)

  -- 7. SSE handshake (if SSE enabled)
  if sse_connection then
    M.setup_sse_expectations(sse_connection, rest_connection)
  end

end

--- Setup standard init-time expectations for a contact sensor device.
---
--- This configures expectations for:
--- - Device info query
--- - Zigbee connectivity query
--- - Contact sensor resource query
--- - Tamper sensor resource query
--- - Device power/battery query
--- - SSE handshake (if sse_connection provided)
---
--- @param rest_connection table The REST connection handle
--- @param sse_connection table|nil The SSE connection handle (optional, for SSE-enabled tests)
--- @param contact_config table Contact sensor configuration with fields:
---   - device_id: Hue device ID
---   - rid: Contact sensor resource ID
---   - label: Device label/name
---   - zigbee_rid: Zigbee connectivity resource ID
---   - contact_state: Contact state ("contact" = closed, "no_contact" = open)
---   - tamper: Tamper state ("tampered" or "not_tampered")
---   - tamper_rid: Tamper sensor resource ID
---   - power_rid: Device power resource ID
---   - battery: Battery level (0-100)
--- @param options table|nil Options:
---   - services: Override default services array
---   - reusable: Make device info reusable (default: true)
function M.setup_contact_init_expectations(rest_connection, sse_connection, contact_config, options)
  options = options or {}
  -- Default services if not provided
  local services = options.services or {
    { rtype = "zigbee_connectivity", rid = contact_config.zigbee_rid },
    { rtype = "contact", rid = contact_config.rid },
    { rtype = "tamper", rid = contact_config.tamper_rid },
    { rtype = "device_power", rid = contact_config.power_rid }
  }

  -- 1. Device info
  M.expect_device_info(rest_connection, contact_config.device_id, services, {
    name = contact_config.label,
    reusable = options.reusable ~= false
  })

  -- 2. Zigbee connectivity
  M.expect_zigbee_connectivity(rest_connection, contact_config.zigbee_rid)

  -- 3. Contact sensor resource
  M.expect_contact_resource(rest_connection, contact_config.rid, contact_config.contact_state)

  -- 4. Tamper sensor resource
  M.expect_tamper_resource(rest_connection, contact_config.tamper_rid, contact_config.tamper)

  -- 5. Device power
  M.expect_device_power(rest_connection, contact_config.power_rid, contact_config.battery)

  -- 6. SSE handshake (if SSE enabled)
  if sse_connection then
    M.setup_sse_expectations(sse_connection, rest_connection)
  end

end

return M
