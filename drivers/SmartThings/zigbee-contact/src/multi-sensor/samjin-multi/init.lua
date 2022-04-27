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

local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"
local device_management = require "st.zigbee.device_management"

local utils = require "st.utils"
local multi_utils = require "multi-sensor/multi_utils"

local SAMJIN_MFG = 0x1241
local ACCELERATION_CONFIG = utils.deep_copy(multi_utils.acceleration_config_base)
ACCELERATION_CONFIG.minimum_interval = 0
local AXIS_X_CONFIG = utils.deep_copy(multi_utils.axis_x_config_base)
AXIS_X_CONFIG.minimum_interval = 0
local AXIS_Y_CONFIG = utils.deep_copy(multi_utils.axis_y_config_base)
AXIS_Y_CONFIG.minimum_interval = 0
local AXIS_Z_CONFIG = utils.deep_copy(multi_utils.axis_z_config_base)
AXIS_Z_CONFIG.minimum_interval = 0

local do_configure = function(self, device)
  device:configure()
  device:send(multi_utils.custom_write_attribute(device, multi_utils.MOTION_THRESHOLD_MULTIPLIER_ATTR, data_types.Uint8, 0x14, SAMJIN_MFG))
  device:send(device_management.build_bind_request(device, multi_utils.CUSTOM_ACCELERATION_CLUSTER, self.environment_info.hub_zigbee_eui))
  device:send(multi_utils.custom_configure_reporting(device, ACCELERATION_CONFIG, SAMJIN_MFG))
  device:send(multi_utils.custom_configure_reporting(device, AXIS_X_CONFIG, SAMJIN_MFG))
  device:send(multi_utils.custom_configure_reporting(device, AXIS_Y_CONFIG, SAMJIN_MFG))
  device:send(multi_utils.custom_configure_reporting(device, AXIS_Z_CONFIG, SAMJIN_MFG))
end

local do_refresh = function(self, device)
  device:refresh()
  device:send(multi_utils.custom_read_attribute(device, multi_utils.ACCELERATION_ATTR, SAMJIN_MFG))
end

local samjin_driver = {
  NAME = "Samjin Multi Sensor",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Samjin"
  end
}

return samjin_driver
