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

local button_utils = require "button-utils"
local capabilities = require "st.capabilities"
local color_utils = require "color-utils"
local common_utils = require "common-utils"
local log = require "log"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"
local MatterDriver = require "st.matter.driver"
local modular_profiles_utils = require "modular-profiles-utils"
local utils = require "st.utils"
local device_lib = require "st.device"
local embedded_cluster_utils = require "embedded-cluster-utils"
local version = require "version"

-- Include driver-side definitions when lua libs api version is < 11
if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"
  clusters.ValveConfigurationAndControl = require "ValveConfigurationAndControl"
end

local MOST_RECENT_TEMP = "mostRecentTemp"
local RECEIVED_X = "receivedX"
local RECEIVED_Y = "receivedY"
local HUESAT_SUPPORT = "huesatSupport"
local MIRED_KELVIN_CONVERSION_CONSTANT = 1000000
-- These values are a "sanity check" to check that values we are getting are reasonable
local COLOR_TEMPERATURE_KELVIN_MAX = 15000
local COLOR_TEMPERATURE_KELVIN_MIN = 1000
local COLOR_TEMPERATURE_MIRED_MAX = MIRED_KELVIN_CONVERSION_CONSTANT/COLOR_TEMPERATURE_KELVIN_MIN
local COLOR_TEMPERATURE_MIRED_MIN = MIRED_KELVIN_CONVERSION_CONSTANT/COLOR_TEMPERATURE_KELVIN_MAX
local SWITCH_LEVEL_LIGHTING_MIN = 1
local CURRENT_HUESAT_ATTR_MIN = 0
local CURRENT_HUESAT_ATTR_MAX = 254

local COLOR_TEMP_BOUND_RECEIVED_KELVIN = "__colorTemp_bound_received_kelvin"
local COLOR_TEMP_BOUND_RECEIVED_MIRED = "__colorTemp_bound_received_mired"
local COLOR_TEMP_MIN = "__color_temp_min"
local COLOR_TEMP_MAX = "__color_temp_max"
local LEVEL_BOUND_RECEIVED = "__level_bound_received"
local LEVEL_MIN = "__level_min"
local LEVEL_MAX = "__level_max"
local COLOR_MODE = "__color_mode"

local updated_fields = {
  { current_field_name = "__component_to_endpoint_map_button", updated_field_name = common_utils.COMPONENT_TO_ENDPOINT_MAP },
  { current_field_name = "__switch_intialized", updated_field_name = nil }
}

local HUE_SAT_COLOR_MODE = clusters.ColorControl.types.ColorMode.CURRENT_HUE_AND_CURRENT_SATURATION
local X_Y_COLOR_MODE = clusters.ColorControl.types.ColorMode.CURRENTX_AND_CURRENTY

local CUMULATIVE_REPORTS_NOT_SUPPORTED = "__cumulative_reports_not_supported"
local FIRST_IMPORT_REPORT_TIMESTAMP = "__first_import_report_timestamp"
local IMPORT_POLL_TIMER_SETTING_ATTEMPTED = "__import_poll_timer_setting_attempted"
local IMPORT_REPORT_TIMEOUT = "__import_report_timeout"
local TOTAL_IMPORTED_ENERGY = "__total_imported_energy"
local LAST_IMPORTED_REPORT_TIMESTAMP = "__last_imported_report_timestamp"
local RECURRING_IMPORT_REPORT_POLL_TIMER = "__recurring_import_report_poll_timer"
local MINIMUM_ST_ENERGY_REPORT_INTERVAL = (15 * 60) -- 15 minutes, reported in seconds
local SUBSCRIPTION_REPORT_OCCURRED = "__subscription_report_occurred"
local CONVERSION_CONST_MILLIWATT_TO_WATT = 1000 -- A milliwatt is 1/1000th of a watt

-- Return an ISO-8061 timestamp in UTC
local function iso8061Timestamp(time)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", time)
end

local function delete_import_poll_schedule(device)
  local import_poll_timer = device:get_field(RECURRING_IMPORT_REPORT_POLL_TIMER)
  if import_poll_timer then
    device.thread:cancel_timer(import_poll_timer)
    device:set_field(RECURRING_IMPORT_REPORT_POLL_TIMER, nil)
    device:set_field(IMPORT_POLL_TIMER_SETTING_ATTEMPTED, nil)
  end
end

local function send_import_poll_report(device, latest_total_imported_energy_wh)
  local current_time = os.time()
  local last_time = device:get_field(LAST_IMPORTED_REPORT_TIMESTAMP) or 0
  device:set_field(LAST_IMPORTED_REPORT_TIMESTAMP, current_time, { persist = true })

  -- Calculate the energy delta between reports
  local energy_delta_wh = 0.0
  local previous_imported_report = device:get_latest_state("main", capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME)
  if previous_imported_report and previous_imported_report.energy then
    energy_delta_wh = math.max(latest_total_imported_energy_wh - previous_imported_report.energy, 0.0)
  end

  -- Report the energy consumed during the time interval. The unit of these values should be 'Wh'
  if not device:get_field(common_utils.ENERGY_MANAGEMENT_ENDPOINT) then
    device:emit_event(capabilities.powerConsumptionReport.powerConsumption({
      start = iso8061Timestamp(last_time),
      ["end"] = iso8061Timestamp(current_time - 1),
      deltaEnergy = energy_delta_wh,
      energy = latest_total_imported_energy_wh
    }))
  else
    device:emit_event_for_endpoint(device:get_field(common_utils.ENERGY_MANAGEMENT_ENDPOINT),capabilities.powerConsumptionReport.powerConsumption({
      start = iso8061Timestamp(last_time),
      ["end"] = iso8061Timestamp(current_time - 1),
      deltaEnergy = energy_delta_wh,
      energy = latest_total_imported_energy_wh
    }))
  end
end

local function create_poll_report_schedule(device)
  local import_timer = device.thread:call_on_schedule(
    device:get_field(IMPORT_REPORT_TIMEOUT), function()
    send_import_poll_report(device, device:get_field(TOTAL_IMPORTED_ENERGY))
    end, "polling_import_report_schedule_timer"
  )
  device:set_field(RECURRING_IMPORT_REPORT_POLL_TIMER, import_timer)
end

local function set_poll_report_timer_and_schedule(device, is_cumulative_report)
  local cumul_eps = embedded_cluster_utils.get_endpoints(device,
    clusters.ElectricalEnergyMeasurement.ID,
    {feature_bitmap = clusters.ElectricalEnergyMeasurement.types.Feature.CUMULATIVE_ENERGY })
  if #cumul_eps == 0 then
    device:set_field(CUMULATIVE_REPORTS_NOT_SUPPORTED, true, {persist = true})
  end
  if #cumul_eps > 0 and not is_cumulative_report then
    return
  elseif not device:get_field(SUBSCRIPTION_REPORT_OCCURRED) then
    device:set_field(SUBSCRIPTION_REPORT_OCCURRED, true)
  elseif not device:get_field(FIRST_IMPORT_REPORT_TIMESTAMP) then
    device:set_field(FIRST_IMPORT_REPORT_TIMESTAMP, os.time())
  else
    local first_timestamp = device:get_field(FIRST_IMPORT_REPORT_TIMESTAMP)
    local second_timestamp = os.time()
    local report_interval_secs = second_timestamp - first_timestamp
    device:set_field(IMPORT_REPORT_TIMEOUT, math.max(report_interval_secs, MINIMUM_ST_ENERGY_REPORT_INTERVAL))
    -- the poll schedule is only needed for devices that support powerConsumption
    -- and enable powerConsumption when energy management is defined in root endpoint(0).
    if device:supports_capability(capabilities.powerConsumptionReport) or
       device:get_field(common_utils.ENERGY_MANAGEMENT_ENDPOINT) then
      create_poll_report_schedule(device)
    end
    device:set_field(IMPORT_POLL_TIMER_SETTING_ATTEMPTED, true)
  end
end

local TEMP_BOUND_RECEIVED = "__temp_bound_received"
local TEMP_MIN = "__temp_min"
local TEMP_MAX = "__temp_max"

local function convert_huesat_st_to_matter(val)
  return utils.clamp_value(math.floor((val * 0xFE) / 100.0 + 0.5), CURRENT_HUESAT_ATTR_MIN, CURRENT_HUESAT_ATTR_MAX)
end

local function mired_to_kelvin(value, minOrMax)
  if value == 0 then -- shouldn't happen, but has
    value = 1
    log.warn(string.format("Received a color temperature of 0 mireds. Using a color temperature of 1 mired to avoid divide by zero"))
  end
  -- We divide inside the rounding and multiply outside of it because we expect these
  -- bounds to be multiples of 100. For the maximum mired value (minimum K value),
  -- add 1 before converting and round up to nearest hundreds. For the minimum mired
  -- (maximum K value) value, subtract 1 before converting and round down to nearest
  -- hundreds. Note that 1 is added/subtracted from the mired value in order to avoid
  -- rounding errors from the conversion of Kelvin to mireds.
  local kelvin_step_size = 100
  local rounding_value = 0.5
  if minOrMax == COLOR_TEMP_MIN then
    return utils.round(MIRED_KELVIN_CONVERSION_CONSTANT / (kelvin_step_size * (value + 1)) + rounding_value) * kelvin_step_size
  elseif minOrMax == COLOR_TEMP_MAX then
    return utils.round(MIRED_KELVIN_CONVERSION_CONSTANT / (kelvin_step_size * (value - 1)) - rounding_value) * kelvin_step_size
  else
    log.warn_with({hub_logs = true}, "Attempted to convert temperature unit for an undefined value")
  end
end

local function check_field_name_updates(device)
  for _, field in ipairs(updated_fields) do
    if device:get_field(field.current_field_name) then
      if field.updated_field_name ~= nil then
        device:set_field(field.updated_field_name, device:get_field(field.current_field_name), {persist = true})
      end
      device:set_field(field.current_field_name, nil)
    end
  end
end

local function device_init(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    check_field_name_updates(device)
    device:set_component_to_endpoint_fn(common_utils.component_to_endpoint)
    device:set_endpoint_to_component_fn(common_utils.endpoint_to_component)
    if device:get_field(common_utils.IS_PARENT_CHILD_DEVICE) then
      device:set_find_child(common_utils.find_child)
    end
    local main_endpoint = common_utils.find_default_endpoint(device)
    -- ensure subscription to all endpoint attributes- including those mapped to child devices
    for _, ep in ipairs(device.endpoints) do
      if ep.endpoint_id ~= main_endpoint then
        local id = 0
        for _, dt in ipairs(ep.device_types) do
          id = math.max(id, dt.device_type_id)
        end
        for _, attr in pairs(common_utils.device_type_attribute_map[id] or {}) do
          if id == common_utils.GENERIC_SWITCH_ID and
             attr ~= clusters.PowerSource.attributes.BatPercentRemaining and
             attr ~= clusters.PowerSource.attributes.BatChargeLevel then
            device:add_subscribed_event(attr)
          else
            device:add_subscribed_attribute(attr)
          end
        end
      end
    end
    if device:get_field(modular_profiles_utils.SUPPORTED_COMPONENT_CAPABILITIES) then
      device:extend_device("supports_capability_by_id", modular_profiles_utils.supports_capability_by_id_modular)
    end
    device:subscribe()
  end
end

local function do_configure(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and not common_utils.detect_bridge(device) then
    modular_profiles_utils.match_profile(driver, device)
  end
end

local function driver_switched(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_MATTER and not common_utils.detect_bridge(device) then
    modular_profiles_utils.match_profile(driver, device)
  end
end

local function device_removed(driver, device)
  log.info("device removed")
  delete_import_poll_schedule(device)
end

local function handle_switch_on(driver, device, cmd)
  if type(device.register_native_capability_cmd_handler) == "function" then
    device:register_native_capability_cmd_handler(cmd.capability, cmd.command)
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  --TODO use OnWithRecallGlobalScene for devices with the LT feature
  local req = clusters.OnOff.server.commands.On(device, endpoint_id)
  device:send(req)
end

local function handle_switch_off(driver, device, cmd)
  if type(device.register_native_capability_cmd_handler) == "function" then
    device:register_native_capability_cmd_handler(cmd.capability, cmd.command)
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.OnOff.server.commands.Off(device, endpoint_id)
  device:send(req)
end

local function handle_set_switch_level(driver, device, cmd)
  if type(device.register_native_capability_cmd_handler) == "function" then
    device:register_native_capability_cmd_handler(cmd.capability, cmd.command)
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local level = math.floor(cmd.args.level/100.0 * 254)
  local req = clusters.LevelControl.server.commands.MoveToLevelWithOnOff(device, endpoint_id, level, cmd.args.rate, 0, 0)
  device:send(req)
end

local TRANSITION_TIME = 0 --1/10ths of a second
-- When sent with a command, these options mask and override bitmaps cause the command
-- to take effect when the switch/light is off.
local OPTIONS_MASK = 0x01
local OPTIONS_OVERRIDE = 0x01

local function handle_set_color(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req
  local huesat_endpoints = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.FeatureMap.HUE_AND_SATURATION})
  if common_utils.tbl_contains(huesat_endpoints, endpoint_id) then
    local hue = convert_huesat_st_to_matter(cmd.args.color.hue)
    local sat = convert_huesat_st_to_matter(cmd.args.color.saturation)
    req = clusters.ColorControl.server.commands.MoveToHueAndSaturation(device, endpoint_id, hue, sat, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
  else
    local x, y, _ = utils.safe_hsv_to_xy(cmd.args.color.hue, cmd.args.color.saturation)
    req = clusters.ColorControl.server.commands.MoveToColor(device, endpoint_id, x, y, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
  end
  device:send(req)
end

local function handle_set_hue(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local huesat_endpoints = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.FeatureMap.HUE_AND_SATURATION})
  if common_utils.tbl_contains(huesat_endpoints, endpoint_id) then
    local hue = convert_huesat_st_to_matter(cmd.args.hue)
    local req = clusters.ColorControl.server.commands.MoveToHue(device, endpoint_id, hue, 0, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
    device:send(req)
  else
    log.warn("Device does not support huesat features on its color control cluster")
  end
end

local function handle_set_saturation(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local huesat_endpoints = device:get_endpoints(clusters.ColorControl.ID, {feature_bitmap = clusters.ColorControl.FeatureMap.HUE_AND_SATURATION})
  if common_utils.tbl_contains(huesat_endpoints, endpoint_id) then
    local sat = convert_huesat_st_to_matter(cmd.args.saturation)
    local req = clusters.ColorControl.server.commands.MoveToSaturation(device, endpoint_id, sat, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
    device:send(req)
  else
    log.warn("Device does not support huesat features on its color control cluster")
  end
end

local function handle_set_color_temperature(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local temp_in_kelvin = cmd.args.temperature
  local min_temp_kelvin = common_utils.get_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_KELVIN..COLOR_TEMP_MIN, endpoint_id)
  local max_temp_kelvin = common_utils.get_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_KELVIN..COLOR_TEMP_MAX, endpoint_id)

  local temp_in_mired = utils.round(MIRED_KELVIN_CONVERSION_CONSTANT/temp_in_kelvin)
  if min_temp_kelvin ~= nil and temp_in_kelvin <= min_temp_kelvin then
    temp_in_mired = common_utils.get_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_MIRED..COLOR_TEMP_MAX, endpoint_id)
  elseif max_temp_kelvin ~= nil and temp_in_kelvin >= max_temp_kelvin then
    temp_in_mired = common_utils.get_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_MIRED..COLOR_TEMP_MIN, endpoint_id)
  end
  local req = clusters.ColorControl.server.commands.MoveToColorTemperature(device, endpoint_id, temp_in_mired, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
  device:set_field(MOST_RECENT_TEMP, cmd.args.temperature, {persist = true})
  device:send(req)
end

local function handle_valve_open(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.ValveConfigurationAndControl.server.commands.Open(device, endpoint_id)
  device:send(req)
end

local function handle_valve_close(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.ValveConfigurationAndControl.server.commands.Close(device, endpoint_id)
  device:send(req)
end

local function handle_set_level(driver, device, cmd)
  local commands = clusters.ValveConfigurationAndControl.server.commands
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local level = cmd.args.level
  if not level then
    return
  elseif level == 0 then
    device:send(commands.Close(device, endpoint_id))
  else
    device:send(commands.Open(device, endpoint_id, nil, level))
  end
end

local function set_fan_mode(driver, device, cmd)
  local fan_mode_id
  if cmd.args.fanMode == capabilities.fanMode.fanMode.low.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.LOW
  elseif cmd.args.fanMode == capabilities.fanMode.fanMode.medium.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.MEDIUM
  elseif cmd.args.fanMode == capabilities.fanMode.fanMode.high.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.HIGH
  elseif cmd.args.fanMode == capabilities.fanMode.fanMode.auto.NAME then
    fan_mode_id = clusters.FanControl.attributes.FanMode.AUTO
  else
    fan_mode_id = clusters.FanControl.attributes.FanMode.OFF
  end
  if fan_mode_id then
    local fan_ep = device:get_endpoints(clusters.FanControl.ID)[1]
    device:send(clusters.FanControl.attributes.FanMode:write(device, fan_ep, fan_mode_id))
  end
end

local function set_fan_speed_percent(driver, device, cmd)
  local speed = math.floor(cmd.args.percent)
  local fan_ep = device:get_endpoints(clusters.FanControl.ID)[1]
  device:send(clusters.FanControl.attributes.PercentSetting:write(device, fan_ep, speed))
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
  if type(device.register_native_capability_attr_handler) == "function" then
    device:register_native_capability_attr_handler("switch", "switch")
  end
end

local function level_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    local level = math.floor((ib.data.value / 254.0 * 100) + 0.5)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switchLevel.level(level))
    if type(device.register_native_capability_attr_handler) == "function" then
      device:register_native_capability_attr_handler("switchLevel", "level")
    end
  end
end

local function hue_attr_handler(driver, device, ib, response)
  if device:get_field(COLOR_MODE) == X_Y_COLOR_MODE  or ib.data.value == nil then
    return
  end
  local hue = math.floor((ib.data.value / 0xFE * 100) + 0.5)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.hue(hue))
end

local function sat_attr_handler(driver, device, ib, response)
  if device:get_field(COLOR_MODE) == X_Y_COLOR_MODE  or ib.data.value == nil then
    return
  end
  local sat = math.floor((ib.data.value / 0xFE * 100) + 0.5)
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.saturation(sat))
end

local function temp_attr_handler(driver, device, ib, response)
  local temp_in_mired = ib.data.value
  if temp_in_mired == nil then
    return
  end
  if (temp_in_mired < COLOR_TEMPERATURE_MIRED_MIN or temp_in_mired > COLOR_TEMPERATURE_MIRED_MAX) then
    device.log.warn_with({hub_logs = true}, string.format("Device reported color temperature %d mired outside of sane range of %.2f-%.2f", temp_in_mired, COLOR_TEMPERATURE_MIRED_MIN, COLOR_TEMPERATURE_MIRED_MAX))
    return
  end
  local min_temp_mired = common_utils.get_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_MIRED..COLOR_TEMP_MIN, ib.endpoint_id)
  local max_temp_mired = common_utils.get_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_MIRED..COLOR_TEMP_MAX, ib.endpoint_id)

  local temp = utils.round(MIRED_KELVIN_CONVERSION_CONSTANT/temp_in_mired)
  if min_temp_mired ~= nil and temp_in_mired <= min_temp_mired then
    temp = common_utils.get_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_KELVIN..COLOR_TEMP_MAX, ib.endpoint_id)
  elseif max_temp_mired ~= nil and temp_in_mired >= max_temp_mired then
    temp = common_utils.get_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_KELVIN..COLOR_TEMP_MIN, ib.endpoint_id)
  end

  local temp_device = device
  if device:get_field(common_utils.IS_PARENT_CHILD_DEVICE) == true then
    temp_device = common_utils.find_child(device, ib.endpoint_id) or device
  end
  local most_recent_temp = temp_device:get_field(MOST_RECENT_TEMP)
  -- this is to avoid rounding errors from the round-trip conversion of Kelvin to mireds
  if most_recent_temp ~= nil and
    most_recent_temp <= utils.round(MIRED_KELVIN_CONVERSION_CONSTANT/(temp_in_mired - 1)) and
    most_recent_temp >= utils.round(MIRED_KELVIN_CONVERSION_CONSTANT/(temp_in_mired + 1)) then
      temp = most_recent_temp
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorTemperature.colorTemperature(temp))
end

local mired_bounds_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    local temp_in_mired = ib.data.value
    if temp_in_mired == nil then
      return
    end
    if (temp_in_mired < COLOR_TEMPERATURE_MIRED_MIN or temp_in_mired > COLOR_TEMPERATURE_MIRED_MAX) then
      device.log.warn_with({hub_logs = true}, string.format("Device reported a color temperature %d mired outside of sane range of %.2f-%.2f", temp_in_mired, COLOR_TEMPERATURE_MIRED_MIN, COLOR_TEMPERATURE_MIRED_MAX))
      return
    end
    local temp_in_kelvin = mired_to_kelvin(temp_in_mired, minOrMax)
    common_utils.set_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_KELVIN..minOrMax, ib.endpoint_id, temp_in_kelvin)
    -- the minimum color temp in kelvin corresponds to the maximum temp in mireds
    if minOrMax == COLOR_TEMP_MIN then
      common_utils.set_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_MIRED..COLOR_TEMP_MAX, ib.endpoint_id, temp_in_mired)
    else
      common_utils.set_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_MIRED..COLOR_TEMP_MIN, ib.endpoint_id, temp_in_mired)
    end
    local min = common_utils.get_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_KELVIN..COLOR_TEMP_MIN, ib.endpoint_id)
    local max = common_utils.get_field_for_endpoint(device, COLOR_TEMP_BOUND_RECEIVED_KELVIN..COLOR_TEMP_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = min, maximum = max} }))
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min color temperature %d K that is not lower than the reported max color temperature %d K", min, max))
      end
    end
  end
end

local level_bounds_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local lighting_endpoints = device:get_endpoints(clusters.LevelControl.ID, {feature_bitmap = clusters.LevelControl.FeatureMap.LIGHTING})
    local lighting_support = common_utils.tbl_contains(lighting_endpoints, ib.endpoint_id)
    -- If the lighting feature is supported then we should check if the reported level is at least 1.
    if lighting_support and ib.data.value < SWITCH_LEVEL_LIGHTING_MIN then
      device.log.warn_with({hub_logs = true}, string.format("Lighting device reported a switch level %d outside of supported capability range", ib.data.value))
      return
    end
    -- Convert level from given range of 0-254 to range of 0-100.
    local level = utils.round(ib.data.value / 254.0 * 100)
    -- If the device supports the lighting feature, the minimum capability level should be 1 so we do not send a 0 value for the level attribute
    if lighting_support and level == 0 then
      level = 1
    end
    common_utils.set_field_for_endpoint(device, LEVEL_BOUND_RECEIVED..minOrMax, ib.endpoint_id, level)
    local min = common_utils.get_field_for_endpoint(device, LEVEL_BOUND_RECEIVED..LEVEL_MIN, ib.endpoint_id)
    local max = common_utils.get_field_for_endpoint(device, LEVEL_BOUND_RECEIVED..LEVEL_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        device:emit_event_for_endpoint(ib.endpoint_id, capabilities.switchLevel.levelRange({ value = {minimum = min, maximum = max} }))
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min level value %d that is not lower than the reported max level value %d", min, max))
      end
      common_utils.set_field_for_endpoint(device, LEVEL_BOUND_RECEIVED..LEVEL_MAX, ib.endpoint_id, nil)
      common_utils.set_field_for_endpoint(device, LEVEL_BOUND_RECEIVED..LEVEL_MIN, ib.endpoint_id, nil)
    end
  end
end

local function x_attr_handler(driver, device, ib, response)
  if device:get_field(COLOR_MODE) == HUE_SAT_COLOR_MODE then
    return
  end
  local y = device:get_field(RECEIVED_Y)
  --TODO it is likely that both x and y attributes are in the response (not guaranteed though)
  -- if they are we can avoid setting fields on the device.
  if y == nil then
    device:set_field(RECEIVED_X, ib.data.value)
  else
    local x = ib.data.value
    local h, s, _ = color_utils.safe_xy_to_hsv(x, y)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.hue(h))
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.saturation(s))
    device:set_field(RECEIVED_Y, nil)
  end
end

local function y_attr_handler(driver, device, ib, response)
  if device:get_field(COLOR_MODE) == HUE_SAT_COLOR_MODE then
    return
  end
  local x = device:get_field(RECEIVED_X)
  if x == nil then
    device:set_field(RECEIVED_Y, ib.data.value)
  else
    local y = ib.data.value
    local h, s, _ = color_utils.safe_xy_to_hsv(x, y)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.hue(h))
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.colorControl.saturation(s))
    device:set_field(RECEIVED_X, nil)
  end
end

local function color_mode_attr_handler(driver, device, ib, response)
  if ib.data.value == device:get_field(COLOR_MODE) or (ib.data.value ~= HUE_SAT_COLOR_MODE and ib.data.value ~= X_Y_COLOR_MODE) then
    return
  end
  device:set_field(COLOR_MODE, ib.data.value)
  local req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  if ib.data.value == HUE_SAT_COLOR_MODE then
    req:merge(clusters.ColorControl.attributes.CurrentHue:read())
    req:merge(clusters.ColorControl.attributes.CurrentSaturation:read())
  elseif ib.data.value == X_Y_COLOR_MODE then
    req:merge(clusters.ColorControl.attributes.CurrentX:read())
    req:merge(clusters.ColorControl.attributes.CurrentY:read())
  end
  if #req.info_blocks > 0 then
    device:send(req)
  end
end

--TODO setup configure handler to read this attribute.
local function color_cap_attr_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    if ib.data.value & 0x1 then
      device:set_field(HUESAT_SUPPORT, true)
    end
  end
end

local function illuminance_attr_handler(driver, device, ib, response)
  local lux = math.floor(10 ^ ((ib.data.value - 1) / 10000))
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.illuminanceMeasurement.illuminance(lux))
end

local function occupancy_attr_handler(driver, device, ib, response)
  device:emit_event(ib.data.value == 0x01 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
end

local function cumul_energy_imported_handler(driver, device, ib, response)
  if ib.data.elements.energy then
    local watt_hour_value = ib.data.elements.energy.value / CONVERSION_CONST_MILLIWATT_TO_WATT
    device:set_field(TOTAL_IMPORTED_ENERGY, watt_hour_value, {persist = true})
    if ib.endpoint_id ~= 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.energyMeter.energy({ value = watt_hour_value, unit = "Wh" }))
    else
      -- when energy management is defined in the root endpoint(0), replace it with the first switch endpoint and process it.
      device:emit_event_for_endpoint(device:get_field(common_utils.ENERGY_MANAGEMENT_ENDPOINT), capabilities.energyMeter.energy({ value = watt_hour_value, unit = "Wh" }))
    end
  end
end

local function per_energy_imported_handler(driver, device, ib, response)
  if ib.data.elements.energy then
    local watt_hour_value = ib.data.elements.energy.value / CONVERSION_CONST_MILLIWATT_TO_WATT
    local latest_energy_report = device:get_field(TOTAL_IMPORTED_ENERGY) or 0
    local summed_energy_report = latest_energy_report + watt_hour_value
    device:set_field(TOTAL_IMPORTED_ENERGY, summed_energy_report, {persist = true})
    device:emit_event(capabilities.energyMeter.energy({ value = summed_energy_report, unit = "Wh" }))
  end
end

local function energy_report_handler_factory(is_cumulative_report)
  return function(driver, device, ib, response)
    if not device:get_field(IMPORT_POLL_TIMER_SETTING_ATTEMPTED) then
      set_poll_report_timer_and_schedule(device, is_cumulative_report)
    end
    if is_cumulative_report then
      cumul_energy_imported_handler(driver, device, ib, response)
    elseif device:get_field(CUMULATIVE_REPORTS_NOT_SUPPORTED) then
      per_energy_imported_handler(driver, device, ib, response)
    end
  end
end

local function active_power_handler(driver, device, ib, response)
  if ib.data.value then
    local watt_value = ib.data.value / CONVERSION_CONST_MILLIWATT_TO_WATT
    if ib.endpoint_id ~= 0 then
      device:emit_event_for_endpoint(ib.endpoint_id, capabilities.powerMeter.power({ value = watt_value, unit = "W"}))
    else
      -- when energy management is defined in the root endpoint(0), replace it with the first switch endpoint and process it.
      device:emit_event_for_endpoint(device:get_field(common_utils.ENERGY_MANAGEMENT_ENDPOINT), capabilities.powerMeter.power({ value = watt_value, unit = "W"}))
    end
  end
end

local function valve_state_attr_handler(driver, device, ib, response)
  if ib.data.value == 0 then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.valve.valve.closed())
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.valve.valve.open())
  end
end

local function valve_level_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.level.level(ib.data.value))
  end
end

local function battery_percent_remaining_attr_handler(driver, device, ib, response)
  if ib.data.value then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

local function power_source_attribute_list_handler(driver, device, ib, response)
  local battery_attr_support
  for _, attr in ipairs(ib.data.elements) do
    -- Check if the device supports BatPercentRemaining or BatChargeLevel.
    -- Prefer BatPercentRemaining if available.
    if attr.value == clusters.PowerSource.attributes.BatPercentRemaining.ID then
      battery_attr_support = common_utils.battery_support.BATTERY_PERCENTAGE
      break
    elseif attr.value == clusters.PowerSource.attributes.BatChargeLevel.ID then
      battery_attr_support = common_utils.battery_support.BATTERY_LEVEL
    end
  end
  modular_profiles_utils.match_modular_profile(driver, device, battery_attr_support)
end

local function battery_charge_level_attr_handler(driver, device, ib, response)
  if ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.OK then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.WARNING then
    device:emit_event(capabilities.batteryLevel.battery.warning())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.CRITICAL then
    device:emit_event(capabilities.batteryLevel.battery.critical())
  end
end

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    if device:get_field(modular_profiles_utils.SUPPORTED_COMPONENT_CAPABILITIES) then
      --re-up subscription with new capabilities using the modular supports_capability override
      device:extend_device("supports_capability_by_id", modular_profiles_utils.supports_capability_by_id_modular)
    end
    device:subscribe()
    local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})
    if #button_eps > 0 and device.network_type == device_lib.NETWORK_TYPE_MATTER then
      button_utils.configure_buttons(device)
    end
  end
end

local function device_added(driver, device)
  -- refresh child devices to get an initial attribute state for OnOff in case child device
  -- was created after the initial subscription report
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then
    local req = clusters.OnOff.attributes.OnOff:read(device)
    device:send(req)
  end

  -- call device init in case init is not called after added due to device caching
  device_init(driver, device)
end

local function temperature_attr_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local temp = measured_value / 100.0
    local unit = "C"
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperature({value = temp, unit = unit}))
  end
end

local temp_attr_handler_factory = function(minOrMax)
  return function(driver, device, ib, response)
    if ib.data.value == nil then
      return
    end
    local temp = ib.data.value / 100.0
    local unit = "C"
    common_utils.set_field_for_endpoint(device, TEMP_BOUND_RECEIVED..minOrMax, ib.endpoint_id, temp)
    local min = common_utils.get_field_for_endpoint(device, TEMP_BOUND_RECEIVED..TEMP_MIN, ib.endpoint_id)
    local max = common_utils.get_field_for_endpoint(device, TEMP_BOUND_RECEIVED..TEMP_MAX, ib.endpoint_id)
    if min ~= nil and max ~= nil then
      if min < max then
        -- Only emit the capability for RPC version >= 5 (unit conversion for
        -- temperature range capability is only supported for RPC >= 5)
        if version.rpc >= 5 then
          device:emit_event_for_endpoint(ib.endpoint_id, capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = min, maximum = max }, unit = unit }))
        end
        common_utils.set_field_for_endpoint(device, TEMP_BOUND_RECEIVED..TEMP_MIN, ib.endpoint_id, nil)
        common_utils.set_field_for_endpoint(device, TEMP_BOUND_RECEIVED..TEMP_MAX, ib.endpoint_id, nil)
      else
        device.log.warn_with({hub_logs = true}, string.format("Device reported a min temperature %d that is not lower than the reported max temperature %d", min, max))
      end
    end
  end
end

local function humidity_attr_handler(driver, device, ib, response)
  local measured_value = ib.data.value
  if measured_value ~= nil then
    local humidity = utils.round(measured_value / 100.0)
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.relativeHumidityMeasurement.humidity(humidity))
  end
end

local function fan_mode_handler(driver, device, ib, response)
  if ib.data.value == clusters.FanControl.attributes.FanMode.OFF then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode("off"))
  elseif ib.data.value == clusters.FanControl.attributes.FanMode.LOW then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode("low"))
  elseif ib.data.value == clusters.FanControl.attributes.FanMode.MEDIUM then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode("medium"))
  elseif ib.data.value == clusters.FanControl.attributes.FanMode.HIGH then
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode("high"))
  else
    device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanMode.fanMode("auto"))
  end
end

local function fan_mode_sequence_handler(driver, device, ib, response)
  local supportedFanModes
  if ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.low.NAME,
      capabilities.fanMode.fanMode.medium.NAME,
      capabilities.fanMode.fanMode.high.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.low.NAME,
      capabilities.fanMode.fanMode.high.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_MED_HIGH_AUTO then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.low.NAME,
      capabilities.fanMode.fanMode.medium.NAME,
      capabilities.fanMode.fanMode.high.NAME,
      capabilities.fanMode.fanMode.auto.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_LOW_HIGH_AUTO then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.low.NAME,
      capabilities.fanMode.fanMode.high.NAME,
      capabilities.fanMode.fanMode.auto.NAME
    }
  elseif ib.data.value == clusters.FanControl.attributes.FanModeSequence.OFF_ON_AUTO then
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.high.NAME,
      capabilities.fanMode.fanMode.auto.NAME
    }
  else
    supportedFanModes = {
      capabilities.fanMode.fanMode.off.NAME,
      capabilities.fanMode.fanMode.high.NAME
    }
  end
  local event = capabilities.fanMode.supportedFanModes(supportedFanModes, {visibility = {displayed = false}})
  device:emit_event_for_endpoint(ib.endpoint_id, event)
end

local function fan_speed_percent_attr_handler(driver, device, ib, response)
  if ib.data.value == nil or ib.data.value < 0 or ib.data.value > 100 then
    return
  end
  device:emit_event_for_endpoint(ib.endpoint_id, capabilities.fanSpeedPercent.percent(ib.data.value))
end

local matter_driver_template = {
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    removed = device_removed,
    infoChanged = info_changed,
    doConfigure = do_configure,
    driverSwitched = driver_switched
  },
  matter_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler,
      },
      [clusters.LevelControl.ID] = {
        [clusters.LevelControl.attributes.CurrentLevel.ID] = level_attr_handler,
        [clusters.LevelControl.attributes.MaxLevel.ID] = level_bounds_handler_factory(LEVEL_MAX),
        [clusters.LevelControl.attributes.MinLevel.ID] = level_bounds_handler_factory(LEVEL_MIN),
      },
      [clusters.ColorControl.ID] = {
        [clusters.ColorControl.attributes.CurrentHue.ID] = hue_attr_handler,
        [clusters.ColorControl.attributes.CurrentSaturation.ID] = sat_attr_handler,
        [clusters.ColorControl.attributes.ColorTemperatureMireds.ID] = temp_attr_handler,
        [clusters.ColorControl.attributes.CurrentX.ID] = x_attr_handler,
        [clusters.ColorControl.attributes.CurrentY.ID] = y_attr_handler,
        [clusters.ColorControl.attributes.ColorMode.ID] = color_mode_attr_handler,
        [clusters.ColorControl.attributes.ColorCapabilities.ID] = color_cap_attr_handler,
        [clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds.ID] = mired_bounds_handler_factory(COLOR_TEMP_MIN), -- max mireds = min kelvin
        [clusters.ColorControl.attributes.ColorTempPhysicalMinMireds.ID] = mired_bounds_handler_factory(COLOR_TEMP_MAX), -- min mireds = max kelvin
      },
      [clusters.IlluminanceMeasurement.ID] = {
        [clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID] = illuminance_attr_handler
      },
      [clusters.OccupancySensing.ID] = {
        [clusters.OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler,
      },
      [clusters.ElectricalPowerMeasurement.ID] = {
        [clusters.ElectricalPowerMeasurement.attributes.ActivePower.ID] = active_power_handler,
      },
      [clusters.ElectricalEnergyMeasurement.ID] = {
        [clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported.ID] = energy_report_handler_factory(true),
        [clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported.ID] = energy_report_handler_factory(false),
      },
      [clusters.ValveConfigurationAndControl.ID] = {
        [clusters.ValveConfigurationAndControl.attributes.CurrentState.ID] = valve_state_attr_handler,
        [clusters.ValveConfigurationAndControl.attributes.CurrentLevel.ID] = valve_level_attr_handler
      },
      [clusters.PowerSource.ID] = {
        [clusters.PowerSource.attributes.AttributeList.ID] = power_source_attribute_list_handler,
        [clusters.PowerSource.attributes.BatChargeLevel.ID] = battery_charge_level_attr_handler,
        [clusters.PowerSource.attributes.BatPercentRemaining.ID] = battery_percent_remaining_attr_handler,
      },
      [clusters.Switch.ID] = {
        [clusters.Switch.attributes.MultiPressMax.ID] = button_utils.max_press_handler
      },
      [clusters.RelativeHumidityMeasurement.ID] = {
        [clusters.RelativeHumidityMeasurement.attributes.MeasuredValue.ID] = humidity_attr_handler
      },
      [clusters.TemperatureMeasurement.ID] = {
        [clusters.TemperatureMeasurement.attributes.MeasuredValue.ID] = temperature_attr_handler,
        [clusters.TemperatureMeasurement.attributes.MinMeasuredValue.ID] = temp_attr_handler_factory(TEMP_MIN),
        [clusters.TemperatureMeasurement.attributes.MaxMeasuredValue.ID] = temp_attr_handler_factory(TEMP_MAX),
      },
      [clusters.FanControl.ID] = {
        [clusters.FanControl.attributes.FanModeSequence.ID] = fan_mode_sequence_handler,
        [clusters.FanControl.attributes.FanMode.ID] = fan_mode_handler,
        [clusters.FanControl.attributes.PercentCurrent.ID] = fan_speed_percent_attr_handler
      }
    },
    event = {
      [clusters.Switch.ID] = {
        [clusters.Switch.events.InitialPress.ID] = button_utils.initial_press_event_handler,
        [clusters.Switch.events.LongPress.ID] = button_utils.long_press_event_handler,
        [clusters.Switch.events.ShortRelease.ID] = button_utils.short_release_event_handler,
        [clusters.Switch.events.MultiPressComplete.ID] = button_utils.multi_press_complete_event_handler
      }
    },
    fallback = matter_handler,
  },
  subscribed_attributes = {
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.switchLevel.ID] = {
      clusters.LevelControl.attributes.CurrentLevel,
      clusters.LevelControl.attributes.MaxLevel,
      clusters.LevelControl.attributes.MinLevel,
    },
    [capabilities.colorControl.ID] = {
      clusters.ColorControl.attributes.ColorMode,
      clusters.ColorControl.attributes.CurrentHue,
      clusters.ColorControl.attributes.CurrentSaturation,
      clusters.ColorControl.attributes.CurrentX,
      clusters.ColorControl.attributes.CurrentY,
    },
    [capabilities.colorTemperature.ID] = {
      clusters.ColorControl.attributes.ColorTemperatureMireds,
      clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
      clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
    },
    [capabilities.illuminanceMeasurement.ID] = {
      clusters.IlluminanceMeasurement.attributes.MeasuredValue
    },
    [capabilities.motionSensor.ID] = {
      clusters.OccupancySensing.attributes.Occupancy
    },
    [capabilities.valve.ID] = {
      clusters.ValveConfigurationAndControl.attributes.CurrentState
    },
    [capabilities.level.ID] = {
      clusters.ValveConfigurationAndControl.attributes.CurrentLevel
    },
    [capabilities.battery.ID] = {
      clusters.PowerSource.attributes.BatPercentRemaining,
    },
    [capabilities.batteryLevel.ID] = {
      clusters.PowerSource.attributes.BatChargeLevel,
    },
    [capabilities.energyMeter.ID] = {
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
      clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported
    },
    [capabilities.powerMeter.ID] = {
      clusters.ElectricalPowerMeasurement.attributes.ActivePower
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue,
      clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
      clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
    },
    [capabilities.fanMode.ID] = {
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode
    },
    [capabilities.fanSpeedPercent.ID] = {
      clusters.FanControl.attributes.PercentCurrent
    }
  },
  subscribed_events = {
    [capabilities.button.ID] = {
      clusters.Switch.events.InitialPress,
      clusters.Switch.events.LongPress,
      clusters.Switch.events.ShortRelease,
      clusters.Switch.events.MultiPressComplete,
    },
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = handle_set_switch_level
    },
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = handle_set_color,
      [capabilities.colorControl.commands.setHue.NAME] = handle_set_hue,
      [capabilities.colorControl.commands.setSaturation.NAME] = handle_set_saturation,
    },
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = handle_set_color_temperature,
    },
    [capabilities.valve.ID] = {
      [capabilities.valve.commands.open.NAME] = handle_valve_open,
      [capabilities.valve.commands.close.NAME] = handle_valve_close
    },
    [capabilities.level.ID] = {
      [capabilities.level.commands.setLevel.NAME] = handle_set_level
    },
    [capabilities.fanMode.ID] = {
      [capabilities.fanMode.commands.setFanMode.NAME] = set_fan_mode
    },
    [capabilities.fanSpeedPercent.ID] = {
      [capabilities.fanSpeedPercent.commands.setPercent.NAME] = set_fan_speed_percent
    }
  },
  supported_capabilities = common_utils.supported_capabilities,
  sub_drivers = {
    require("aqara-cube"),
    require("eve-energy"),
    require("static-profiles"),
    require("third-reality-mk1")
  }
}

local matter_driver = MatterDriver("matter-switch", matter_driver_template)
log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()
