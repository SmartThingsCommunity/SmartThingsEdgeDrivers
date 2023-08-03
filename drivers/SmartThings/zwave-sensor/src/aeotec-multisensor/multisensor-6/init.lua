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
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({version = 2})

local MULTISENSOR_6_PRODUCT_ID = 0x0064
local PREFERENCE_NUM = 9

local function can_handle_multisensor_6(opts, self, device, ...)
  return device.zwave_product_id == MULTISENSOR_6_PRODUCT_ID
end

local function wakeup_notification(driver, device, cmd)
  --Note sending WakeUpIntervalGet the first time a device wakes up will happen by default in Lua libs 0.49.x and higher
  --This is done to help the hub correctly set the checkInterval for migrated devices.
  if not device:get_field("__wakeup_interval_get_sent") then
    device:send(WakeUp:IntervalGetV1({}))
    device:set_field("__wakeup_interval_get_sent", true)
  end
  device:send(Configuration:Get({parameter_number = PREFERENCE_NUM}))
  device:refresh()
end

local function configuration_report_handler(self, device, cmd)
  local power_source
  if cmd.args.parameter_number == PREFERENCE_NUM then
    if cmd.args.configuration_value & 0x100 == 0 then
      power_source = capabilities.powerSource.powerSource.dc()
    else
      power_source = capabilities.powerSource.powerSource.battery()
    end
  end

  if power_source ~= nil then
    device:emit_event(power_source)
  end
end

local multisensor_6 = {
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report_handler
    },
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  },
  NAME = "aeotec multisensor 6",
  can_handle = can_handle_multisensor_6
}

return multisensor_6
