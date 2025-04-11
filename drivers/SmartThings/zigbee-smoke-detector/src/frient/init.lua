-- Copyright 2025 SmartThings
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

local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local data_types = require "st.zigbee.data_types"
local alarm = capabilities.alarm
local smokeDetector = capabilities.smokeDetector

local IASWD = zcl_clusters.IASWD
local IASZone = zcl_clusters.IASZone
local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement

local ALARM_COMMAND = "alarmCommand"
local ALARM_LAST_DURATION = "Custom_Alarm_Duration"
local ALARM_DEFAULT_MAX_DURATION = 0x00F0
local DEFAULT_WARNING_DURATION = 240
local BATTERY_MIN_VOLTAGE = 2.3
local BATTERY_MAX_VOLTAGE = 3.0

local TEMPERATURE_MEASUREMENT_ENDPOINT = 0x26

local alarm_command = {
  OFF = 0,
  SIREN = 1
}

local CONFIGURATIONS = {
  {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 30,
    maximum_interval = 300,
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1
  },
  {
    cluster = TemperatureMeasurement.ID,
    attribute = TemperatureMeasurement.attributes.MeasuredValue.ID,
    minimum_interval = 60,
    maximum_interval = 600,
    data_type = TemperatureMeasurement.attributes.MeasuredValue.base_type,
    reportable_change = 100
  }
}

local function device_added(driver, device)
  device:emit_event(alarm.alarm.off())
  device:emit_event(smokeDetector.smoke.clear())
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(BATTERY_MIN_VOLTAGE, BATTERY_MAX_VOLTAGE)(driver, device)
  if CONFIGURATIONS ~= nil then
    for _, attribute in ipairs(CONFIGURATIONS) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
end

local function do_configure(self, device)
  device:configure()
  device:send(IASWD.attributes.MaxDuration:write(device, ALARM_DEFAULT_MAX_DURATION))
end

local info_changed = function (driver, device, event, args)
  for name, info in pairs(device.preferences) do
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      local input = device.preferences[name]
      if (name == "tempSensitivity") then
        local sensitivity = math.floor((device.preferences.tempSensitivity or 0.1)*100 + 0.5)
        device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 60, 600, sensitivity):to_endpoint(TEMPERATURE_MEASUREMENT_ENDPOINT))
      elseif (name == "warningDuration") then
        device:set_field(ALARM_LAST_DURATION, input, {persist = true})
        device:send(IASWD.attributes.MaxDuration:write(device, tonumber(input)))
      end
    end
  end
end

local function generate_event_from_zone_status(driver, device, zone_status, zigbee_message)
   print("Received ZoneStatus:", zone_status.value)

   if zone_status:is_test_set() then
      print("Test mode detected!")
      device:emit_event(smokeDetector.smoke.tested())
   elseif zone_status:is_alarm1_set() then
      print("Smoke detected!")
      device:emit_event(smokeDetector.smoke.detected())
   else
      device.thread:call_with_delay(6, function ()
        print("Smoke cleared!")
      device:emit_event(smokeDetector.smoke.clear())
      end)
   end
end

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  local zone_status = zb_rx.body.zcl_body.zone_status
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function send_siren_command(device)
  local warning_duration = device:get_field(ALARM_LAST_DURATION) or DEFAULT_WARNING_DURATION
  local sirenConfiguration = IASWD.types.SirenConfiguration(0x00)

  sirenConfiguration:set_warning_mode(0x01)

  device:send(
    IASWD.server.commands.StartWarning(
      device,
      sirenConfiguration,
      data_types.Uint16(warning_duration)
    )
  )

end

local emit_alarm_event = function(device, cmd)
  if cmd == alarm_command.OFF then
    device:emit_event(alarm.alarm.off())
  else
    if cmd == alarm_command.SIREN then
      device:emit_event(alarm.alarm.siren())
    end
  end
end

local default_response_handler = function(driver, device, zigbee_message)
  local command = zigbee_message.body.zcl_body.cmd.value
  local alarm_ev = device:get_field(ALARM_COMMAND)
  if command == IASWD.server.commands.StartWarning.ID then
    if alarm_ev ~= alarm_command.OFF then
      emit_alarm_event(device, alarm_ev)
      local lastDuration = device:get_field(ALARM_LAST_DURATION) or ALARM_DEFAULT_MAX_DURATION
      device.thread:call_with_delay(lastDuration, function(d)
        device:emit_event(alarm.alarm.off())
      end)
    else
      emit_alarm_event(device,alarm_command.OFF)
    end
  end
end

local siren_alarm_siren_handler = function(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.SIREN, {persist = true})
  send_siren_command(device)
end


local siren_switch_off_handler = function(driver, device, command)
  local sirenConfiguration = IASWD.types.SirenConfiguration(0x00)
  sirenConfiguration:set_warning_mode(0x00)
  device:set_field(ALARM_COMMAND, alarm_command.OFF, {persist = true})

  device:send(
    IASWD.server.commands.StartWarning(
      device,
      sirenConfiguration
    )
  )
end

local frient_smoke_sensor = {
  NAME = "frient smoke sensor",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    init = device_init,
    infoChanged = info_changed
  },
  capability_handlers = {
    [alarm.ID] = {
      [alarm.commands.off.NAME] = siren_switch_off_handler,
      [alarm.commands.siren.NAME] = siren_alarm_siren_handler,
    },
  },
  zigbee_handlers = {
    global = {
      [IASWD.ID] = {
        [zcl_global_commands.DEFAULT_RESPONSE_ID] = default_response_handler
      },
    },
    cluster = {
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "frient A/S" and device:get_model() == "SMSZB-120"
  end
}
return frient_smoke_sensor
