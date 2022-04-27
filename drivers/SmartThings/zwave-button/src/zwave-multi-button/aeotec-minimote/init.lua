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
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })

local ZWAVE_AEOTEC_MINIMOTE_FINGERPRINTS = {
  {mfr = 0x0086, prod = 0x0001, model = 0x0003} -- Aeotec Mimimote
}

local function can_handle_aeotec_minimote(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZWAVE_AEOTEC_MINIMOTE_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local function basic_set_handler(self, device, cmd)
  local button = cmd.args.value // 40 + 1
  local event = (button * 40 - cmd.args.value) <= 20 and capabilities.button.button.held or capabilities.button.button.pushed
  device:emit_event_for_endpoint(button, event({state_change = true}))
  device:emit_event(event({state_change = true}))
end

local do_configure = function(self, device)
  device:refresh()
  for buttons = 1,4 do
    device:send(Configuration:Set({parameter_number = 240 + buttons , size = 1, configuration_value = 1}))
    device:send(Configuration:Set({parameter_number = (buttons - 1) * 40, size = 4, configuration_value = 1 << 24 | ((buttons - 1) * 40 + 1) << 16}))
    device:send(Configuration:Set({parameter_number = (buttons - 1) * 40 + 20, size = 4, configuration_value = 1 << 24 | ((buttons - 1) * 40 + 21) << 16}))
  end
end

local aeotec_minimote = {
  NAME = "Aeotec Minimote",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  can_handle = can_handle_aeotec_minimote,
}

return aeotec_minimote
