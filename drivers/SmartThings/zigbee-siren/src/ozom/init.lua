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
local WarningMode = IASWD.types.WarningMode
local Strobe = IASWD.types.Strobe
local IaswdLevel = IASWD.types.IaswdLevel


--capability
local capabilities = require "st.capabilities"
local switch = capabilities.switch

local ALARM_COMMAND = "alarmCommand"
local ALARM_LAST_DURATION = "lastDuration"
local ALARM_MAX_DURATION = "maxDuration"

local ALARM_DEFAULT_MAX_DURATION = 0x00B4
local ALARM_STROBE_DUTY_CYCLE = 40

local alarm_command = {
    OFF = 0,
    SIREN = 1,
    STROBE = 2,
    BOTH = 3
}

local send_siren_command = function(device, warning_mode, warning_sirenLevel, strobe_active, strobe_level)
  local max_duration = device:get_field(ALARM_MAX_DURATION)
  local warning_duration = max_duration and max_duration or ALARM_DEFAULT_MAX_DURATION

  device:set_field(ALARM_LAST_DURATION, warning_duration, {persist = true})

  local siren_configuration = SirenConfiguration(0x00)

  siren_configuration:set_warning_mode(warning_mode)
  siren_configuration:set_strobe(strobe_active)
  siren_configuration:set_siren_level(warning_sirenLevel)

  device:send(
    IASWD.server.commands.StartWarning(
      device,
      siren_configuration,
      data_types.Uint16(warning_duration),
      data_types.Uint8(ALARM_STROBE_DUTY_CYCLE),
      data_types.Enum8(strobe_level)
    )
  )
end

local siren_switch_on_handler = function(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.SIREN, {persist = true})
  send_siren_command(device, WarningMode.BURGLAR, IaswdLevel.VERY_HIGH_LEVEL, Strobe.NO_STROBE, IaswdLevel.LOW_LEVEL)
end

local ozom_siren_driver = {
  NAME = "Ozom",
  capability_handlers = {
    [switch.ID] = {
      [switch.commands.on.NAME] = siren_switch_on_handler
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "ClimaxTechnology"
  end
}

return ozom_siren_driver
