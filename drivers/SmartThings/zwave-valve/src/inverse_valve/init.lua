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
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version=2, strict=true })
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1, strict=true })
local valve_defaults = require "st.zwave.defaults.valve"

local function open_handler(driver, device, command)
  valve_defaults.capability_handlers[capabilities.valve.commands.close](driver, device, command)
end

local function close_handler(driver, device, command)
  valve_defaults.capability_handlers[capabilities.valve.commands.open](driver, device, command)
end

local function binary_report_handler(driver, device, cmd)
  local event
  if cmd.args.value == SwitchBinary.value.OFF_DISABLE then
    event = capabilities.valve.valve.open()
  else
    event = capabilities.valve.valve.closed()
  end
  device:emit_event_for_endpoint(cmd.src_channel, event)
end

local inverse_valve = {
  NAME = "Inverse Valve",
  zwave_handlers = {
    [cc.SWITCH_BINARY] = {
      [SwitchBinary.REPORT] = binary_report_handler
    },
    [cc.BASIC] = {
      [Basic.REPORT] = binary_report_handler
    }
  },
  capability_handlers = {
    [capabilities.valve.ID] = {
      [capabilities.valve.commands.open.NAME] = open_handler,
      [capabilities.valve.commands.close.NAME] = close_handler
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device.zwave_manufacturer_id == 0x0084 or device.zwave_manufacturer_id == 0x027A
  end
}

return inverse_valve
