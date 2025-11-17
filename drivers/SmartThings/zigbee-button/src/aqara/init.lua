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
local button_utils = require "button_utils"


local PowerConfiguration = clusters.PowerConfiguration
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID_T1 = 0x0009
local PRIVATE_ATTRIBUTE_ID_E1 = 0x0125
local MFG_CODE = 0x115F

local MULTISTATE_INPUT_CLUSTER_ID = 0x0012
local PRESENT_ATTRIBUTE_ID = 0x0055

local COMP_LIST = { "button1", "button2", "all" }
local FINGERPRINTS = {
  ["lumi.remote.b1acn02"] = { mfr = "LUMI", btn_cnt = 1 },
  ["lumi.remote.acn003"] = { mfr = "LUMI", btn_cnt = 1 },
  ["lumi.remote.b186acn03"] = { mfr = "LUMI", btn_cnt = 1 },
  ["lumi.remote.b286acn03"] = { mfr = "LUMI", btn_cnt = 3 }
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
  if value.value < 0xFF then
    local end_point = zb_rx.address_header.src_endpoint.value
    local btn_evt_cnt = FINGERPRINTS[device:get_model()].btn_cnt or 1
    local evt = capabilities.button.button.held({ state_change = true })
    if value.value == 1 then
      evt = capabilities.button.button.pushed({ state_change = true })
    elseif value.value == 2 then
      evt = capabilities.button.button.double({ state_change = true })
    end
    device:emit_event(evt)
    if btn_evt_cnt > 1 then
      device:emit_component_event(device.profile.components[COMP_LIST[end_point]], evt)
    end
  end
end
local function battery_level_handler(driver, device, value, zb_rx)
  local voltage = value.value
  local batteryLevel = "normal"
  if voltage <= 25 then
    batteryLevel = "critical"
  elseif voltage < 28 then
    batteryLevel = "warning"
  end
  device:emit_event(capabilities.batteryLevel.battery(batteryLevel))
end

local is_aqara_products = function(opts, driver, device)
  local isAqaraProducts = false
  if FINGERPRINTS[device:get_model()] and FINGERPRINTS[device:get_model()].mfr == device:get_manufacturer() then
    isAqaraProducts = true
  end
  return isAqaraProducts
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.6, 3.0)(driver, device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
    end
  end
end

local function added_handler(self, device)
  local btn_evt_cnt = FINGERPRINTS[device:get_model()].btn_cnt or 1

  device:emit_event(capabilities.button.supportedButtonValues({ "pushed", "held", "double" },
    { visibility = { displayed = false } }))
  device:emit_event(capabilities.button.numberOfButtons({ value = 1 }))
  button_utils.emit_event_if_latest_state_missing(device, "main", capabilities.button, capabilities.button.button.NAME,
    capabilities.button.button.pushed({ state_change = false }))
  device:emit_event(capabilities.batteryLevel.battery.normal())
  device:emit_event(capabilities.batteryLevel.type("CR2032"))
  device:emit_event(capabilities.batteryLevel.quantity(1))

  if btn_evt_cnt > 1 then
    for i = 1, btn_evt_cnt do
      device:emit_component_event(device.profile.components[COMP_LIST[i]],
        capabilities.button.supportedButtonValues({ "pushed", "held", "double" },
          { visibility = { displayed = false } }))
      device:emit_component_event(device.profile.components[COMP_LIST[i]],
        capabilities.button.numberOfButtons({ value = 1 }))
      device:emit_component_event(device.profile.components[COMP_LIST[i]],
        capabilities.button.button.pushed({ state_change = false }))
      button_utils.emit_event_if_latest_state_missing(device, COMP_LIST[i], capabilities.button,
        capabilities.button.button.NAME, capabilities.button.button.pushed({ state_change = false }))
    end
  end
end

local function do_configure(driver, device)
  local ATTR_ID = PRIVATE_ATTRIBUTE_ID_T1
  local cmd_value = 1

  device:configure()
  if device:get_model() == "lumi.remote.acn003" then
    ATTR_ID = PRIVATE_ATTRIBUTE_ID_E1
    cmd_value = 2
  end
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, ATTR_ID, MFG_CODE, data_types.Uint8, cmd_value))
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
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_level_handler
      }
    }
  },
  can_handle = is_aqara_products
}

return aqara_wireless_switch_handler
