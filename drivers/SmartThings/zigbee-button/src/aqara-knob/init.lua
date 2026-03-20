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
local utils = require "st.utils"

local PowerConfiguration = clusters.PowerConfiguration
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local MULTISTATE_INPUT_CLUSTER_ID = 0x0012
local PRESENT_ATTRIBUTE_ID = 0x0055
local ROTATION_MONITOR_ID = 0x0232

local SENSITIVITY = "stse.knobSensitivity"
local SENSITIVITY_FACTORS = {0.5, 1.0, 2.0}

local AQARA_KNOB = {
  ["lumi.remote.rkba01"] = { mfr = "LUMI", type = "CR2032", quantity = 2 },   -- Aqara Wireless Knob Switch H1
}

local configuration = {
  {
    cluster = PowerConfiguration.ID,
    attribute = PowerConfiguration.attributes.BatteryVoltage.ID,
    minimum_interval = 30,
    maximum_interval = 3600,
    data_type = PowerConfiguration.attributes.BatteryVoltage.base_type,
    reportable_change = 1
  }
}

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.6, 3.0)(driver, device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
    end
  end
end

local function device_added(self, device)
  local model = device:get_model()
  local type = AQARA_KNOB[model].type or "CR2032"
  local quantity = AQARA_KNOB[model].quantity or 1

  device:emit_event(capabilities.button.supportedButtonValues({ "pushed", "held", "double" }, { visibility = { displayed = false } }))
  device:emit_event(capabilities.button.numberOfButtons({ value = 1 }))
  if device:get_latest_state("main", capabilities.button.ID, capabilities.button.button.NAME) == nil then
    device:emit_event(capabilities.button.button.pushed({ state_change = false }))
  end
  device:emit_event(capabilities.batteryLevel.battery.normal())
  device:emit_event(capabilities.batteryLevel.type(type))
  device:emit_event(capabilities.batteryLevel.quantity(quantity))
  device:emit_event(capabilities.knob.rotateAmount({value = 0, unit = "%"}))
  device:emit_event(capabilities.knob.heldRotateAmount({value = 0, unit = "%"}))
end

local function do_configure(driver, device)
  device:configure()
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1))
  device:emit_event(capabilities.knob.supportedAttributes({"rotateAmount", "heldRotateAmount"}, {state_change = true}))
end

local function button_monitor_handler(driver, device, value, zb_rx)
  local val = value.value

  if val == 1 then     -- push
    device:emit_event(capabilities.button.button.pushed({ state_change = true }))
  elseif val == 2 then -- dobule push
    device:emit_event(capabilities.button.button.double({ state_change = true }))
  elseif val == 0 then -- down_hold
    device:emit_event(capabilities.button.button.held({ state_change = true }))
  end
end

local function rotation_monitor_per_handler(driver, device, value, zb_rx)
  local end_point = zb_rx.address_header.src_endpoint.value
  local raw_val = utils.round(value.value)
  local sensitivity = tonumber(device.preferences[SENSITIVITY])
  local factor = SENSITIVITY_FACTORS[sensitivity] or 1.0
  local intermediate_val = raw_val * factor
  local sign = (intermediate_val > 0 and 1) or (intermediate_val < 0 and -1) or 0
  local val = math.floor(math.abs(intermediate_val) + 0.5) * sign
  val = math.max(-100, math.min(100, val))

  if val == 0 then
    return
  elseif end_point == 0x47 then -- normal
    device:emit_event(capabilities.knob.rotateAmount({value = val, unit = "%"}, {state_change = true}))
elseif end_point == 0x48 then -- press
    device:emit_event(capabilities.knob.heldRotateAmount({value = val, unit = "%"}, {state_change = true}))
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

local aqara_knob_switch_handler = {
  NAME = "Aqara Wireless Knob Switch Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure
  },
  zigbee_handlers = {
    attr = {
      [MULTISTATE_INPUT_CLUSTER_ID] = {
        [PRESENT_ATTRIBUTE_ID] = button_monitor_handler
      },
      [PRIVATE_CLUSTER_ID] = {
        [ROTATION_MONITOR_ID] = rotation_monitor_per_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_level_handler
      },
    }
  },

  can_handle = require("aqara-knob.can_handle"),
}

return aqara_knob_switch_handler
