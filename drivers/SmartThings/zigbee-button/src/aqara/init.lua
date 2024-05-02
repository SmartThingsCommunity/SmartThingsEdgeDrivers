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

local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"


local PowerConfiguration = clusters.PowerConfiguration
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID_T1 = 0x0009
local PRIVATE_ATTRIBUTE_ID_E1 = 0x0125
local MFG_CODE = 0x115F

local MULTISTATE_INPUT_CLUSTER_ID = 0x0012
local PRESENT_ATTRIBUTE_ID = 0x0055

local FINGERPRINTS = {
  { mfr = "LUMI", model = "lumi.remote.b1acn02" },
  { mfr = "LUMI", model = "lumi.remote.acn003" }
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
    if value.value == 1 then
        device:emit_event(capabilities.button.button.pushed({state_change = true}))
    elseif value.value == 2 then
        device:emit_event(capabilities.button.button.double({state_change = true}))
    elseif value.value == 0 then
        device:emit_event(capabilities.button.button.held({state_change = true}))
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
    device:emit_event(capabilities.button.supportedButtonValues({"pushed","held","double"}, {visibility = { displayed = false }}))
    device:emit_event(capabilities.button.numberOfButtons({value = 1}))
    device:emit_event(capabilities.button.button.pushed({state_change = false}))
    device:emit_event(capabilities.battery.battery(100))
end

local function do_configure(driver, device)
  device:configure()
  if device:get_model() == "lumi.remote.b1acn02" then
    device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID_T1, MFG_CODE, data_types.Uint8, 1))
  elseif device:get_model() == "lumi.remote.acn003" then
    device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID_E1, MFG_CODE, data_types.Uint8, 2))
  end
  -- when the wireless switch T1 accesses the network, the gateway sends
  -- private attribute 0009 to make the device no longer distinguish
  -- between the standard gateway and the aqara gateway.
  -- When wireless switch E1 is connected to the network, the gateway sends
  -- private attribute 0125 to enable the device to send double-click and long-press packets.
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
