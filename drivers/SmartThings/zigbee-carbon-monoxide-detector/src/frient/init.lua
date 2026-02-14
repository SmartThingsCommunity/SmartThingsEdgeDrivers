-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local IASZone = zcl_clusters.IASZone
local CarbonMonoxideCluster = zcl_clusters.CarbonMonoxide
local carbonMonoxide = capabilities.carbonMonoxideDetector
local CarbonMonoxideEndpoint = 0x2E
local SmokeAlarmEndpoint = 0x23
local TemperatureMeasurement = zcl_clusters.TemperatureMeasurement
local TEMPERATURE_ENDPOINT = 0x26
local alarm = capabilities.alarm
local smokeDetector = capabilities.smokeDetector
local IASWD = zcl_clusters.IASWD
local carbonMonoxideMeasurement = capabilities.carbonMonoxideMeasurement
local tamperAlert = capabilities.tamperAlert
local SirenConfiguration = IASWD.types.SirenConfiguration
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local SinglePrecisionFloat = require "st.zigbee.data_types.SinglePrecisionFloat"
local ALARM_COMMAND = "alarmCommand"
local ALARM_DURATION = "warningDuration"
local DEFAULT_MAX_WARNING_DURATION = 0x00F0
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local Status = require "st.zigbee.generated.types.ZclStatus"

local alarm_command = {
  OFF = 0,
  SIREN = 1
}

local CONFIGURATIONS = {
  {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 0,
    maximum_interval = 300,
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1
  },
  {
    cluster = CarbonMonoxideCluster.ID,
    attribute = CarbonMonoxideCluster.attributes.MeasuredValue.ID,
    minimum_interval = 30,
    maximum_interval = 600,
    data_type = data_types.SinglePrecisionFloat,
    reportable_change = SinglePrecisionFloat(0, -20, 0.048576)  -- 0, -20, 0.048576 is 1ppm in SinglePrecisionFloat
  }
}

local function get_current_max_warning_duration(device)
  return device.preferences.maxWarningDuration == nil and DEFAULT_MAX_WARNING_DURATION or device.preferences.maxWarningDuration
end

local function device_added(driver, device)
  device:emit_event(alarm.alarm.off())
  device:emit_event(smokeDetector.smoke.clear())
  device:emit_event(carbonMonoxide.carbonMonoxide.clear())
  device:emit_event(tamperAlert.tamper.clear())
  device:emit_event(carbonMonoxideMeasurement.carbonMonoxideLevel({value = 0, unit = "ppm"}))
end

local function device_init(driver, device)
  battery_defaults.build_linear_voltage_init(2.6, 3.1)(driver, device)
  if CONFIGURATIONS ~= nil then
    for _, attribute in ipairs(CONFIGURATIONS) do
      device:add_configured_attribute(attribute)
    end
  end
end

local function generate_event_from_zone_status(driver, device, zone_status, zigbee_message)
  local endpoint = zigbee_message.address_header.src_endpoint.value
  if endpoint == SmokeAlarmEndpoint then
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
  if endpoint == CarbonMonoxideEndpoint then
    if zone_status:is_test_set() then
      device:emit_event(carbonMonoxide.carbonMonoxide.tested())
    elseif zone_status:is_alarm1_set() then
      device:emit_event(carbonMonoxide.carbonMonoxide.detected())
    else
      device.thread:call_with_delay(6, function ()
        device:emit_event(carbonMonoxide.carbonMonoxide.clear())
      end)
    end
  end
  if zone_status:is_tamper_set() then
    device:emit_event(tamperAlert.tamper.detected())
  else
    device:emit_event(tamperAlert.tamper.clear())
  end
end

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function ias_zone_status_change_handler(driver, device, zb_rx)
  local zone_status = zb_rx.body.zcl_body.zone_status
  generate_event_from_zone_status(driver, device, zone_status, zb_rx)
end

local function carbon_monoxide_measure_value_attr_handler(driver, device, attr_val, zb_rx)
  local co_value = attr_val.value
  if co_value <= 1 then
    co_value = co_value * 1000000
  else
    return
  end
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, carbonMonoxideMeasurement.carbonMonoxideLevel({value = co_value, unit = "ppm"}))
end

local function do_refresh(driver, device)
  device:refresh()
end

local function do_configure(driver, device)
  device:configure()
  local maxWarningDuration = get_current_max_warning_duration(device)
  device:set_field(ALARM_DURATION, maxWarningDuration , { persist = true})
  device:send(IASWD.attributes.MaxDuration:write(device, maxWarningDuration):to_endpoint(0x23))

  device.thread:call_with_delay(5, function()
    do_refresh(driver, device)
  end)
end

local function send_siren_command(device, warning_mode, warning_siren_level)
  local warning_duration = get_current_max_warning_duration(device)
  local siren_configuration

  siren_configuration = SirenConfiguration(0x00)
  siren_configuration:set_warning_mode(warning_mode)
  siren_configuration:set_siren_level(warning_siren_level)

  device:send(
          IASWD.server.commands.StartWarning(
                  device,
                  siren_configuration,
                  data_types.Uint16(warning_duration),
                  data_types.Uint8(0x00),
                  data_types.Enum8(0x00)
          )
  )
end

local function siren_switch_off_handler(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.OFF, {persist = true})
  send_siren_command(device, 0x00, 0x00)
end

local function siren_alarm_siren_handler(driver, device, command)
  device:set_field(ALARM_COMMAND, alarm_command.SIREN, {persist = true})
  send_siren_command(device, 0x01 , 0x01)

  local warningDurationDelay = get_current_max_warning_duration(device)

  device.thread:call_with_delay(warningDurationDelay, function() -- Send command to switch from siren to off in the app when the siren is done
    if(device:get_field(ALARM_COMMAND) == alarm_command.SIREN) then
      siren_switch_off_handler(driver, device, command)
    end
  end)
end

local emit_alarm_event = function(device, cmd)
  if cmd == alarm_command.OFF then
    device:emit_event(capabilities.alarm.alarm.off())
  elseif cmd == alarm_command.SIREN then
    device:emit_event(capabilities.alarm.alarm.siren())
  end
end

local default_response_handler = function(driver, device, zigbee_message)
  local is_success = zigbee_message.body.zcl_body.status.value
  local command = zigbee_message.body.zcl_body.cmd.value
  local alarm_ev = device:get_field(ALARM_COMMAND)

  if command == IASWD.server.commands.StartWarning.ID and is_success == Status.SUCCESS then
    if alarm_ev ~= alarm_command.OFF then
      emit_alarm_event(device, alarm_ev)
      local lastDuration = get_current_max_warning_duration(device)
      device.thread:call_with_delay(lastDuration, function(d)
        device:emit_event(capabilities.alarm.alarm.off())
      end)
    else
      emit_alarm_event(device,alarm_command.OFF)
    end
  end
end

local function info_changed(driver, device, event, args)
  for name, info in pairs(device.preferences) do
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      if (name == "maxWarningDuration") then
        local input = device.preferences.maxWarningDuration
        device:send(IASWD.attributes.MaxDuration:write(device, input))
      end
      if (name == "temperatureSensitivity") then
        local sensitivity = device.preferences.temperatureSensitivity
        local temperatureSensitivity = math.floor(sensitivity * 100 + 0.5)
        device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 30, 600, temperatureSensitivity):to_endpoint(TEMPERATURE_ENDPOINT))
      end
    end
  end
end

local frient_smoke_carbon_monoxide = {
  NAME = "Frient Smoke Carbon Monoxide",
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    refresh = do_refresh,
    configure = do_configure,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [alarm.ID] = {
      [alarm.commands.off.NAME] = siren_switch_off_handler,
      [alarm.commands.siren.NAME] = siren_alarm_siren_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    global = {
      [IASWD.ID] = {
        [zcl_global_commands.DEFAULT_RESPONSE_ID] = default_response_handler
      }
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
      [CarbonMonoxideCluster.ID] = {
        [CarbonMonoxideCluster.attributes.MeasuredValue.ID] = carbon_monoxide_measure_value_attr_handler
      }
    }
  },
  can_handle = require("frient.can_handle"),
}

return frient_smoke_carbon_monoxide