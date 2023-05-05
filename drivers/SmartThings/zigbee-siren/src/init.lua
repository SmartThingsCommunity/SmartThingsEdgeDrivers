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

local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local constants = require "st.zigbee.constants"
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local data_types = require "st.zigbee.data_types"

--ZCL
local zcl_clusters = require "st.zigbee.zcl.clusters"
local Status = require "st.zigbee.generated.types.ZclStatus"
local IASZone = zcl_clusters.IASZone
local IASWD = zcl_clusters.IASWD
local SirenConfiguration = IASWD.types.SirenConfiguration
local WarningMode = IASWD.types.WarningMode
local Strobe = IASWD.types.Strobe
local IaswdLevel = IASWD.types.IaswdLevel

--Capability
local capabilities = require "st.capabilities"
local alarm = capabilities.alarm
local switch = capabilities.switch

-- Constants
local ALARM_COMMAND = "alarmCommand"
local ALARM_LAST_DURATION = "lastDuration"
local ALARM_MAX_DURATION = "maxDuration"

local ALARM_DEFAULT_MAX_DURATION = 0x00B4
local ALARM_DEFAULT_DURATION = 0xFFFE

local ALARM_STROBE_DUTY_CYCLE = 40

local alarm_command = {
  OFF = 0,
  SIREN = 1,
  STROBE = 2,
  BOTH = 3
}

local emit_alarm_event = function(device, cmd)
  if cmd == alarm_command.OFF then
    device:emit_event(capabilities.alarm.alarm.off())
    device:emit_event(capabilities.switch.switch.off())
  else
    if cmd == alarm_command.SIREN then
      device:emit_event(capabilities.alarm.alarm.siren())
    elseif cmd == alarm_command.STROBE then
      device:emit_event(capabilities.alarm.alarm.strobe())
    else
      device:emit_event(capabilities.alarm.alarm.both())
    end

    device:emit_event(capabilities.switch.switch.on())
  end
end

local send_siren_command = function(device, warning_mode, warning_siren_level, strobe_active, strobe_level)
  local max_duration = device:get_field(ALARM_MAX_DURATION)
  local warning_duration = max_duration and max_duration or ALARM_DEFAULT_MAX_DURATION
  local duty_cycle = ALARM_STROBE_DUTY_CYCLE

  device:set_field(ALARM_LAST_DURATION, warning_duration, {persist = true})

  local siren_configuration = SirenConfiguration(0x00)

  siren_configuration:set_warning_mode(warning_mode)
  siren_configuration:set_strobe(strobe_active)
  siren_configuration:set_siren_level(warning_siren_level)

  device:send(
      IASWD.server.commands.StartWarning(
          device,
          siren_configuration,
          data_types.Uint16(warning_duration),
          data_types.Uint8(duty_cycle),
          data_types.Enum8(strobe_level)
      )
  )
end

local default_response_handler = function(driver, device, zigbee_message)
  local is_success = zigbee_message.body.zcl_body.status.value
  local command = zigbee_message.body.zcl_body.cmd.value
  local alarm_ev = device:get_field(ALARM_COMMAND)

  if command == IASWD.server.commands.StartWarning.ID and is_success == Status.SUCCESS then
    if alarm_ev ~= alarm_command.OFF then
      emit_alarm_event(device, alarm_ev)
      local lastDuration = device:get_field(ALARM_LAST_DURATION) or ALARM_DEFAULT_MAX_DURATION
      device.thread:call_with_delay(lastDuration, function(d)
        device:emit_event(capabilities.alarm.alarm.off())
        device:emit_event(capabilities.switch.switch.off())
      end)
    else
      emit_alarm_event(device,alarm_command.OFF)
    end
  end
end

local attr_max_duration_handler = function(driver, device, max_duration)
  device:set_field(ALARM_MAX_DURATION, max_duration.value, {persist = true})
end

local siren_switch_both_handler = function(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.BOTH, {persist = true})
  send_siren_command(device, WarningMode.BURGLAR, IaswdLevel.VERY_HIGH_LEVEL, Strobe.USE_STROBE, IaswdLevel.VERY_HIGH_LEVEL)
end

local siren_alarm_siren_handler = function(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.SIREN, {persist = true})
  send_siren_command(device, WarningMode.BURGLAR, IaswdLevel.VERY_HIGH_LEVEL, Strobe.NO_STROBE, IaswdLevel.LOW_LEVEL)
end

local siren_alarm_strobe_handler = function(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.STROBE, {persist = true})
  send_siren_command(device, WarningMode.STOP, IaswdLevel.LOW_LEVEL, Strobe.USE_STROBE, IaswdLevel.VERY_HIGH_LEVEL)
end

local siren_switch_on_handler = function(driver, device, command)
  siren_switch_both_handler(driver, device, command)
end

local siren_switch_off_handler = function(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.OFF, {persist = true})
  send_siren_command(device, WarningMode.STOP, IaswdLevel.LOW_LEVEL, Strobe.NO_STROBE, IaswdLevel.LOW_LEVEL)
end

local do_configure = function(self, device)
  device:send(IASWD.attributes.MaxDuration:write(device, ALARM_DEFAULT_DURATION))

  device:configure()
  device:refresh()
end

local device_init = function(self, device)
  device:set_field(ALARM_MAX_DURATION, ALARM_DEFAULT_MAX_DURATION, {persist = true})
end

local function device_added(driver, device)
  -- device:emit_event(capabilities.alarm.alarm.off())
  -- device:emit_event(capabilities.switch.switch.off())
end

local zigbee_siren_driver_template = {
  supported_capabilities = {
    alarm,
    switch
  },
  ias_zone_configuration_method = constants.IAS_ZONE_CONFIGURE_TYPE.AUTO_ENROLL_RESPONSE,
  zigbee_handlers = {
    global = {
      [IASWD.ID] = {
        [zcl_global_commands.DEFAULT_RESPONSE_ID] = default_response_handler
      }
    },
    attr = {
      [IASWD.ID] = {
        [IASWD.attributes.MaxDuration.ID] = attr_max_duration_handler
      }
    }
  },
  capability_handlers = {
    [alarm.ID] = {
      [alarm.commands.both.NAME] = siren_switch_both_handler,
      [alarm.commands.off.NAME] = siren_switch_off_handler,
      [alarm.commands.siren.NAME] = siren_alarm_siren_handler,
      [alarm.commands.strobe.NAME] = siren_alarm_strobe_handler
    },
    [switch.ID] = {
      [switch.commands.on.NAME] = siren_switch_on_handler,
      [switch.commands.off.NAME] = siren_switch_off_handler
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure
  },
  sub_drivers = { require("ozom"), require("frient") },
  cluster_configurations = {
    [alarm.ID] = {
      {
        cluster = IASZone.ID,
        attribute = IASZone.attributes.ZoneStatus.ID,
        minimum_interval = 0,
        maximum_interval = 180,
        data_type = IASZone.attributes.ZoneStatus.base_type
      }
    }
  }
}

defaults.register_for_default_handlers(zigbee_siren_driver_template, zigbee_siren_driver_template.supported_capabilities)
local zigbee_siren = ZigbeeDriver("zigbee-siren", zigbee_siren_driver_template)
zigbee_siren:run()
