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
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({ version = 2 })
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
--- @type st.zwave.CommandClass.SensorBinary
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })

local MIMOLITE_GARAGE_DOOR_FINGERPRINTS = {
  { manufacturerId = 0x0084, productType = 0x0453, productId = 0x0111 } -- mimolite garage door
}

--- Determine whether the passed device is mimolite garage door
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device proper, else false
local function can_handle_mimolite_garage_door(opts, driver, device, ...)
  for _, fingerprint in ipairs(MIMOLITE_GARAGE_DOOR_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function door_event_helper(device, value)
  device:emit_event(value == 0x00 and capabilities.doorControl.door.closed() or capabilities.doorControl.door.open())
  device:emit_event(value == 0x00 and capabilities.contactSensor.contact.closed() or capabilities.contactSensor.contact.open())
end

local function basic_cmd_handler(self, device, cmd)
  door_event_helper(device, cmd.args.value)
end

local function sensor_binary_report_handler(self, device, cmd)
  door_event_helper(device, cmd.args.sensor_value)
end

local function switch_binary_report_handler(self, device, cmd)
  local event = nil
  if cmd.args.value == 0 then
    if device:get_latest_state("main", capabilities.contactSensor.ID, capabilities.contactSensor.contact.NAME) == "closed" then
      event = capabilities.doorControl.door.opening()
    else
      event = capabilities.doorControl.door.closing()
    end
    device:emit_event(event)
  end
end

local function open(driver, device, command)
  device:send(Basic:Set({ value = 0xFF }))
  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, function(d)
    device:send(Basic:Get({}))
  end)
end

local function close(driver, device, command)
  device:send(Basic:Set({ value = 0x00 }))
  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, function(d)
    device:send(Basic:Get({}))
  end)
end

local function device_added(self, device)
  device:send(Basic:Get({}))
end

local function do_configure(self, device)
  device:send(Configuration:Set({ configuration_value = 25, parameter_number = 11, size = 1 }))
  device:send(Association:Set({grouping_identifier = 3, node_ids = {self.environment_info.hub_zwave_id}}))
end

local mimolite_garage_door = {
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_cmd_handler,
      [Basic.REPORT] = basic_cmd_handler
    },
    [cc.SENSOR_BINARY] = {
      [SensorBinary.REPORT] = sensor_binary_report_handler
    },
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = switch_binary_report_handler
    }
  },
  capability_handlers = {
    [capabilities.doorControl.ID] = {
      [capabilities.doorControl.commands.open.NAME] = open,
      [capabilities.doorControl.commands.close.NAME] = close
    }
  },
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure
  },
  NAME = "mimolite garage door",
  can_handle = can_handle_mimolite_garage_door
}

return mimolite_garage_door
