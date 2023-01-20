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
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 2 })
local preferences = require "preferences"

local MULTISENSOR_7_PRODUCT_ID = 0x0018
local PREFERENCE_NUM = 10

local function preference_update(driver, device, args)
  preferences.update_preferences(driver, device, args)
  device:send(Configuration:Get({parameter_number = PREFERENCE_NUM}))

end

local function device_added(self, device)
  device:send(Configuration:Get({parameter_number = PREFERENCE_NUM}))
  device:refresh()
end

local function device_init(self, device)
  device:set_update_preferences_fn(preference_update)
end

local function can_handle_multisensor_7(opts, self, device, ...)
  return device.zwave_product_id == MULTISENSOR_7_PRODUCT_ID
end

local function configuration_report_handler(self, device, cmd)
  local power_source
  if cmd.args.parameter_number == PREFERENCE_NUM then
    if cmd.args.configuration_value == 0 then
        power_source = capabilities.powerSource.powerSource.battery()
      else
        power_source = capabilities.powerSource.powerSource.dc()
      end
  end

  if power_source ~= nil then
    device:emit_event(power_source)
  end
end

local multisensor_7 = {
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report_handler
    }
  },
  lifecycle_handlers = {
    added = device_added,
    init = device_init
  },
  NAME = "aeotec multisensor 7",
  can_handle = can_handle_multisensor_7
}

return multisensor_7
