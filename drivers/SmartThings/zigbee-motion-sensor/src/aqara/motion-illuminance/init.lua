local capabilities = require "st.capabilities"
local zcl_commands = require "st.zigbee.zcl.global_commands"
local aqara_utils = require "aqara/aqara_utils"

local MOTION_ILLUMINANCE_ATTRIBUTE_ID = 0x0112
local MOTION_DETECTED_UINT32 = 65536

local function added_handler(self, device)
  device:emit_event(capabilities.motionSensor.motion.inactive())
  device:emit_event(capabilities.illuminanceMeasurement.illuminance(0))
  aqara_utils.emit_default_detection_frequency_event(device)
  device:emit_event(capabilities.battery.battery(100))

  aqara_utils.enable_custom_cluster_attribute(device)
end

local function detection_frequency_capability_handler(driver, device, command)
  aqara_utils.detection_frequency_capability_handler(driver, device, command)
end

local function write_attr_res_handler(driver, device, zb_rx)
  aqara_utils.detection_frequency_res_handler(device)
end

local function motion_illuminance_attr_handler(driver, device, value, zb_rx)
  -- The low 16 bits for Illuminance
  -- The high 16 bits for Motion Detection
  local raw_value = value.value
  if raw_value >= MOTION_DETECTED_UINT32 then
    aqara_utils.motion_detected(device)
  end

  local lux = raw_value - MOTION_DETECTED_UINT32
  device:emit_event(capabilities.illuminanceMeasurement.illuminance(lux))
end

local aqara_motion_illuminance_handler = {
  NAME = "Aqara Motion Illuminance Handler",
  lifecycle_handlers = {
    added = added_handler
  },
  capability_handlers = {
    [aqara_utils.detectionFrequencyId] = {
      [aqara_utils.detectionFrequencyCommand] = detection_frequency_capability_handler,
    }
  },
  zigbee_handlers = {
    global = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [zcl_commands.WriteAttributeResponse.ID] = write_attr_res_handler
      }
    },
    attr = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [MOTION_ILLUMINANCE_ATTRIBUTE_ID] = motion_illuminance_attr_handler,
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "lumi.motion.agl02"
  end
}

return aqara_motion_illuminance_handler
