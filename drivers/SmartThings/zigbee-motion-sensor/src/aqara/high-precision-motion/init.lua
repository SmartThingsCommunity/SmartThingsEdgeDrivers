local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local aqara_utils = require "aqara/aqara_utils"
local data_types = require "st.zigbee.data_types"

local OccupancySensing = clusters.OccupancySensing

local sensitivityAdjustment = capabilities["stse.sensitivityAdjustment"]
local sensitivityAdjustmentId = "stse.sensitivityAdjustment"
local sensitivityAdjustmentCommand = "setSensitivityAdjustment"

local MOTION_DETECTED_NUMBER = 1

local SENSITIVITY_ATTRIBUTE_ID = 0x010C

local PREF_SENSITIVITY_KEY = "prefSensitivity"
local PREF_SENSITIVITY_VALUE_HIGH = 3
local PREF_SENSITIVITY_VALUE_MEDIUM = 2
local PREF_SENSITIVITY_VALUE_LOW = 1

local function added_handler(self, device)
  device:emit_event(capabilities.motionSensor.motion.inactive())
  aqara_utils.emit_default_detection_frequency_event(device)
  device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Medium())
  device:emit_event(capabilities.battery.battery(100))

  aqara_utils.enable_custom_cluster_attribute(device)
end

local function send_sensitivity_adjustment_value(device, value)
  aqara_utils.set_pref_changed_field(device, PREF_SENSITIVITY_KEY, value)
  aqara_utils.write_custom_attribute(device, SENSITIVITY_ATTRIBUTE_ID, data_types.Uint8, value)
end

local function emit_sensitivity_adjustment_event(device, sensitivity)
  if sensitivity == PREF_SENSITIVITY_VALUE_HIGH then
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.High())
  elseif sensitivity == PREF_SENSITIVITY_VALUE_MEDIUM then
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Medium())
  elseif sensitivity == PREF_SENSITIVITY_VALUE_LOW then
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Low())
  end
end

local function detection_frequency_capability_handler(driver, device, command)
  aqara_utils.detection_frequency_capability_handler(driver, device, command)
end

local function sensitivity_adjustment_capability_handler(driver, device, command)
  local sensitivity = command.args.sensitivity
  if sensitivity == 'High' then
    send_sensitivity_adjustment_value(device, PREF_SENSITIVITY_VALUE_HIGH)
  elseif sensitivity == 'Medium' then
    send_sensitivity_adjustment_value(device, PREF_SENSITIVITY_VALUE_MEDIUM)
  elseif sensitivity == 'Low' then
    send_sensitivity_adjustment_value(device, PREF_SENSITIVITY_VALUE_LOW)
  end
end

local function sensitivity_adjustment_res_handler(device)
  local key, value = aqara_utils.get_pref_changed_field(device)
  if key == PREF_SENSITIVITY_KEY then
    emit_sensitivity_adjustment_event(device, value)
  end
end

local function write_attr_res_handler(driver, device, zb_rx)
  -- detection frequency
  aqara_utils.detection_frequency_res_handler(device)
  -- sensitivity adjustment
  sensitivity_adjustment_res_handler(device)
end

local function occupancy_attr_handler(driver, device, value, zb_rx)
  if value.value == MOTION_DETECTED_NUMBER then
    aqara_utils.motion_detected(device)
  end
end

local aqara_high_precision_motion_handler = {
  NAME = "Aqara High Precision Motion Handler",
  lifecycle_handlers = {
    added = added_handler
  },
  capability_handlers = {
    [aqara_utils.detectionFrequencyId] = {
      [aqara_utils.detectionFrequencyCommand] = detection_frequency_capability_handler,
    },
    [sensitivityAdjustmentId] = {
      [sensitivityAdjustmentCommand] = sensitivity_adjustment_capability_handler,
    }
  },
  zigbee_handlers = {
    global = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [zcl_commands.WriteAttributeResponse.ID] = write_attr_res_handler
      }
    },
    attr = {
      [OccupancySensing.ID] = {
        [OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler
      },
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "lumi.motion.agl04"
  end
}

return aqara_high_precision_motion_handler
