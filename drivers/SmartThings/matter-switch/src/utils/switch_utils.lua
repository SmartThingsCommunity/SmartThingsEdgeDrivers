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

local fields = require "utils.switch_fields"
local st_utils = require "st.utils"
local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local log = require "log"

local utils = {}

function utils.tbl_contains(array, value)
  for _, element in ipairs(array) do
    if element == value then
      return true
    end
  end
  return false
end

function utils.convert_huesat_st_to_matter(val)
  return st_utils.clamp_value(math.floor((val * 0xFE) / 100.0 + 0.5), fields.CURRENT_HUESAT_ATTR_MIN, fields.CURRENT_HUESAT_ATTR_MAX)
end

function utils.get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

function utils.set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
end

function utils.mired_to_kelvin(value, minOrMax)
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
  if minOrMax == fields.COLOR_TEMP_MIN then
    return st_utils.round(fields.MIRED_KELVIN_CONVERSION_CONSTANT / (kelvin_step_size * (value + 1)) + rounding_value) * kelvin_step_size
  elseif minOrMax == fields.COLOR_TEMP_MAX then
    return st_utils.round(fields.MIRED_KELVIN_CONVERSION_CONSTANT / (kelvin_step_size * (value - 1)) - rounding_value) * kelvin_step_size
  else
    log.warn_with({hub_logs = true}, "Attempted to convert temperature unit for an undefined value")
  end
end

function utils.check_field_name_updates(device)
  for _, field in ipairs(fields.updated_fields) do
    if device:get_field(field.current_field_name) then
      if field.updated_field_name ~= nil then
        device:set_field(field.updated_field_name, device:get_field(field.current_field_name), {persist = true})
      end
      device:set_field(field.current_field_name, nil)
    end
  end
end

--- device_type_supports_button_switch_combination helper function used to check
--- whether the device type for an endpoint is currently supported by a profile for
--- combination button/switch devices.
function utils.device_type_supports_button_switch_combination(device, endpoint_id)
  for _, ep in ipairs(device.endpoints) do
    if ep.endpoint_id == endpoint_id then
      for _, dt in ipairs(ep.device_types) do
        if dt.device_type_id == fields.DIMMABLE_LIGHT_DEVICE_TYPE_ID then
          for _, fingerprint in ipairs(fields.child_device_profile_overrides_per_vendor_id[0x115F]) do
            if device.manufacturer_info and device.manufacturer_info.product_id == fingerprint.product_id then
              return false -- For Aqara Dimmer Switch with Button.
            end
          end
          return true
        end
      end
    end
  end
  return false
end

--- find_default_endpoint is a helper function to handle situations where
--- device does not have endpoint ids in sequential order from 1
function utils.find_default_endpoint(device)
  if device.manufacturer_info and
    device.manufacturer_info.vendor_id == fields.AQARA_MANUFACTURER_ID and
    device.manufacturer_info.product_id == fields.AQARA_CLIMATE_SENSOR_W100_ID then
    -- In case of Aqara Climate Sensor W100, in order to sequentially set the button name to button 1, 2, 3
    return device.MATTER_DEFAULT_ENDPOINT
  end

  local switch_eps = device:get_endpoints(clusters.OnOff.ID)
  local button_eps = device:get_endpoints(clusters.Switch.ID, {feature_bitmap=clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH})

  local get_first_non_zero_endpoint = function(endpoints)
    table.sort(endpoints)
    for _,ep in ipairs(endpoints) do
      if ep ~= 0 then -- 0 is the matter RootNode endpoint
        return ep
      end
    end
    return nil
  end

  -- Return the first switch endpoint as the default endpoint if no button endpoints are present
  if #button_eps == 0 and #switch_eps > 0 then
    return get_first_non_zero_endpoint(switch_eps)
  end

  -- Return the first button endpoint as the default endpoint if no switch endpoints are present
  if #switch_eps == 0 and #button_eps > 0 then
    return get_first_non_zero_endpoint(button_eps)
  end

  -- If both switch and button endpoints are present, check the device type on the main switch
  -- endpoint. If it is not a supported device type, return the first button endpoint as the
  -- default endpoint.
  if #switch_eps > 0 and #button_eps > 0 then
    local main_endpoint = get_first_non_zero_endpoint(switch_eps)
    if utils.device_type_supports_button_switch_combination(device, main_endpoint) then
      return main_endpoint
    else
      device.log.warn("The main switch endpoint does not contain a supported device type for a component configuration with buttons")
      return get_first_non_zero_endpoint(button_eps)
    end
  end

  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return device.MATTER_DEFAULT_ENDPOINT
end

function utils.component_to_endpoint(device, component)
  local map = device:get_field(fields.COMPONENT_TO_ENDPOINT_MAP) or {}
  if map[component] then
    return map[component]
  end
  return utils.find_default_endpoint(device)
end

function utils.endpoint_to_component(device, ep)
  local map = device:get_field(fields.COMPONENT_TO_ENDPOINT_MAP) or {}
  for component, endpoint in pairs(map) do
    if endpoint == ep then
      return component
    end
  end
  return "main"
end

function utils.find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%d", ep_id))
end

-- Fallback handler for responses that dont have their own handler
function utils.matter_handler(driver, device, response_block)
  device.log.info(string.format("Fallback handler for %s", response_block))
end

--helper function to create list of multi press values
function utils.create_multi_press_values_list(size, supportsHeld)
  local list = {"pushed", "double"}
  if supportsHeld then table.insert(list, "held") end
  -- add multi press values of 3 or greater to the list
  for i=3, size do
    table.insert(list, string.format("pushed_%dx", i))
  end
  return list
end

function utils.detect_bridge(device)
  for _, ep in ipairs(device.endpoints) do
    for _, dt in ipairs(ep.device_types) do
      if dt.device_type_id == fields.AGGREGATOR_DEVICE_TYPE_ID then
        return true
      end
    end
  end
  return false
end

function utils.detect_matter_thing(device)
  for _, capability in ipairs(fields.supported_capabilities) do
    if device:supports_capability(capability) then
      return false
    end
  end
  return device:supports_capability(capabilities.refresh)
end

function utils.report_power_consumption_to_st_energy(device, latest_total_imported_energy_wh)
  local current_time = os.time()
  local last_time = device:get_field(fields.LAST_IMPORTED_REPORT_TIMESTAMP) or 0

  -- Ensure that the previous report was sent at least 15 minutes ago
  if fields.MINIMUM_ST_ENERGY_REPORT_INTERVAL >= (current_time - last_time) then
    return
  end

  device:set_field(fields.LAST_IMPORTED_REPORT_TIMESTAMP, current_time, { persist = true })

  -- Calculate the energy delta between reports
  local energy_delta_wh = 0.0
  local previous_imported_report = device:get_latest_state("main", capabilities.powerConsumptionReport.ID,
    capabilities.powerConsumptionReport.powerConsumption.NAME)
  if previous_imported_report and previous_imported_report.energy then
    energy_delta_wh = math.max(latest_total_imported_energy_wh - previous_imported_report.energy, 0.0)
  end

  local epoch_to_iso8601 = function(time) return os.date("!%Y-%m-%dT%H:%M:%SZ", time) end -- Return an ISO-8061 timestamp from UTC

  -- Report the energy consumed during the time interval. The unit of these values should be 'Wh'
  local power_consumption_component = device.profile.components["main"]
  device:emit_component_event(power_consumption_component, capabilities.powerConsumptionReport.powerConsumption({
    start = epoch_to_iso8601(last_time),
    ["end"] = epoch_to_iso8601(current_time - 1),
    deltaEnergy = energy_delta_wh,
    energy = latest_total_imported_energy_wh
  }))
end

return utils
