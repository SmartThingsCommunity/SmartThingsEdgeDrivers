local zcl_commands = require "st.zigbee.zcl.global_commands"
local aqara_utils = require "aqara/aqara_utils"

local aqara_motion_handler = {
  capability_handlers = {
    [aqara_utils.detectionFrequencyId] = {
      [aqara_utils.detectionFrequencyCommand] = aqara_utils.detection_frequency_handler,
    }
  },
  zigbee_handlers = {
    global = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [zcl_commands.WriteAttributeResponse.ID] = aqara_utils.write_attr_res_handler
      }
    },
    attr = {
      [aqara_utils.PRIVATE_CLUSTER_ID] = {
        [aqara_utils.FREQUENCY_ATTRIBUTE_ID] = aqara_utils.frequency_attr_handler
      }
    }
  },
  sub_drivers = {
    require("aqara.motion-illuminance"),
    require("aqara.high-precision")
  }
}

return aqara_motion_handler
