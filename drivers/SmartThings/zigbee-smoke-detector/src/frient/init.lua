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

local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"
local Basic = zcl_clusters.Basic
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

local DEVELCO_MANUFACTURER_CODE = 0x1015
local DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR = 0x8000

local PRIMARY_SW_VERSION = "primary_sw_version"
local SMOKE_ALARM_FIXED_ENDIAN_SW_VERSION = "040005"

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

local function primary_sw_version_attr_handler(driver, device, value, zb_rx)
  local primary_sw_version = value.value:gsub('.', function (c) return string.format('%02x', string.byte(c)) end)
  device:set_field(PRIMARY_SW_VERSION, primary_sw_version, {persist = true})
end

local function device_added(driver, device)
  device:emit_event(alarm.alarm.off())
  device:emit_event(smokeDetector.smoke.clear())
  device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, DEVELCO_MANUFACTURER_CODE))
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

  local sw_version = device:get_field(PRIMARY_SW_VERSION)
  if ((sw_version == nil) or (sw_version == "")) then
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, DEVELCO_MANUFACTURER_CODE))
  end
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

   if zone_status:is_test_set() then
      device:emit_event(smokeDetector.smoke.tested())
   elseif zone_status:is_alarm1_set() then
      device:emit_event(smokeDetector.smoke.detected())
   else
      device.thread:call_with_delay(6, function ()
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

local emit_alarm_event = function(device, cmd)
  if cmd == alarm_command.OFF then
    device:emit_event(alarm.alarm.off())
  elseif cmd == alarm_command.SIREN then
      device:emit_event(alarm.alarm.siren())
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
  device:set_field(ALARM_COMMAND, alarm_command.SIREN)

  local sw_version = device:get_field(PRIMARY_SW_VERSION)
  if ((sw_version == nil) or (sw_version == "")) then
    device:send(cluster_base.read_manufacturer_specific_attribute(device, Basic.ID, DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR, DEVELCO_MANUFACTURER_CODE))
  end

  local warning_duration = device:get_field(ALARM_LAST_DURATION) or DEFAULT_WARNING_DURATION
  local sirenConfiguration
  local warning_mode = 0x01  -- For siren on

  if (device:get_field(PRIMARY_SW_VERSION) < SMOKE_ALARM_FIXED_ENDIAN_SW_VERSION) then
    -- Old frient firmware, the endian format is reversed
    local siren_config_value = warning_mode
    sirenConfiguration = IASWD.types.SirenConfiguration(siren_config_value)
  else
    sirenConfiguration = IASWD.types.SirenConfiguration(0x00)
    sirenConfiguration:set_warning_mode(warning_mode)
  end

  device:send(
    IASWD.server.commands.StartWarning(
      device,
      sirenConfiguration,
      data_types.Uint16(warning_duration),
      data_types.Uint8(00),
      data_types.Enum8(00)
    )
  )
end


local siren_switch_off_handler = function(driver, device, command)
  local sirenConfiguration
  local warning_mode = 0x00  -- For siren off

  if (device:get_field(PRIMARY_SW_VERSION) < SMOKE_ALARM_FIXED_ENDIAN_SW_VERSION) then
    -- Old frient firmware, the endian format is reversed
    sirenConfiguration = IASWD.types.SirenConfiguration(warning_mode)
  else
    sirenConfiguration = IASWD.types.SirenConfiguration(0x00)
    sirenConfiguration:set_warning_mode(warning_mode)
  end

  device:set_field(ALARM_COMMAND, alarm_command.OFF, {persist = true})

  device:send(
    IASWD.server.commands.StartWarning(
      device,
      sirenConfiguration,
      data_types.Uint16(0x00),
      data_types.Uint8(00),
      data_types.Enum8(00)
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
      },
      [Basic.ID] = {
        [DEVELCO_BASIC_PRIMARY_SW_VERSION_ATTR] = primary_sw_version_attr_handler,
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "frient A/S" and device:get_model() == "SMSZB-120"
  end
}
return frient_smoke_sensor
