-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local log = require "log"
local clusters = require "st.matter.clusters"
local device_lib = require "st.device"

-- COMPONENT_TO_ENDPOINT_MAP is here only to preserve the endpoint mapping for
-- devices that were joined to this driver as MCD devices before the transition
-- to join all matter-switch devices as parent-child. This value will only exist
-- in the device table for devices that joined prior to this transition, and it
-- will not be set for new devices.
local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local IS_PARENT_CHILD_DEVICE = "__is_parent_child_device"
local SECOND_SWITCH_ID = "__second_switch_id"
local SECOND_SWITCH_ENDPOINT = "__second_switch_endpoint"
local SECOND_BUTTON_ENDPOINT = "__second_button_endpoint"

local ON_OFF_LIGHT_DEVICE_TYPE_ID = 0x0100
local GENERIC_SWITCH_ID = 0x000F
local ELECTRICAL_SENSOR_ID = 0x0510
local device_type_profile_map = {
  [ON_OFF_LIGHT_DEVICE_TYPE_ID] = "light-button",
  [GENERIC_SWITCH_ID] = "button"
}

local device_type_id_map = {
  ON_OFF_LIGHT_DEVICE_TYPE_ID,
  GENERIC_SWITCH_ID,
  ELECTRICAL_SENSOR_ID
}

local device_type_attribute_map = {
  [ON_OFF_LIGHT_DEVICE_TYPE_ID] = {
    clusters.OnOff.attributes.OnOff
  },
  [GENERIC_SWITCH_ID] = {
    clusters.Switch.events.InitialPress
  },
  [ELECTRICAL_SENSOR_ID] = {
    clusters.ElectricalPowerMeasurement.attributes.ActivePower,
    clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported
  }
}

local CUMULATIVE_REPORTS_NOT_SUPPORTED = "__cumulative_reports_not_supported"
local FIRST_EXPORT_REPORT_TIMESTAMP = "__first_export_report_timestamp"
local EXPORT_POLL_TIMER_SETTING_ATTEMPTED = "__export_poll_timer_setting_attempted"
local EXPORT_REPORT_TIMEOUT = "__export_report_timeout"
local TOTAL_EXPORTED_ENERGY = "__total_exported_energy"
local LAST_EXPORTED_REPORT_TIMESTAMP = "__last_exported_report_timestamp"
local RECURRING_EXPORT_REPORT_POLL_TIMER = "__recurring_export_report_poll_timer"
local MINIMUM_ST_ENERGY_REPORT_INTERVAL = (15 * 60) -- 15 minutes, reported in seconds
local SUBSCRIPTION_REPORT_OCCURRED = "__subscription_report_occurred"
local CONVERSION_CONST_MILLIWATT_TO_WATT = 1000 -- A milliwatt is 1/1000th of a watt

local embedded_cluster_utils = require "embedded-cluster-utils"

-- Include driver-side definitions when lua libs api version is < 11
local version = require "version"
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"
end

-- Return an ISO-8061 timestamp in UTC
local function iso8061Timestamp(time)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", time)
end

local function delete_export_poll_schedule(device)
  local export_poll_timer = device:get_field(RECURRING_EXPORT_REPORT_POLL_TIMER)
  if export_poll_timer then
    device.thread:cancel_timer(export_poll_timer)
    device:set_field(RECURRING_EXPORT_REPORT_POLL_TIMER, nil)
    device:set_field(EXPORT_POLL_TIMER_SETTING_ATTEMPTED, nil)
  end
end

local function send_export_poll_report(device, latest_total_exported_energy_wh)
  local current_time = os.time()
  local last_time = device:get_field(LAST_EXPORTED_REPORT_TIMESTAMP) or 0
  device:set_field(LAST_EXPORTED_REPORT_TIMESTAMP, current_time, { persist = true })

  -- Calculate the energy delta between reports
  local energy_delta_wh = 0.0
  local previous_exported_report = device:get_latest_state("main", capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME)
  if previous_exported_report and previous_exported_report.energy then
    energy_delta_wh = math.max(latest_total_exported_energy_wh - previous_exported_report.energy, 0.0)
  end

  -- Report the energy consumed during the time interval. The unit of these values should be 'Wh'
  device:emit_event(capabilities.powerConsumptionReport.powerConsumption({
    start = iso8061Timestamp(last_time),
    ["end"] = iso8061Timestamp(current_time - 1),
    deltaEnergy = energy_delta_wh,
    energy = latest_total_exported_energy_wh
  }))
end

local function create_poll_report_schedule(device)
  local export_timer = device.thread:call_on_schedule(
    device:get_field(EXPORT_REPORT_TIMEOUT),
    send_export_poll_report(device, device:get_field(TOTAL_EXPORTED_ENERGY)),
    "polling_export_report_schedule_timer"
  )
  device:set_field(RECURRING_EXPORT_REPORT_POLL_TIMER, export_timer)
end

local function set_poll_report_timer_and_schedule(device, is_cumulative_report)
  local cumul_eps = embedded_cluster_utils.get_endpoints(device,
    clusters.ElectricalEnergyMeasurement.ID,
    {feature_bitmap = clusters.ElectricalEnergyMeasurement.types.Feature.CUMULATIVE_ENERGY
                     | clusters.ElectricalEnergyMeasurement.types.Feature.IMPORTED_ENERGY})
  if #cumul_eps == 0 then
    device:set_field(CUMULATIVE_REPORTS_NOT_SUPPORTED, true)
  end
  if #cumul_eps > 0 and not is_cumulative_report then
    return
  elseif not device:get_field(SUBSCRIPTION_REPORT_OCCURRED) then
    device:set_field(SUBSCRIPTION_REPORT_OCCURRED, true)
  elseif not device:get_field(FIRST_EXPORT_REPORT_TIMESTAMP) then
    device:set_field(FIRST_EXPORT_REPORT_TIMESTAMP, os.time())
  else
    local first_timestamp = device:get_field(FIRST_EXPORT_REPORT_TIMESTAMP)
    local second_timestamp = os.time()
    local report_interval_secs = second_timestamp - first_timestamp
    device:set_field(EXPORT_REPORT_TIMEOUT, math.max(report_interval_secs, MINIMUM_ST_ENERGY_REPORT_INTERVAL))
    -- the poll schedule is only needed for devices that support powerConsumption
    if device:supports_capability(capabilities.powerConsumptionReport) then
      create_poll_report_schedule(device)
    end
    device:set_field(EXPORT_POLL_TIMER_SETTING_ATTEMPTED, true)
  end
end

-- used in unit testing, since device.profile.id and args.old_st_store.profile.id are always the same
-- and this is to avoid the crash of the test case that occurs when try_update_metadata is performed in the device_init stage.
local TEST_CONFIGURE = "__test_configure"
local DEFERRED_CONFIGURE = "__DEFERRED_CONFIGURE"

-- These are essentially storing the supported features of a given endpoint
-- TODO: add an is_feature_supported_for_endpoint function to matter.device that takes an endpoint
local INITIAL_PRESS_ONLY = "__initial_press_only" -- for devices that support MS (MomentarySwitch), but not MSR (MomentarySwitchRelease)

local function is_aqara_light_switch_h2(opts, driver, device)
  local name = string.format("%s", device.manufacturer_info.product_name)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and
    string.find(name, "Aqara Light Switch H2") then
      return true
  end
  return false
end

local function get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

local function set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
end

local function get_first_non_zero_endpoint(endpoints)
  for _,ep in ipairs(endpoints) do
    if ep ~= 0 then -- 0 is the matter RootNode endpoint
      return ep
    end
  end
  return nil
end

--- find_default_endpoint helper function to handle situations where
--- device does not have endpoint ids in sequential order from 1
--- In this case the function returns the lowest endpoint value that isn't 0
--- and supports the OnOff or Switch cluster. This is done to bypass the
--- BRIDGED_NODE_DEVICE_TYPE on bridged devices.
local function find_default_endpoint(device)
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  table.sort(switch_eps)

  -- Return the first switch endpoint as the default endpoint if no button endpoints are available
  if #switch_eps > 0 then
    return get_first_non_zero_endpoint(switch_eps)
  end

  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return device.MATTER_DEFAULT_ENDPOINT
end

local function assign_child_profile(device, child_ep)
  local profile

  for _, ep in ipairs(device.endpoints) do
    if ep.endpoint_id == child_ep then
      -- Some devices report multiple device types which are a subset of
      -- a superset device type (For example, Dimmable Light is a superset of
      -- On/Off light). This mostly applies to the four light types, so we will want
      -- to match the profile for the superset device type. This can be done by
      -- matching to the device type with the highest ID
      local id = 0
      for _, dt in ipairs(ep.device_types) do
        id = math.max(id, dt.device_type_id)
      end
      profile = device_type_profile_map[id]
      break
    end
  end
  -- default to "switch-binary" if no profile is found
  return profile or "switch-binary"
end

local function do_configure(driver, device)
end

local function configure_buttons(device)
  if device.network_type ~= device_lib.NETWORK_TYPE_CHILD then
    local MS = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
    device.log.debug(#MS.." momentary switch endpoints")
    for _, ep in ipairs(MS) do
      -- device only supports momentary switch, no release events
      device.log.debug("configuring for press event only")
      set_field_for_endpoint(device, INITIAL_PRESS_ONLY, ep, true, {persist = true})
      if device:get_field(TEST_CONFIGURE) then
        if _ == 1 then
          device:emit_event_for_endpoint(ep, capabilities.button.supportedButtonValues({"pushed"}, {state_change = false}, {visibility = {displayed = false}}))
        end
      else
        local sbe = device:get_field(SECOND_BUTTON_ENDPOINT)
        if ep == sbe then
          local sse = device:get_field(SECOND_SWITCH_ENDPOINT)
          local ssi = device:get_field(SECOND_SWITCH_ID)
          local child_list = device:get_child_list()
          for _, child in pairs(child_list) do
            if child.id == ssi then
              device:emit_event_for_endpoint(sse, capabilities.button.supportedButtonValues({"pushed"}, {state_change = false}, {visibility = {displayed = false}}))
              break
            end
          end
        else
          device:emit_event_for_endpoint(ep, capabilities.button.supportedButtonValues({"pushed"}, {state_change = false}, {visibility = {displayed = false}}))
        end
      end
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%d", ep_id))
end

-- Since EDGE_CHILD supports only one component, the button cannot be processed as a component in card2 with two endpoints(switch and button).
-- In other words, the profile must be specified as the button capability of the main component.
-- Therefore, the following routine is required to change the event generated at the second button endpoint so that it can be
-- processed at the main component of the second switch.
local function save_second_switch_id(device)
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  table.sort(switch_eps)
  table.sort(button_eps)

  local component_map = {}
  local current_component_number = 3
  for _, ep in ipairs(switch_eps) do
    if _ == 1 then
      component_map["main"] = ep
    elseif _ == 2 then
      -- Save the second switch endpoint to use the second button in the main component of the second switch.
      device:set_field(SECOND_SWITCH_ENDPOINT, ep)
    end
  end

  for _, ep in ipairs(button_eps) do
    if _ == 1 then
      -- To use the component name of the first button as button
      component_map["button"] = ep
    elseif _ == 3 then
      -- Save the second button endpoint to use the second button in the main component of the second switch.
      component_map["button2"] = ep
      device:set_field(SECOND_BUTTON_ENDPOINT, ep)
    else
      component_map[string.format("button%d", current_component_number)] = ep
      current_component_number = current_component_number + 1
    end
  end

  local sse = device:get_field(SECOND_SWITCH_ENDPOINT)
  local child_list = device:get_child_list()
  for _, child in pairs(child_list) do
    for k, v in pairs(child) do
      if k == "st_store" then
        for k1, v1 in pairs(v) do
          if string.find(k1, "parent_assigned_child_key") and v1 == string.format("%d", sse) then
            device:set_field(SECOND_SWITCH_ID, child.id)
            device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
            break
          end
        end
        break
      end
    end
  end
end

local function initialize_switch(driver, device)
  -- Aqara Light Switch H2 has the following device types for each endpoint in 4 physical switches.
  -- The device type of switch is the on/off light(0x100) and the device type of button is the generic switch(0xF)
  -- Card 1: switch (ep1, main component), button (ep4, button component, first button)
  -- Card 2: switch (ep2, EDGE_CHILD), button (ep6, second button)
  -- Card 3: button (ep5, EDGE_CHILD, third button)
  -- Card 4: button (ep7, EDGE_CHILD, fourth button)
  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  table.sort(switch_eps)
  table.sort(button_eps)

  local profile_name
  local num_switch_server_eps = 0
  local main_endpoint = device.MATTER_DEFAULT_ENDPOINT

  -- If both switch and button endpoints are present, check the device type on the main switch endpoint.
  -- If it is not a supported device type, return the first light endpoint as the default endpoint.
  if #switch_eps > 0 and #button_eps > 0 then
    main_endpoint = get_first_non_zero_endpoint(switch_eps)
    profile_name = "light-button-electricalMeasurement"
    device:try_update_metadata({ profile = profile_name })
  end

  -- If switch endpoints are present, the first switch endpoint will be the main endpoint.
  -- And other endpoints will be EDGE_CHILD devices.
  for _, ep in ipairs(switch_eps) do
    if device:supports_server_cluster(clusters.OnOff.ID, ep) then
      num_switch_server_eps = num_switch_server_eps + 1
      if ep ~= main_endpoint then -- don't create a child device that maps to the main endpoint
        local name = string.format("%s %d", device.label, num_switch_server_eps)
        local child_profile = assign_child_profile(device, ep)
        driver:try_create_device(
          {
            type = "EDGE_CHILD",
            label = name,
            profile = child_profile,
            parent_device_id = device.id,
            parent_assigned_child_key = string.format("%d", ep),
            vendor_provided_label = name
          }
        )
      end
    end
  end

  for _, ep in ipairs(button_eps) do
    -- the index of first button endpoint is 1
    -- the index of second button endpoint is 3
    -- the index of third button endpoint is 2
    -- the index of fourth button endpoint is 4
    if _ ~= 1 and _ ~= 3 then
      num_switch_server_eps = num_switch_server_eps + 1
      if ep ~= main_endpoint then -- don't create a child device that maps to the main endpoint
        local name = string.format("%s %d", device.label, num_switch_server_eps)
        local child_profile = assign_child_profile(device, ep)
        driver:try_create_device(
          {
            type = "EDGE_CHILD",
            label = name,
            profile = child_profile,
            parent_device_id = device.id,
            parent_assigned_child_key = string.format("%d", ep),
            vendor_provided_label = name
          }
        )
      end
    end
  end

  -- If the device is a parent child device, then set the find_child function on init.
  -- This is persisted because initialize_switch is only run once, but find_child function should be set
  -- on each driver init.
  device:set_field(IS_PARENT_CHILD_DEVICE, true, {persist = true})
  device:set_field(DEFERRED_CONFIGURE, true)
end

local function component_to_endpoint(device, component)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  if map[component] then
    return map[component]
  end
  return find_default_endpoint(device)
end

local function endpoint_to_component(device, ep)
  local map = device:get_field(COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

local function device_init(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    -- initialize_switch will create parent-child devices as needed for multi-switch devices.
    -- However, we want to maintain support for existing MCD devices, so do not initialize
    -- device if it has already been previously initialized as an MCD device.
    -- when unit testing, call initialize_switch elsewhere
    if not device:get_field(TEST_CONFIGURE) then
      if not device:get_field(COMPONENT_TO_ENDPOINT_MAP) then
        -- create child devices as needed for multi-switch devices
        initialize_switch(driver, device)
      end
      save_second_switch_id(device)
    end
    device:set_component_to_endpoint_fn(component_to_endpoint)
    device:set_endpoint_to_component_fn(endpoint_to_component)
    if device:get_field(IS_PARENT_CHILD_DEVICE) == true then
      device:set_find_child(find_child)
    end

    for _, id in ipairs(device_type_id_map) do
      for _, attr in pairs(device_type_attribute_map[id] or {}) do
        if id == GENERIC_SWITCH_ID then
          device:add_subscribed_event(attr)
        else
          device:add_subscribed_attribute(attr)
        end
      end
    end

    configure_buttons(device)
    device:subscribe()
  end
end

local function device_removed(driver, device)
  log.info("device removed")
  delete_export_poll_schedule(device)
end

local function handle_refresh(driver, device, cmd)
  --Note: no endpoint specified indicates a wildcard endpoint
  local req = clusters.OnOff.attributes.OnOff:read(device)
  device:send(req)
end

-- Fallback handler for responses that dont have their own handler
local function matter_handler(driver, device, response_block)
  log.info(string.format("Fallback handler for %s", response_block))
end

local function on_off_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.on())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switch.switch.off())
  end
end

--TODO setup configure handler to read this attribute.
local function cumul_energy_exported_handler(driver, device, ib, response)
  if ib.data.elements.energy then
    local watt_hour_value = ib.data.elements.energy.value / CONVERSION_CONST_MILLIWATT_TO_WATT
    device:set_field(TOTAL_EXPORTED_ENERGY, watt_hour_value)
    device:emit_event(capabilities.energyMeter.energy({ value = watt_hour_value, unit = "Wh" }))
  end
end

local function per_energy_exported_handler(driver, device, ib, response)
  if ib.data.elements.energy then
    local watt_hour_value = ib.data.elements.energy.value / CONVERSION_CONST_MILLIWATT_TO_WATT
    local latest_energy_report = device:get_field(TOTAL_EXPORTED_ENERGY) or 0
    local summed_energy_report = latest_energy_report + watt_hour_value
    device:set_field(TOTAL_EXPORTED_ENERGY, summed_energy_report)
  end
end

local function energy_report_handler_factory(is_cumulative_report)
  return function(driver, device, ib, response)
    if not device:get_field(EXPORT_POLL_TIMER_SETTING_ATTEMPTED) then
      set_poll_report_timer_and_schedule(device, is_cumulative_report)
    end
    if is_cumulative_report then
      cumul_energy_exported_handler(driver, device, ib, response)
    elseif device:get_field(CUMULATIVE_REPORTS_NOT_SUPPORTED) then
      per_energy_exported_handler(driver, device, ib, response)
    end
  end
end

local function initial_press_event_handler(driver, device, ib, response)
  if get_field_for_endpoint(device, INITIAL_PRESS_ONLY, ib.endpoint_id) then
    local sbe = device:get_field(SECOND_BUTTON_ENDPOINT)
    if ib.endpoint_id == sbe then
      local sse = device:get_field(SECOND_SWITCH_ENDPOINT)
      local ssi = device:get_field(SECOND_SWITCH_ID)
      local child_list = device:get_child_list()
      for _, child in pairs(child_list) do
        if child.id == ssi then
          device:emit_event_for_endpoint(string.format("%d", sse), capabilities.button.button.pushed({state_change = true}))
          break
        end
      end
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
    end
  end
end

local function active_power_handler(driver, device, ib, response)
  if ib.data.value then
    local watt_value = ib.data.value / CONVERSION_CONST_MILLIWATT_TO_WATT
    device:emit_event(capabilities.powerMeter.power({ value = watt_value, unit = "W"}))
  end
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id or device:get_field(TEST_CONFIGURE) then
    if device:get_field(DEFERRED_CONFIGURE) and device.network_type ~= device_lib.NETWORK_TYPE_CHILD then
      -- profile has changed, and we deferred setting up our buttons, so do that now

      -- for unit testing
      if device:get_field(TEST_CONFIGURE) then
        initialize_switch(driver, device)
      end
      save_second_switch_id(device)
      configure_buttons(device)

      -- Reset the values
      if device:supports_capability(capabilities.powerMeter) then
        device:emit_event(capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
      end
      if device:supports_capability(capabilities.energyMeter) then
        device:emit_event(capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" }))
      end

      device:set_field(DEFERRED_CONFIGURE, nil)
    end
  end
end

local function device_added(driver, device)
  -- refresh child devices to get initial attribute state in case child device
  -- was created after the initial subscription report
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then
    handle_refresh(driver, device)
  end
end

local aqara_light_switch_h2_handler = {
  NAME = "Aqara Light Switch H2 Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    removed = device_removed,
    infoChanged = info_changed,
    doConfigure = do_configure
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.ElectricalPowerMeasurement.ID] = {
        [clusters.ElectricalPowerMeasurement.attributes.ActivePower.ID] = active_power_handler,
      },
      [clusters.ElectricalEnergyMeasurement.ID] = {
        [clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported.ID] = energy_report_handler_factory(true),
      },
    },
    event = {
      [clusters.Switch.ID] = {
        [clusters.Switch.events.InitialPress.ID] = initial_press_event_handler
      },
    },
    fallback = matter_handler,
  },
  subscribed_attributes = {
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.energyMeter.ID] = {
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
    },
    [capabilities.powerMeter.ID] = {
      clusters.ElectricalPowerMeasurement.attributes.ActivePower
    }
  },
  subscribed_events = {
    [capabilities.button.ID] = {
      clusters.Switch.events.InitialPress
    },
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh,
    },
  },
  supported_capabilities = {
    capabilities.switch,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.powerConsumptionReport,
    capabilities.button,
  },
  can_handle = is_aqara_light_switch_h2
}

return aqara_light_switch_h2_handler

