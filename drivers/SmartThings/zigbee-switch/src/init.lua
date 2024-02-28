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
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local configurationMap = require "configurations"
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local ColorControl = clusters.ColorControl
local preferences = require "preferences"
local utils = require "st.utils"

local SANITY_CHECK_MIN_KELVIN = 1000
local SANITY_CHECK_MAX_KELVIN = 10000
local BOUND_RECEIVED = "colorTemp_bound_received"
local MIN = "_MIN"
local MAX = "_MAX"

local function mired_to_kelvin(value)
  local CONVERSION_CONSTANT = 1000000
  if value == 0 then value = 1 end -- shouldn't happen, but has
  -- we divide inside the rounding and multiply outside of it because we expect these
  -- bounds to be multiples of 100
  return utils.round((CONVERSION_CONSTANT / value) / 100) * 100
end

local function info_changed(self, device, event, args)
  preferences.update_preferences(self, device, args)
end

local do_configure = function(self, device)
  device:refresh()
  device:configure()

  -- Additional one time configuration
  if device:supports_capability(capabilities.energyMeter) or device:supports_capability(capabilities.powerMeter) then
    -- Divisor and multipler for EnergyMeter
    device:send(ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
    device:send(ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
    -- Divisor and multipler for PowerMeter
    device:send(SimpleMetering.attributes.Divisor:read(device))
    device:send(SimpleMetering.attributes.Multiplier:read(device))
  end

  if device:supports_capability(capabilities.colorTemperature) then
    device:send(ColorControl.attributes.ColorTempPhysicalMaxMireds:read(device))
    device:send(ColorControl.attributes.ColorTempPhysicalMinMireds:read(device))
  end
end

local mired_bounds_handler_factory = function(minOrMax)
  return function(self, device, value, zb_rx)
    local endpoint_id = zb_rx.address_header.src_endpoint.value
    local temp_in_kelvin = mired_to_kelvin(value.value)
    if temp_in_kelvin > SANITY_CHECK_MIN_KELVIN and temp_in_kelvin < SANITY_CHECK_MAX_KELVIN then
      device:set_field(BOUND_RECEIVED..minOrMax, temp_in_kelvin)
    else
      device.log.warn("Device reported a min or max color temp value outside of reasonable bounds: "..temp_in_kelvin..'K')
    end

    local min = device:get_field(BOUND_RECEIVED..MIN)
    local max = device:get_field(BOUND_RECEIVED..MAX)
    if min ~= nil and max ~= nil and min < max then
      device:emit_event_for_endpoint(endpoint_id, capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = min, maximum = max}}))
      device:set_field(BOUND_RECEIVED..MAX, nil)
      device:set_field(BOUND_RECEIVED..MIN, nil)
    end
  end
end

local function component_to_endpoint(device, component_id)
  local ep_num = component_id:match("switch(%d)")
  return ep_num and tonumber(ep_num) or device.fingerprinted_endpoint_id
end

local function endpoint_to_component(device, ep)
  local switch_comp = string.format("switch%d", ep)
  if device.profile.components[switch_comp] ~= nil then
    return switch_comp
  else
    return "main"
  end
end

local device_init = function(self, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:set_endpoint_to_component_fn(endpoint_to_component)

  local configuration = configurationMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end

  local ias_zone_config_method = configurationMap.get_ias_zone_config_method(device)
  if ias_zone_config_method ~= nil then
    device:set_ias_zone_config_method(ias_zone_config_method)
  end
end

local zigbee_switch_driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.colorControl,
    capabilities.colorTemperature,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.motionSensor
  },
  sub_drivers = {
    require("hanssem"),
    require("aqara"),
    require("aqara-light"),
    require("ezex"),
    require("rexense"),
    require("sinope"),
    require("sinope-dimmer"),
    require("zigbee-dimmer-power-energy"),
    require("zigbee-metering-plug-power-consumption-report"),
    require("jasco"),
    require("multi-switch-no-master"),
    require("zigbee-dual-metering-switch"),
    require("rgb-bulb"),
    require("zigbee-dimming-light"),
    require("white-color-temp-bulb"),
    require("rgbw-bulb"),
    require("zll-dimmer-bulb"),
    require("zigbee-switch-power"),
    require("ge-link-bulb"),
    require("bad_on_off_data_type"),
    require("robb"),
    require("wallhero")
  },
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
    doConfigure = do_configure
  },
  zigbee_handlers = {
    attr = {
      [ColorControl.ID] = {
        [ColorControl.attributes.ColorTempPhysicalMaxMireds.ID] = mired_bounds_handler_factory(MIN), -- max mireds = min kelvin
        [ColorControl.attributes.ColorTempPhysicalMinMireds.ID] = mired_bounds_handler_factory(MAX)  -- min mireds = max kelvin
      }
    }
  }
}

defaults.register_for_default_handlers(zigbee_switch_driver_template,
  zigbee_switch_driver_template.supported_capabilities)
local zigbee_switch = ZigbeeDriver("zigbee_switch", zigbee_switch_driver_template)
zigbee_switch:run()
