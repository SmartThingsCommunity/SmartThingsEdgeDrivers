-- Copyright 2024 SmartThings
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
local IASZone = (require "st.zigbee.zcl.clusters").IASZone
local zcl_clusters   = require "st.zigbee.zcl.clusters"
local PowerConfiguration = zcl_clusters.PowerConfiguration
local supported_values = require "zigbee-multi-button.supported_values"

local log = require "log"


local LINXURA_BUTTON_FINGERPRINTS = {
  { mfr = "Linxura", model = "Smart Controller"},
  { mfr = "Linxura", model = "Aura Smart Button"}
}

local configuration = {
  {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 0,
    maximum_interval = 3600,
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1
  },
  {
    cluster = PowerConfiguration.ID,
    attribute = PowerConfiguration.attributes.BatteryPercentageRemaining.ID,
    minimum_interval = 0,
    maximum_interval = 3600,
    data_type = PowerConfiguration.attributes.BatteryPercentageRemaining.base_type,
    reportable_change = 2
  }
}
local is_linxura_button = function(opts, driver, device)
  for _, fingerprint in ipairs(LINXURA_BUTTON_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function present_value_attr_handler(driver, device, zone_status, zb_rx)
  log.info("present_value_attr_handler The current value is: ", zone_status.value)
  local status = zone_status
  local button

  local additional_fields = {
    state_change = true
  }
  local event
  local mod = status.value % 6
  if mod == 1 then
    event = capabilities.button.button.pushed(additional_fields)
  elseif mod == 3 then
    event = capabilities.button.button.double(additional_fields)
  elseif mod == 5 then
    event = capabilities.button.button.held(additional_fields)
  else
    return false
  end

  if (event) then
    button = string.format("button%d", status.value // 6 + 1)
    device:emit_component_event(device.profile.components[button], event)
  end
end

local function battery_attr_handler(driver, device, value, zb_rx)
  local raw = value.value
  if raw == nil then return end

  local pct = nil
  if raw == 0xFF then
    log.info("BatteryPercentageRemaining is unknown (0xFF)")
  else
    pct = math.floor(math.max(0, math.min(200, raw)) / 2)
  end

  if pct then
    device:emit_event(capabilities.battery.battery(pct))
  end
end
local function device_init(driver, device)
  for _, attribute in ipairs(configuration) do
    device:add_configured_attribute(attribute)
  end
end

local function device_added(driver, device)
  local config = supported_values.get_device_parameters(device)
  for _, component in pairs(device.profile.components) do
    if config ~= nil then
      local number_of_buttons = component.id == "main" and config.NUMBER_OF_BUTTONS or 1
      device:emit_component_event(component,
        capabilities.button.supportedButtonValues(config.SUPPORTED_BUTTON_VALUES, { visibility = { displayed = false } }))
      device:emit_component_event(component,
        capabilities.button.numberOfButtons({ value = number_of_buttons }, { visibility = { displayed = false } }))
    else
      device:emit_component_event(component,
        capabilities.button.supportedButtonValues({ "pushed", "held" }, { visibility = { displayed = false } }))
      device:emit_component_event(component,
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } }))
    end
  end
  device:emit_event(capabilities.button.button.pushed({state_change = false}))

  -- device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end

local function do_configure(driver, device)
  device:configure()
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
end
local linxura_device_handler = {
  NAME = "Linxura Device Handler",
  lifecycle_handlers = {
    init = device_init,
    added       = device_added,
    doConfigure = do_configure,
  },

  zigbee_handlers = {
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = present_value_attr_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_attr_handler
      }
    }
  },

  can_handle = is_linxura_button
}

return linxura_device_handler
