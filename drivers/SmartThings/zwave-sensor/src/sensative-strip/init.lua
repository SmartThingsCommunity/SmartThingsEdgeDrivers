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

local SENSATIVE_MFR = 0x019A
local LEAKAGE_ALARM_PARAM = 12
local LEAKAGE_ALARM_OFF = 0
local SENSATIVE_COMFORT_PROFILE = "illuminance-temperature"

local function can_handle_sensative_strip(opts, driver, device, cmd, ...)
  return device.zwave_manufacturer_id == SENSATIVE_MFR
end

local function configuration_report(driver, device, cmd)
  local parameter_number = cmd.args.parameter_number
  local configuration_value = cmd.args.configuration_value

  if parameter_number == LEAKAGE_ALARM_PARAM and configuration_value == LEAKAGE_ALARM_OFF then
    device:try_update_metadata({profile = SENSATIVE_COMFORT_PROFILE})
  end
end

local function do_configure(driver, device)
  device:refresh()
  device:send(Configuration:Get({ parameter_number = LEAKAGE_ALARM_PARAM }))
end

local sensative_strip = {
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "sensative_strip",
  can_handle = can_handle_sensative_strip
}

return sensative_strip
