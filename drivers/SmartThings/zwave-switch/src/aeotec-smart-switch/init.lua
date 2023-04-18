-- Copyright 2023 SmartThings
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
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version=1 })

local AEOTEC_SWITCH_6 = {
  mfr = 0x0086,
  prodId = 0x0060
}

local function can_handle(opts, driver, device, ...)
  return device:id_match(AEOTEC_SWITCH_6.mfr, nil, AEOTEC_SWITCH_6.prodId)
end

-- Despite the NIF indicating that this device supports the Switch Multilevel
-- command class, the device will not respond to multilevel commands
local function on_off_factory(onOff)
  return function(driver, device, cmd)
    device:send(Basic:Set({value=onOff}))
    device.thread:call_with_delay(3, function() device:send(SwitchBinary:Get({})) end)
  end
end

local aeotec_smart_switch = {
  NAME = "Aeotec Smart Switch 6",
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = on_off_factory(0xFF),
      [capabilities.switch.commands.off.NAME] = on_off_factory(0x00)
    }
  },
  can_handle = can_handle
}

return aeotec_smart_switch
