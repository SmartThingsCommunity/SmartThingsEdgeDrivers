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

local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local supported_values = require "zigbee-multi-button.supported_values"

local PowerConfiguration = clusters.PowerConfiguration

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MULTISTATE_INPUT_ATTRIBUTE_ID = 0x0125
local MULTISTATE_INPUT_CLUSTER_ID = 0x0012
local PRESENT_ATTRIBUTE_ID = 0x0055
local MFG_CODE = 0x115F

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.remote.b1acn02" },
  { mfr = "LUMI", model = "lumi.remote.acn003" },
  { mfr = "LUMI", model = "lumi.remote.b18ac1" },
  { mfr = "LUMI", model = "lumi.remote.b28ac1" }
}

local configuration = {
    {
      cluster = MULTISTATE_INPUT_CLUSTER_ID,
      attribute = PRESENT_ATTRIBUTE_ID,
      minimum_interval = 3,
      maximum_interval = 7200,
      data_type = data_types.Uint16,
      reportable_change = 1
    },
    {
      cluster = PowerConfiguration.ID,
      attribute = PowerConfiguration.attributes.BatteryVoltage.ID,
      minimum_interval = 30,
      maximum_interval = 3600,
      data_type = PowerConfiguration.attributes.BatteryVoltage.base_type,
      reportable_change = 1
    }
}

local function present_value_attr_handler(driver, device, value, zb_rx)
  local src_endpoint = zb_rx.address_header.src_endpoint.value
  local event_map = { [1] = "pushed", [2] = "double", [0] = "held" }
  local event_value = event_map[value.value]
  if not event_value then return end
  device:emit_component_event(device.profile.components.main, capabilities.button.button[event_value]({ state_change = true }))
  if device:get_model() == "lumi.remote.b28ac1" and src_endpoint == 1 then
    device:emit_component_event(device.profile.components.button1, capabilities.button.button[event_value]({ state_change = true }))
  elseif src_endpoint == 2 then
    device:emit_component_event(device.profile.components.button2, capabilities.button.button[event_value]({ state_change = true }))
  end
end

local is_aqara_products = function(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.6, 3.0)(driver, device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
end

local function added_handler(self, device)
  local config = supported_values.get_device_parameters(device)
  for _, component in pairs(device.profile.components) do
    local number_of_buttons = component.id == "main" and config.NUMBER_OF_BUTTONS or 1
    if config ~= nil then
      device:emit_component_event(component, capabilities.button.supportedButtonValues(config.SUPPORTED_BUTTON_VALUES), {visibility = { displayed = false }})
    else
      device:emit_component_event(component, capabilities.button.supportedButtonValues({"pushed", "held", "double"}, {visibility = { displayed = false }}))
    end
    device:emit_component_event(component, capabilities.button.numberOfButtons({value = number_of_buttons}))
  end
  device:emit_event(capabilities.button.button.pushed({state_change = false}))
  device:emit_event(capabilities.battery.battery(100))
end

local function do_configure(driver, device)
  device:configure()
  if device:get_model() == "lumi.remote.acn003" then
    device:send(cluster_base.write_manufacturer_specific_attribute(device,
      PRIVATE_CLUSTER_ID, MULTISTATE_INPUT_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 2))
  else
    device:send(cluster_base.write_manufacturer_specific_attribute(device,
      PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1))
    device:send(cluster_base.write_manufacturer_specific_attribute(device,
      PRIVATE_CLUSTER_ID, MULTISTATE_INPUT_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 2))
  end
end

local aqara_wireless_switch_handler = {
  NAME = "Aqara Wireless Switch Handler",
  lifecycle_handlers = {
    init = device_init,
    added = added_handler,
    doConfigure = do_configure
  },
  zigbee_handlers = {
    attr = {
      [MULTISTATE_INPUT_CLUSTER_ID] = {
        [PRESENT_ATTRIBUTE_ID] = present_value_attr_handler
      }
    }
  },
  can_handle = is_aqara_products
}

return aqara_wireless_switch_handler
