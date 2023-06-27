local capabilities = require "st.capabilities"

local THIRDREALITY_MOTION_CLUSTER = 0xFC00
local ATTR_TR = 0x0002
local MOTION_DETECT = 0x0001
local MOTION_NO_DETECT = 0x0000

local function motion_sensor_attr_handler(driver, device, value, zb_rx)
    if value.value == MOTION_DETECT then
      device:emit_event(capabilities.motionSensor.motion.active())
    end
    if value.value == MOTION_NO_DETECT then
      device:emit_event(capabilities.motionSensor.motion.inactive())
    end
  end

local thirdreality_device_handler = {
  NAME = "ThirdReality Multi-Function Night Light",
  zigbee_handlers = {
    attr = {
      [THIRDREALITY_MOTION_CLUSTER] = {
        [ATTR_TR] = motion_sensor_attr_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Third Reality, Inc" and device:get_model() == "3RSNL02043Z"
  end
}

return thirdreality_device_handler
