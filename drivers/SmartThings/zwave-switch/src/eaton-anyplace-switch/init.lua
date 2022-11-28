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
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })

local EATON_ANYPLACE_SWITCH_FINGERPRINTS = {
  { manufacturerId = 0x001A, productType = 0x4243, productId = 0x0000 } -- Eaton Anyplace Switch
}

local function can_handle_eaton_anyplace_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(EATON_ANYPLACE_SWITCH_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function basic_set_handler(self, device, cmd)
  if cmd.args.value == 0xFF then
    device:emit_event(capabilities.switch.switch.on())
  else
    device:emit_event(capabilities.switch.switch.off())
  end
end

local function basic_get_handler(self, device, cmd)
  local is_on = device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME)
  device:send(Basic:Report({value = is_on == "on" and 0xff or 0x00}))
end

local function device_added(driver, device)
  -- device:emit_event(capabilities.switch.switch.off())
end

local function switch_on_handler(driver, device)
  device:emit_event(capabilities.switch.switch.on())
end

local function switch_off_handler(driver, device)
  device:emit_event(capabilities.switch.switch.off())
end

local eaton_anyplace_switch = {
  NAME = "eaton anyplace switch",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler,
      [Basic.GET] = basic_get_handler
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  can_handle = can_handle_eaton_anyplace_switch
}

return eaton_anyplace_switch
