-- Copyright 2024 Inovelli
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

local st_device = require "st.device"
local capabilities = require "st.capabilities"
local log = require "log"
local cluster_base = require "st.zigbee.cluster_base"
local utils = require "st.utils"

local function can_handle_child_notification(opts, driver, device, ...)
    if device.network_type == st_device.NETWORK_TYPE_CHILD then
      return true
    end
  return false
end

local function huePercentToValue(value)
  if value <= 2 then
    return 0
  elseif value >= 98 then
    return 255
  else
    return utils.round(value / 100 * 255)
  end
end

local function getNotificationValue(device, value)
  local notificationValue = 0
  local level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or 100
  local color = utils.round(device:get_latest_state("main", capabilities.colorControl.ID, capabilities.colorControl.hue.NAME) or 100)
  local effect = device:get_parent_device().preferences.notificationType or 1
  notificationValue = notificationValue + (effect*16777216)
  notificationValue = notificationValue + (huePercentToValue(value or color)*65536)
  notificationValue = notificationValue + (level*256)
  notificationValue = notificationValue + (255*1)
  return notificationValue
end

local function on_handler(driver, device, command)
  log.info("child-notification - on_handler")
  device:emit_event(capabilities.switch.switch("on"))
  local dev = device:get_parent_device()
  local send_configuration = function()
    dev:send(cluster_base.build_manufacturer_specific_command(
          dev,
          0xfc31,
          0x01,
          0x122f,
          utils.serialize_int(getNotificationValue(device),4,false,false)))
  end
  device.thread:call_with_delay(1,send_configuration)
end

local function off_handler(driver, device, command)
  log.info("child-notification - off_handler")
  device:emit_event(capabilities.switch.switch("off"))
  local dev = device:get_parent_device()
  local send_configuration = function()
    dev:send(cluster_base.build_manufacturer_specific_command(
          dev,
          0xfc31,
          0x01,
          0x122f,
          utils.serialize_int(0,4,false,false)))
  end
  device.thread:call_with_delay(1,send_configuration)
end

local function switch_level_handler(driver, device, command)
  log.info("child-notification - switch_level_handler")
  device:emit_event(capabilities.switchLevel.level(command.args.level))
  device:emit_event(capabilities.switch.switch(command.args.level ~= 0 and "on" or "off"))
  local dev = device:get_parent_device()
  local send_configuration = function()
    dev:send(cluster_base.build_manufacturer_specific_command(
          dev,
          0xfc31,
          0x01,
          0x122f,
          utils.serialize_int(getNotificationValue(device),4,false,false)))
  end
  device.thread:call_with_delay(1,send_configuration)
end

local function set_color_temperature(driver, device, command)
  log.info("child-notification - set_color_temperature")
  device:emit_event(capabilities.colorControl.hue(100))
  device:emit_event(capabilities.colorTemperature.colorTemperature(command.args.temperature))
  local dev = device:get_parent_device()
  local send_configuration = function()
    dev:send(cluster_base.build_manufacturer_specific_command(
          dev,
          0xfc31,
          0x01,
          0x122f,
          utils.serialize_int(getNotificationValue(device, 100),4,false,false)))
  end
  device.thread:call_with_delay(1,send_configuration)
end

local function set_color(driver, device, command)
  log.info("child-notification - set_color")
  device:emit_event(capabilities.colorControl.hue(command.args.color.hue))
  device:emit_event(capabilities.colorControl.saturation(command.args.color.saturation))
  local dev = device:get_parent_device()
  local send_configuration = function()
    dev:send(cluster_base.build_manufacturer_specific_command(
          dev,
          0xfc31,
          0x01,
          0x122f,
          utils.serialize_int(getNotificationValue(device),4,false,false)))
  end
  device.thread:call_with_delay(1,send_configuration)
end

local device_init = function(self, device)
  log.info("child-notification - device_init")
end

local do_configure = function(self, device)
  log.info("child-notification - do_configure")
end

local function added(driver, device) 
  log.info("child-notification - added")
  device:emit_event(capabilities.colorControl.hue(1))
  device:emit_event(capabilities.colorControl.saturation(1))
  device:emit_event(capabilities.colorTemperature.colorTemperature(6500))
  device:emit_event(capabilities.switchLevel.level(100))
  device:emit_event(capabilities.switch.switch("off"))
end

local function info_changed(driver, device, event, args)
  log.info("child-notification - info_changed")
end

local child_notification = {
  NAME = "Child Notification",
  lifecycle_handlers = {
    init = device_init,
    doConfigure = do_configure,
    added = added,
    infoChanged = info_changed
  },
  zigbee_handlers = {
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = on_handler,
      [capabilities.switch.commands.off.NAME] = off_handler,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_handler
    },
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = set_color
    },
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temperature
    }
  },
  can_handle = can_handle_child_notification,
}

return child_notification