-- Copyright 2022 SmartThings
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

--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({ version=2 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version=3 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 2 })

local devices = {
  AEOTEC_MULTISENSOR_GEN5 = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = {0x0002, 0x0102, 0x0202},
      product_ids = 0x004A
    },
    CONFIGURATION = {
      -- send temperature, humidity, and illuminance every 8 minutes
      {parameter_number = 101, configuration_value = 128|64|32, size = 4},
      {parameter_number = 111, configuration_value = 8*60, size = 4},
      -- send battery every 20 hours
      {parameter_number = 102, configuration_value = 1, size = 4},
      {parameter_number = 112, configuration_value = 20*60*60, size = 4},
      -- send no-motion report 60 seconds after motion stops
      {parameter_number = 3, configuration_value = 60, size = 2},
      -- send binary sensor report instead of basic set for motion
      {parameter_number = 5, configuration_value = 2, size = 1},
      -- turn on the Multisensor Gen5 PIR sensor
      {parameter_number = 4, configuration_value = 1, size = 1}
    },
    NOTIFICATION = {
      -- disable notification-style motion events
      {notification_type = 7, notification_status = 0}
    }
  },
  AEOTEC_MULTISENSOR_6 = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = {0x0002, 0x0102, 0x0202},
      product_ids = 0x0064
    },
    CONFIGURATION = {
      -- automatic report flags
      -- param 101 & 102 [4 bytes] 128: light sensor, 64 humidity, 32 temperature sensor, 15 ultraviolet sensor, 1 battery sensor
      -- set value  241 (default for 101) to get all reports. Set value 0 for no reports (default for 102-103)
      -- association group 1
      {parameter_number = 101, configuration_value = 240, size = 4},
      -- association group 2
      {parameter_number = 102, configuration_value = 1, size = 4},
      -- no-motion report 20 seconds after motion stops
      {parameter_number = 3, configuration_value = 20, size = 2},
      --  motionSensitivity - maximum
      {parameter_number = 4, configuration_value = 5, size = 1},
      -- parameters 111-113: report interval for association group 1-3
      -- association group 1 - set in preferences, default 8 mins
      {parameter_number = 111, configuration_value = 480, size = 4},
      -- report battery every 6 hours
      {parameter_number = 112, configuration_value = 21600, size = 4},
      -- report automatically ONLY on threshold change (0 = disable, 1 = enable)
      {parameter_number = 40, configuration_value = 1, size = 1}
    },
    ASSOCIATION = {
      {grouping_identifier = 1}
    }
  },
  AEOTEC_MULTISENSOR_7 = {
    MATCHING_MATRIX = {
      mfrs = 0x0371,
      product_types = {0x0002, 0x0102, 0x0202},
      product_ids = 0x0018
    },
    CONFIGURATION = {
      -- automatic report flags
      -- param 101 & 102 [4 bytes] 128: light sensor, 64 humidity, 32 temperature sensor, 15 ultraviolet sensor, 1 battery sensor
      -- set value  241 (default for 101) to get all reports. Set value 0 for no reports (default for 102-103)
      -- association group 1
      {parameter_number = 101, configuration_value = -16, size = 1}, -- 2's complement representation of 240
      -- association group 2
      {parameter_number = 102, configuration_value = 1, size = 1},
      -- no-motion report 30 seconds after motion stops
      {parameter_number = 3, configuration_value = 30, size = 2},
      --  motionSensitivity - maximum
      {parameter_number = 4, configuration_value = 11, size = 1},
      -- parameters 111-113: report interval for association group 1-3
      -- association group 1 - set in preferences, default 8 mins
      {parameter_number = 111, configuration_value = 480, size = 2},
      -- report battery every 6 hours
      {parameter_number = 112, configuration_value = 21600, size = 2},
      -- report automatically ONLY on threshold change (0 = disable, 1 = enable)
      {parameter_number = 40, configuration_value = 1, size = 1}
    },
    ASSOCIATION = {
      {grouping_identifier = 1}
    }
  },
  AEON_MULTISENSOR = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = {0x0002, 0x0102, 0x0202},
      product_ids = 0x0005
    },
    CONFIGURATION = {
      -- send binary sensor report instead of basic set for motion
      {parameter_number = 5, configuration_value = 2, size = 1},
      -- send no-motion report 15 seconds after motion stops
      {parameter_number = 3, configuration_value = 15, size = 2},
      -- send all data (temperature, humidity, illuminance & battery) periodically
      {parameter_number = 101, configuration_value = 225, size = 4},
      -- set data reporting period to 5 minutes
      {parameter_number = 111, configuration_value = 300, size = 4},
    }
  },
  EVERSPRING_ILLUMINANCE_SENSOR = {
    MATCHING_MATRIX = {
      mfrs = 0x0060,
      product_types = 0x0007,
      product_ids = 0x0001
    },
    CONFIGURATION = {
      -- Auto report time interval in minutes
      {parameter_number = 5, configuration_value = 20, size = 2},
      -- Auto report lux change threshold
      {parameter_number = 6, configuration_value = 30, size = 2}
    }
  },
  EVERSPRING_SP817 = {
    MATCHING_MATRIX = {
      mfrs = 0x0060,
      product_types = 0x0001,
      product_ids = 0x0006
    },
    CONFIGURATION = {
      {parameter_number = 4, configuration_value = 180, size = 2}
    }
  },
  EVERSPRING_ST814 = {
    MATCHING_MATRIX = {
      mfrs = 0x0060,
      product_types = 0x0006,
      product_ids = 0x0001
    },
    CONFIGURATION = {
      -- Auto report time interval in minutes
      {parameter_number = 6, configuration_value = 20, size = 2},
      -- Auto report temperature change threshold
      {parameter_number = 7, configuration_value = 2, size = 1},
      -- Auto report humidity change threshold
      {parameter_number = 8, configuration_value = 5, size = 1}
    }
  },
  AEOTEC_TRISENSOR = {
    MATCHING_MATRIX = {
        mfrs = 0x0371,
        product_types = {0x0002, 0x0102, 0x0202},
        product_ids = 0x0005
    },
    CONFIGURATION = {
      -- clear time (in seconds) when sensor times out and sends a no motion status
      {parameter_number = 2, configuration_value = 30, size = 2}
    }
  },
  AEOTEC_OPEN_CLOSED_SENSOR = {
    MATCHING_MATRIX = {
      mfrs = 0x0371,
      product_types = {0x0002,0x0102},
      product_ids = 0x00BB,
    },
    CONFIGURATION = {
      {parameter_number = 1, configuration_value = 1, size = 1}
    }
  },
  ENERWAVE_MOTION_SENSOR = {
    MATCHING_MATRIX = {
      mfrs = 0x011A,
      product_types = 0x0601,
      product_ids = 0x0901
    },
    ASSOCIATION = {
      {grouping_identifier = 1}
    }
  },
  AEOTEC_WATER_SENSOR = {
    MATCHING_MATRIX = {
      mfrs = 0x0086,
      product_types = {0x0002, 0x0102, 0x0202},
      product_ids = 0x007A
    },
    ASSOCIATION = {
      {grouping_identifier = 3},
      {grouping_identifier = 4}
    },
    CONFIGURATION = {
      {parameter_number = 0x58, configuration_value = 1, size = 1},
      {parameter_number = 0x59, configuration_value = 1, size = 1},
      {parameter_number = 0x5E, configuration_value = 1, size = 1}
    }
  },
  DOME_LEAK_SENSOR = {
    MATCHING_MATRIX = {
      mfrs = 0x021F,
      product_types = 0x0003,
      product_ids = 0x0085
    },
    WAKE_UP = {
      {seconds = 14400}
    }
  },
  NEO_COOLCAM_WATER_SENSOR = {
    MATCHING_MATRIX = {
      mfrs = 0x0258,
      product_types = 0x0003,
      product_ids = 0x1085
    },
    WAKE_UP = {
      {seconds = 14400}
    }
  },
  LEAK_GOPHER_WATER_SENSOR = {
    MATCHING_MATRIX = {
      mfrs = 0x0173,
      product_types = 0x4C47,
      product_ids = 0x4C44
    },
    WAKE_UP = {
      {seconds = 14400}
    }
  },
  ZOOZ_WATER_LEAK_SENSOR = {
    MATCHING_MATRIX = {
      mfrs = 0x027A,
      product_types = 0x7000,
      product_ids = 0xE002
    },
    WAKE_UP = {
      {seconds = 14400}
    }
  },
  FIBARO_MOTION_SENSOR = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x0800,
      product_ids = {0x1001,0x2001}
    },
    ASSOCIATION = {
      {grouping_identifier = 3}
    },
    CONFIGURATION = {
      {parameter_number = 24, configuration_value = 4, size = 1},
      {parameter_number = 60, configuration_value = 5, size = 1},
    },
    WAKE_UP = {
      {seconds = 7200}
    }
  },
  FIBARO_MOTION_SENSOR_ZW5 = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x0801
    },
    ASSOCIATION = {
      {grouping_identifier = 1}
    },
    CONFIGURATION = {
      {parameter_number = 24, configuration_value = 2, size = 1}
    },
    WAKE_UP = {
      {seconds = 7200}
    }
  },
  FIBARO_FLOOD_SENSOR = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = {0x0000,0x0B00},
      product_ids = nil
    },
    ASSOCIATION = {
      {grouping_identifier = 2},
      {grouping_identifier = 3}
    },
    CONFIGURATION = {
      {parameter_number = 74, configuration_value = 3, size = 1}
    }
  },
  FIBARO_FLOOD_SENSOR_ZW5 = {
    MATCHING_MATRIX = {
      mfrs = 0x010F,
      product_types = 0x0B01,
      product_ids = nil
    },
    ASSOCIATION = {
      {grouping_identifier = 1},
      {grouping_identifier = 3},
      {grouping_identifier = 4}
    },
    CONFIGURATION = {
      {parameter_number = 74, configuration_value = 3, size = 1}
    },
    WAKE_UP = {
      {seconds = 21600}
    }
  },
  FIBARO_OPEN_CLOSE_SENSOR_1 = {
    MATCHING_MATRIX = {
      mfrs = {0x010F,0x0086,0x0109,0x017F},
      product_types = {0x0002,0x0100,0x0102,0x200A,0x0501,0x0701},
      product_ids = {0x0001,0x0004,0x0061,0x1001,0x1002,0x0A02}
    },
    ASSOCIATION = {
      {grouping_identifier = 2},
      {grouping_identifier = 3}
    },
    CONFIGURATION = {
      {parameter_number = 1, configuration_value = 0, size = 2},
      {parameter_number = 2, configuration_value = 1, size = 1},
      {parameter_number = 3, configuration_value = 0, size = 1},
      {parameter_number = 5, configuration_value = 255, size = 2},
      {parameter_number = 7, configuration_value = 255, size = 2},
      {parameter_number = 9, configuration_value = 0, size = 1},
      {parameter_number = 10, configuration_value = 1, size = 1},
      {parameter_number = 12, configuration_value = 4, size = 1},
      {parameter_number = 13, configuration_value = 0, size = 1},
      {parameter_number = 14, configuration_value = 0, size = 1}
    }
  },
  EVERSPRING_ST812 = {
    MATCHING_MATRIX = {
      mfrs = 0x0060,
      product_types = {0x0000, 0x000B},
      product_ids = 0x0001
    },
    ASSOCIATION = {
      {grouping_identifier = 1}
    }
  }
}
local configurations = {}

configurations.initial_configuration = function(driver, device)
  local configuration = configurations.get_device_configuration(device)
  if configuration ~= nil then
    for _, value in ipairs(configuration) do
      device:send(Configuration:Set(value))
    end
  end
  local association = configurations.get_device_association(device)
  if association ~= nil then
    for _, value in ipairs(association) do
      local _node_ids = value.node_ids or {driver.environment_info.hub_zwave_id}
      device:send(Association:Set({grouping_identifier = value.grouping_identifier, node_ids = _node_ids}))
    end
  end
  local notification = configurations.get_device_notification(device)
  if notification ~= nil then
    for _, value in ipairs(notification) do
      device:send(Notification:Set(value))
    end
  end
  local wake_up = configurations.get_device_wake_up(device)
  if wake_up ~= nil then
    for _, value in ipairs(wake_up) do
      local _node_id = value.node_id or driver.environment_info.hub_zwave_id
      device:send(WakeUp:IntervalSet({seconds = value.seconds, node_id = _node_id}))
    end
  end
end

configurations.get_device_configuration = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.CONFIGURATION
    end
  end
  return nil
end

configurations.get_device_association = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.ASSOCIATION
    end
  end
  return nil
end

configurations.get_device_notification = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.NOTIFICATION
    end
  end
  return nil
end

configurations.get_device_wake_up = function(zw_device)
  for _, device in pairs(devices) do
    if zw_device:id_match(
      device.MATCHING_MATRIX.mfrs,
      device.MATCHING_MATRIX.product_types,
      device.MATCHING_MATRIX.product_ids) then
      return device.WAKE_UP
    end
  end
  return nil
end

return configurations
