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
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"
local capabilities = require "st.capabilities"

local sensitivityAdjustment = capabilities["stse.sensitivityAdjustment"]
local sensitivityAdjustmentCommandName = "setSensitivityAdjustment"
local selfCheck = capabilities["stse.selfCheck"]
local startSelfCheckCommandName  = "startSelfCheck"
local lifeTimeReport = capabilities["stse.lifeTimeReport"]

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local PRIVATE_SENSITIVITY_ADJUSTMENT_ATTRIBUTE_ID = 0x010C
local PRIVATE_MUTE_ATTRIBUTE_ID = 0x0126
local PRIVATE_SELF_CHECK_ATTRIBUTE_ID = 0x0127
local PRIVATE_LIFE_TIME_ATTRIBUTE_ID = 0x0128
local PRIVATE_GAS_ZONE_STATUS_ATTRIBUTE_ID = 0x013A


local FINGERPRINTS = {
    { mfr = "LUMI", model = "lumi.sensor_gas.acn02" }
}


local CONFIGURATIONS = {
  {
    cluster = PRIVATE_CLUSTER_ID,
    attribute = PRIVATE_GAS_ZONE_STATUS_ATTRIBUTE_ID,
    minimum_interval = 1,
    maximum_interval = 3600,
    data_type = data_types.Uint16,
    reportable_change = 1
  }
}

local function gas_zone_status_handler(driver, device, value, zb_rx)
  if value.value == 1 then
    device:emit_event(capabilities.gasDetector.gas.detected())
  elseif value.value == 0 then
    device:emit_event(capabilities.gasDetector.gas.clear())
  end
end

local function buzzer_status_handler(driver, device, value, zb_rx)
  if value.value == 1 then
    device:emit_event(capabilities.audioMute.mute.muted())
  elseif value.value == 0 then
    device:emit_event(capabilities.audioMute.mute.unmuted())
  end
end

local function lifetime_status_handler(driver, device, value, zb_rx)
  if value.value == 1 then
    device:emit_event(lifeTimeReport.lifeTimeState.endOfLife())
  elseif value.value == 0 then
    device:emit_event(lifeTimeReport.lifeTimeState.normal())
  end
end

local function selfcheck_status_handler(driver, device, value, zb_rx)
  if value.value == 0 then
    device:emit_event(selfCheck.selfCheckState.idle())
  elseif value.value == 1 then
    device:emit_event(selfCheck.selfCheckState.selfCheckCompleted())
  end
end

local function sensitivity_adjustment_handler(driver, device, value, zb_rx)
  if value.value == 0x01 then
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Low())
  elseif value.value == 0x02 then
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.High())
  end
end

local function mute_handler(driver, device, cmd)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_MUTE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1))
end

local function unmute_handler(driver, device, cmd)
  -- device:send(cluster_base.write_manufacturer_specific_attribute(device,
  --   PRIVATE_CLUSTER_ID, PRIVATE_MUTE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0))
  device:emit_event(capabilities.audioMute.mute.muted())
end

local function sensitivity_adjustment_capability_handler(driver, device, command)
  local sensitivity = command.args.sensitivity
  local pre_sensitivity_value = device:get_latest_state("main", sensitivityAdjustment.ID, sensitivityAdjustment.sensitivityAdjustment.NAME)

  if pre_sensitivity_value ~= sensitivity then
    if sensitivity == 'High' then
      device:send(cluster_base.write_manufacturer_specific_attribute(device,
        PRIVATE_CLUSTER_ID, PRIVATE_SENSITIVITY_ADJUSTMENT_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x02))
    elseif sensitivity == 'Low' then
      device:send(cluster_base.write_manufacturer_specific_attribute(device,
        PRIVATE_CLUSTER_ID, PRIVATE_SENSITIVITY_ADJUSTMENT_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x01))
    end
  else
    if sensitivity == 'High' then
      device:emit_event(sensitivityAdjustment.sensitivityAdjustment.High())
    elseif sensitivity == 'Low' then
      device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Low())
    end
  end
end

local function self_check_attr_handler(self, device, zone_status, zb_rx)
  device:emit_event(selfCheck.selfCheckState.selfChecking())
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_SELF_CHECK_ATTRIBUTE_ID, MFG_CODE, data_types.Boolean, true))
end

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function device_init(driver, device)
  if CONFIGURATIONS ~= nil then
    for _, attribute in ipairs(CONFIGURATIONS) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
end

local function device_added(driver, device)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x01))
  device:emit_event(capabilities.gasDetector.gas.clear())
  device:emit_event(capabilities.audioMute.mute.unmuted())
  device:emit_event(sensitivityAdjustment.sensitivityAdjustment.High())
  device:emit_event(selfCheck.selfCheckState.idle())
  device:emit_event(lifeTimeReport.lifeTimeState.normal())
end

local aqara_gas_detector_handler = {
  NAME = "Aqara Gas Detector Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  zigbee_handlers = {
    attr = {
      [PRIVATE_CLUSTER_ID] = {
        [PRIVATE_GAS_ZONE_STATUS_ATTRIBUTE_ID] = gas_zone_status_handler,
        [PRIVATE_MUTE_ATTRIBUTE_ID] = buzzer_status_handler,
        [PRIVATE_LIFE_TIME_ATTRIBUTE_ID] = lifetime_status_handler,
        [PRIVATE_SELF_CHECK_ATTRIBUTE_ID] = selfcheck_status_handler,
        [PRIVATE_SENSITIVITY_ADJUSTMENT_ATTRIBUTE_ID] = sensitivity_adjustment_handler
      },
    }
  },
  capability_handlers = {
    [capabilities.audioMute.ID] = {
      [capabilities.audioMute.commands.mute.NAME] = mute_handler,
      [capabilities.audioMute.commands.unmute.NAME] = unmute_handler
    },
    [sensitivityAdjustment.ID] = {
      [sensitivityAdjustmentCommandName] = sensitivity_adjustment_capability_handler
    },
    [selfCheck.ID] = {
      [startSelfCheckCommandName] = self_check_attr_handler
    },
  },
  can_handle = is_aqara_products
}

return aqara_gas_detector_handler

