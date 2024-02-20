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

local FINGERPRINTS = {
  {mfr = 0x0086, prodId = 0x0060},
  {mfr = 0x0371, prodId = 0x00AF},
  {mfr = 0x0371, prodId = 0x0017}
}

local function can_handle(opts, driver, device, ...)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, nil, fingerprint.prodId) then
      local subdriver = require("aeotec-smart-switch")
      return true, subdriver
    end
  end
  return false
end

-- Despite the NIF indicating that this device supports the Switch Multilevel
-- command class, the device will not respond to multilevel commands. Note that
-- this applies at least to the Aeotec Smart Switch 6 and 7
local function on_off_factory(onOff)
  return function(driver, device, cmd)
    device:send(Basic:Set({value=onOff}))
    device.thread:call_with_delay(3, function() device:send(SwitchBinary:Get({})) end)
  end
end

local aeotec_smart_switch = {
  NAME = "Aeotec Smart Switch",
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = on_off_factory(0xFF),
      [capabilities.switch.commands.off.NAME] = on_off_factory(0x00)
    }
  },
  can_handle = can_handle
}

return aeotec_smart_switch
