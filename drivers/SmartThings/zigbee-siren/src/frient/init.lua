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

local data_types = require "st.zigbee.data_types"
--ZCL
local zcl_clusters = require "st.zigbee.zcl.clusters"
local IASWD = zcl_clusters.IASWD
local SirenConfiguration = IASWD.types.SirenConfiguration
local IaswdLevel = IASWD.types.IaswdLevel

--capability
local capabilities = require "st.capabilities"
local alarm = capabilities.alarm
local switch = capabilities.switch

local ALARM_COMMAND = "alarmCommand"
local ALARM_LAST_DURATION = "lastDuration"
local ALARM_MAX_DURATION = "maxDuration"

local ALARM_DEFAULT_MAX_DURATION = 0x00B4
local ALARM_STROBE_DUTY_CYCLE = 00

local alarm_command = {
  OFF = 0,
  SIREN = 1,
  STROBE = 2,
  BOTH = 3
}

local send_siren_command = function(device)
  local max_duration = device:get_field(ALARM_MAX_DURATION)
  local warning_duration = max_duration and max_duration or ALARM_DEFAULT_MAX_DURATION
  local duty_cycle = ALARM_STROBE_DUTY_CYCLE

  device:set_field(ALARM_LAST_DURATION, warning_duration, {persist = true})

  local siren_configuration = SirenConfiguration(0xC1)

  device:send(
    IASWD.server.commands.StartWarning(
      device,
      siren_configuration,
      data_types.Uint16(warning_duration),
      data_types.Uint8(duty_cycle),
      data_types.Enum8(IaswdLevel.LOW_LEVEL)
    )
  )
end

local siren_switch_both_handler = function(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.BOTH, {persist = true})
  send_siren_command(device)
end

local siren_alarm_siren_handler = function(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.SIREN, {persist = true})
  send_siren_command(device)
end

local siren_alarm_strobe_handler = function(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.STROBE, {persist = true})
  send_siren_command(device)
end

local siren_switch_on_handler = function(driver, device, command)
  siren_switch_both_handler(driver, device, command)
end

local frient_siren_driver = {
  NAME = "frient A/S",
  capability_handlers = {
    [alarm.ID] = {
      [alarm.commands.both.NAME] = siren_switch_both_handler,
      [alarm.commands.siren.NAME] = siren_alarm_siren_handler,
      [alarm.commands.strobe.NAME] = siren_alarm_strobe_handler
    },
    [switch.ID] = {
      [switch.commands.on.NAME] = siren_switch_on_handler,
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "frient A/S"
  end
}

return frient_siren_driver
