-- Copyright 2025 SmartThings
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
local clusters = require "st.matter.clusters"
local device_lib = require "st.device"
local log = require "log"
local lua_socket = require "socket"

local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
local EMULATE_HELD = "__emulate_held" -- for non-MSR (MomentarySwitchRelease) devices we can emulate this on the software side
-- Some switches will send a MultiPressComplete event as part of a long press sequence. Normally the driver will create a
-- button capability event on receipt of MultiPressComplete, but in this case that would result in an extra event because
-- the "held" capability event is generated when the LongPress event is received. The IGNORE_NEXT_MPC flag is used
-- to tell the driver to ignore MultiPressComplete if it is received after a long press to avoid this extra event.
local IGNORE_NEXT_MPC = "__ignore_next_mpc"
local INITIAL_PRESS_ONLY = "__initial_press_only" -- for devices that support MS (MomentarySwitch), but not MSR (MomentarySwitchRelease)
local START_BUTTON_PRESS = "__start_button_press"
local SUPPORTS_MULTI_PRESS = "__multi_button" -- for MSM devices (MomentarySwitchMultiPress), create an event on receipt of MultiPressComplete

local AQARA_MANUFACTURER_ID = 0x115F
local AQARA_CLIMATE_SENSOR_W100_ID = 0x2004

local TIMEOUT_THRESHOLD = 10 -- arbitrary timeout
local HELD_THRESHOLD = 1

local function tbl_contains(array, value)
  for _, element in ipairs(array) do
    if element == value then
      return true
    end
  end
  return false
end

local function get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

local function set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
end

local function init_press(device, endpoint)
  set_field_for_endpoint(device, START_BUTTON_PRESS, endpoint, lua_socket.gettime(), {persist = false})
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

-- helper function to create list of multi press values
local function create_multi_press_values_list(size, supportsHeld)
  local list = {"pushed", "double"}
  if supportsHeld then table.insert(list, "held") end
  -- add multi press values of 3 or greater to the list
  for i=3, size do
    table.insert(list, string.format("pushed_%dx", i))
  end
  return list
end

local function emulate_held_event(device, ep)
  local now = lua_socket.gettime()
  local press_init = get_field_for_endpoint(device, START_BUTTON_PRESS, ep) or now -- if we don't have an init time, assume instant release
  if (now - press_init) < TIMEOUT_THRESHOLD then
    if (now - press_init) > HELD_THRESHOLD then
      device:emit_event_for_endpoint(ep, capabilities.button.button.held({state_change = true}))
    else
      device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = true}))
    end
  end
  set_field_for_endpoint(device, START_BUTTON_PRESS, ep, nil, {persist = false})
end

local buttons = {}

function buttons.build_component_map(device, main_endpoint, button_eps)
  -- create component mapping on the main profile button endpoints
  table.sort(button_eps)
  local component_map = {}
  component_map["main"] = main_endpoint
  for component_num, ep in ipairs(button_eps) do
    if ep ~= main_endpoint then
      local button_component = "button"
      if #button_eps > 1 then
        button_component = button_component .. component_num
      end
      component_map[button_component] = ep
    end
  end
  device:set_field(COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
end

function buttons.build_profile(device, num_button_eps, device_supports_button_switch_combination)
  local profile_name = string.gsub(num_button_eps .. "-button", "1%-", "") -- remove the "1-" in a device with 1 button ep
  if device_supports_button_switch_combination then
    profile_name = "light-level-" .. profile_name
  end
  local battery_supported = #device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY}) > 0
  if battery_supported then -- battery profiles are configured later, in power_source_attribute_list_handler
    device:send(clusters.PowerSource.attributes.AttributeList:read(device))
  else
    device:try_update_metadata({profile = profile_name})
  end
end

function buttons.configure(device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    local ms_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
    local msr_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE})
    local msl_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS})
    local msm_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS})
    for _, ep in ipairs(ms_eps) do
      if device.profile.components[endpoint_to_component(device, ep)] then
        device.log.info_with({hub_logs=true}, string.format("Configuring Supported Values for generic switch endpoint %d", ep))
        local supportedButtonValues_event
        -- this ordering is important, since MSM & MSL devices must also support MSR
        if tbl_contains(msm_eps, ep) then
          supportedButtonValues_event = nil -- deferred to the max press handler
          device:send(clusters.Switch.attributes.MultiPressMax:read(device, ep))
          set_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ep, true, {persist = true})
        elseif tbl_contains(msl_eps, ep) then
          supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})
        elseif tbl_contains(msr_eps, ep) then
          supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})
          set_field_for_endpoint(device, EMULATE_HELD, ep, true, {persist = true})
        else -- this switch endpoint only supports momentary switch, no release events
          supportedButtonValues_event = capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})
          set_field_for_endpoint(device, INITIAL_PRESS_ONLY, ep, true, {persist = true})
        end
        if supportedButtonValues_event then
          device:emit_event_for_endpoint(ep, supportedButtonValues_event)
        end
        device:emit_event_for_endpoint(ep, capabilities.button.button.pushed({state_change = false}))
      else
        device.log.info_with({hub_logs=true}, string.format("Component not found for generic switch endpoint %d. Skipping Supported Value configuration", ep))
      end
    end
  end
end

function buttons.initial_press_event_handler(driver, device, ib, response)
  if get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    -- Receipt of an InitialPress event means we do not want to ignore the next MultiPressComplete event
    -- or else we would potentially not create the expected button capability event
    set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, nil)
  elseif get_field_for_endpoint(device, INITIAL_PRESS_ONLY, ib.endpoint_id) then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
  elseif get_field_for_endpoint(device, EMULATE_HELD, ib.endpoint_id) then
    -- if our button doesn't differentiate between short and long holds, do it in code by keeping track of the press down time
    init_press(device, ib.endpoint_id)
  end
end

-- if the device distinguishes a long press event, it will always be a "held"
-- there's also a "long release" event, but this event is required to come first
function buttons.long_press_event_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.held({state_change = true}))
  if get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    -- Ignore the next MultiPressComplete event if it is sent as part of this "long press" event sequence
    set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, true)
  end
end

function buttons.short_release_event_handler(driver, device, ib, response)
  if not get_field_for_endpoint(device, SUPPORTS_MULTI_PRESS, ib.endpoint_id) then
    if get_field_for_endpoint(device, EMULATE_HELD, ib.endpoint_id) then
      emulate_held_event(device, ib.endpoint_id)
    else
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.button.pushed({state_change = true}))
    end
  end
end

function buttons.multi_press_complete_event_handler(driver, device, ib, response)
  -- in the case of multiple button presses
  -- emit number of times, multiple presses have been completed
  if ib.data and not get_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id) then
    local press_value = ib.data.elements.total_number_of_presses_counted.value
    --capability only supports up to 6 presses
    if press_value < 7 then
      local button_event = capabilities.button.button.pushed({state_change = true})
      if press_value == 2 then
        button_event = capabilities.button.button.double({state_change = true})
      elseif press_value > 2 then
        button_event = capabilities.button.button(string.format("pushed_%dx", press_value), {state_change = true})
      end
      device:emit_event_for_endpoint(ib.endpoint_id, button_event)
    else
      log.info(string.format("Number of presses (%d) not supported by capability", press_value))
    end
  end
  set_field_for_endpoint(device, IGNORE_NEXT_MPC, ib.endpoint_id, nil)
end

function buttons.battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

function buttons.battery_charge_level_attr_handler(driver, device, ib, response)
  if ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.OK then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.WARNING then
    device:emit_event(capabilities.batteryLevel.battery.warning())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.CRITICAL then
    device:emit_event(capabilities.batteryLevel.battery.critical())
  end
end

function buttons.power_source_attribute_list_handler(driver, device, ib, response)
  local profile_name = ""
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
  for _, attr in ipairs(ib.data.elements) do
    -- Re-profile the device if BatPercentRemaining (Attribute ID 0x0C) or
    -- BatChargeLevel (Attribute ID 0x0E) is present.
    if attr.value == 0x0C then
      profile_name = "button-battery"
      break
    elseif attr.value == 0x0E then
      profile_name = "button-batteryLevel"
      break
    end
  end
  if profile_name ~= "" then
    if #button_eps > 1 then
      profile_name = string.format("%d-", #button_eps) .. profile_name
    end
    if device.manufacturer_info.vendor_id == AQARA_MANUFACTURER_ID and
       device.manufacturer_info.product_id == AQARA_CLIMATE_SENSOR_W100_ID then
      profile_name = profile_name .. "-temperature-humidity"
    end
    device:try_update_metadata({ profile = profile_name })
  end
end

function buttons.max_press_handler(driver, device, ib, response)
  local max = ib.data.value or 1 --get max number of presses
  device.log.debug("Device supports "..max.." presses")
  -- capability only supports up to 6 presses
  if max > 6 then
    log.info("Device supports more than 6 presses")
    max = 6
  end
  local MSL = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS})
  local supportsHeld = tbl_contains(MSL, ib.endpoint_id)
  local values = create_multi_press_values_list(max, supportsHeld)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.button.supportedButtonValues(values, {visibility = {displayed = false}}))
end

return buttons
