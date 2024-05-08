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
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local utils = require "st.utils"
local device_management = require "st.zigbee.device_management"

local multi_utils = {}

local CUSTOM_ACCELERATION_CLUSTER = 0xFC02
multi_utils.CUSTOM_ACCELERATION_CLUSTER = CUSTOM_ACCELERATION_CLUSTER
local MOTION_THRESHOLD_MULTIPLIER_ATTR = 0x0000
multi_utils.MOTION_THRESHOLD_MULTIPLIER_ATTR = MOTION_THRESHOLD_MULTIPLIER_ATTR
local MOTION_THRESHOLD_ATTR = 0x0002
multi_utils.MOTION_THRESHOLD_ATTR = MOTION_THRESHOLD_ATTR
local ACCELERATION_ATTR = 0x0010
multi_utils.ACCELERATION_ATTR = ACCELERATION_ATTR
local AXIS_X_ATTR = 0x0012
multi_utils.AXIS_X_ATTR = AXIS_X_ATTR
local AXIS_Y_ATTR = 0x0013
multi_utils.AXIS_Y_ATTR = AXIS_Y_ATTR
local AXIS_Z_ATTR = 0x0014
multi_utils.AXIS_Z_ATTR = AXIS_Z_ATTR

local acceleration_config_base = {
  attribute = ACCELERATION_ATTR,
  minimum_interval = 10,
  maximum_interval = 3600,
  data_type = data_types.Bitmap8.ID,
  reportable_change = 1
}
multi_utils.acceleration_config_base = acceleration_config_base

local axis_config_base = {
  minimum_interval = 1,
  maximum_interval = 3600,
  data_type = data_types.Int16.ID,
  reportable_change = 1
}

local axis_x_config_base = utils.deep_copy(axis_config_base)
axis_x_config_base.attribute = AXIS_X_ATTR
multi_utils.axis_x_config_base = axis_x_config_base
local axis_y_config_base = utils.deep_copy(axis_config_base)
axis_y_config_base.attribute = AXIS_Y_ATTR
multi_utils.axis_y_config_base = axis_y_config_base
local axis_z_config_base = utils.deep_copy(axis_config_base)
axis_z_config_base.attribute = AXIS_Z_ATTR
multi_utils.axis_z_config_base = axis_z_config_base

local handle_garage_event = function(device, value)
  local event
  if value > 900 then
    event = capabilities.contactSensor.contact.closed()
  elseif value < 100 then
    event = capabilities.contactSensor.contact.open()
  end
  if event ~= nil then
    device:emit_event(event)
  end
end

multi_utils.handle_three_axis_report = function(device, x, y, z)
  if x ~= nil and y ~= nil and z ~= nil then
    device:emit_event(capabilities.threeAxis.threeAxis({value = {x, y, z}}))
  end
  if z ~= nil and device.preferences["certifiedpreferences.garageSensor"] then
    handle_garage_event(device, math.abs(z))
  end
end

multi_utils.handle_acceleration_report = function(device, value)
  local event
  if value == 0x01 then
    event = capabilities.accelerationSensor.acceleration.active()
  else
    event = capabilities.accelerationSensor.acceleration.inactive()
  end
  if event ~= nil then
    device:emit_event(event)
  end
end

local custom_read_attribute = function(device, attribute, mfg_code)
  local message = cluster_base.read_attribute(device, data_types.ClusterId(CUSTOM_ACCELERATION_CLUSTER), attribute)
  if mfg_code ~= nil then
    message.body.zcl_header.frame_ctrl:set_mfg_specific()
    message.body.zcl_header.mfg_code = data_types.validate_or_build_type(mfg_code, data_types.Uint16, "mfg_code")
  end
  return message
end
multi_utils.custom_read_attribute = custom_read_attribute

local custom_write_attribute = function(device, attribute, data_type, value, mfg_code)
  local data = data_types.validate_or_build_type(value, data_type)
  local message = cluster_base.write_attribute(device, data_types.ClusterId(CUSTOM_ACCELERATION_CLUSTER), attribute, data)
  if mfg_code ~= nil then
    message.body.zcl_header.frame_ctrl:set_mfg_specific()
    message.body.zcl_header.mfg_code = data_types.validate_or_build_type(mfg_code, data_types.Uint16, "mfg_code")
  end
  return message
end
multi_utils.custom_write_attribute = custom_write_attribute

local custom_configure_reporting = function(device, config, mfg_code)
  local message = cluster_base.configure_reporting(device, data_types.ClusterId(CUSTOM_ACCELERATION_CLUSTER), config.attribute, config.data_type, config.minimum_interval, config.maximum_interval, config.reportable_change)
  if mfg_code ~= nil then
    message.body.zcl_header.frame_ctrl:set_mfg_specific()
    message.body.zcl_header.mfg_code = data_types.validate_or_build_type(mfg_code, data_types.Uint16, "mfg_code")
  end
  return message
end
multi_utils.custom_configure_reporting = custom_configure_reporting

multi_utils.send_common_configuration = function(driver, device, mfg_code)
  device:send(device_management.build_bind_request(device, CUSTOM_ACCELERATION_CLUSTER, driver.environment_info.hub_zigbee_eui))
  device:send(custom_configure_reporting(device, acceleration_config_base, mfg_code))
  device:send(custom_configure_reporting(device, axis_x_config_base, mfg_code))
  device:send(custom_configure_reporting(device, axis_y_config_base, mfg_code))
  device:send(custom_configure_reporting(device, axis_z_config_base, mfg_code))
end


multi_utils.convert_to_signedInt16 = function(byte1, byte2)
  local finalValue
  local swapped = (byte2 << 8) | byte1
  local sign_mask = 0x8000
  local int16mask = 0xFFFF
  local isNegative = (swapped & sign_mask) >> 15

  if(isNegative == 1) then
    local negation_plus_one = ~swapped + 1
    local int16value = negation_plus_one & int16mask
    finalValue = int16value * (-1)
  else
    finalValue = swapped
  end
  return finalValue
end


return multi_utils