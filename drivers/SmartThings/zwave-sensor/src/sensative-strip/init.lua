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



--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })

local SENSATIVE_MFR = 0x019A
local LEAKAGE_ALARM_PARAM = 12
local LEAKAGE_ALARM_OFF = 0
local SENSATIVE_COMFORT_PROFILE = "illuminance-temperature"
local CONFIG_REPORT_RECEIVED = "configReportReceived"

local function can_handle_sensative_strip(opts, driver, device, cmd, ...)
  return device.zwave_manufacturer_id == SENSATIVE_MFR
end

local function configuration_report(driver, device, cmd)
  local parameter_number = cmd.args.parameter_number
  local configuration_value = cmd.args.configuration_value

  if parameter_number == LEAKAGE_ALARM_PARAM then
    device:set_field(CONFIG_REPORT_RECEIVED, true, {persist = true})
    if configuration_value == LEAKAGE_ALARM_OFF then
      device:try_update_metadata({profile = SENSATIVE_COMFORT_PROFILE})
    end
  end
end

local function do_configure(driver, device)
  device:refresh()
  device:send(Configuration:Get({ parameter_number = LEAKAGE_ALARM_PARAM }))
end

local function wakeup_notification(driver, device, cmd)
  if device:get_field(CONFIG_REPORT_RECEIVED) ~= true then
    device:send(Configuration:Get({ parameter_number = LEAKAGE_ALARM_PARAM }))
  end
end

local sensative_strip = {
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report
    },
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "sensative_strip",
  can_handle = can_handle_sensative_strip
}

return sensative_strip
