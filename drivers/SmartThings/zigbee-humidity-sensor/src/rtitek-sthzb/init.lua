-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local device_management = require "st.zigbee.device_management"
local generic_body = require "st.zigbee.generic_body"
local global_commands = require "st.zigbee.zcl.global_commands"
local log = require "log"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local zcl_messages = require "st.zigbee.zcl"

local PowerConfiguration = clusters.PowerConfiguration
local RelativeHumidity = clusters.RelativeHumidity
local TemperatureMeasurement = clusters.TemperatureMeasurement

local RTI_TEK_PRIVATE_CLUSTER = 0xFD22
local TEMPERATURE_UNIT_ATTR = 0x0000
local FAULT_CODE_ATTR = 0x0002
local TEMPERATURE_CALIBRATION_ATTR = 0xE005
local HUMIDITY_CALIBRATION_ATTR = 0xE006
local TEMPERATURE_ALARM_UPPER_ATTR = 0xE00A
local TEMPERATURE_ALARM_LOWER_ATTR = 0xE00B
local HUMIDITY_ALARM_UPPER_ATTR = 0xE00C
local HUMIDITY_ALARM_LOWER_ATTR = 0xE00D
local TEMPERATURE_ALARM_STATUS_ATTR = 0xE00E
local HUMIDITY_ALARM_STATUS_ATTR = 0xE00F

local PRIVATE_ATTRIBUTES = {
  TEMPERATURE_UNIT_ATTR,
  FAULT_CODE_ATTR,
  TEMPERATURE_CALIBRATION_ATTR,
  HUMIDITY_CALIBRATION_ATTR,
  TEMPERATURE_ALARM_UPPER_ATTR,
  TEMPERATURE_ALARM_LOWER_ATTR,
  HUMIDITY_ALARM_UPPER_ATTR,
  HUMIDITY_ALARM_LOWER_ATTR,
  TEMPERATURE_ALARM_STATUS_ATTR,
  HUMIDITY_ALARM_STATUS_ATTR,
}

local DEFAULT_RAW_VALUES = {
  temperatureCalibration = 0,
  humidityCalibration = 0,
  temperatureAlarmUpper = 2600,
  temperatureAlarmLower = 2000,
  humidityAlarmUpper = 6000,
  humidityAlarmLower = 3000,
}

local PREFERENCE_FIELDS = {
  temperatureCalibration = {
    attr = TEMPERATURE_CALIBRATION_ATTR,
    data_type = data_types.Int8,
    field = "rtitek_temperature_calibration",
    minimum = -10,
    maximum = 10,
    scale = 10,
    step = 0.1,
  },
  humidityCalibration = {
    attr = HUMIDITY_CALIBRATION_ATTR,
    data_type = data_types.Int8,
    field = "rtitek_humidity_calibration",
    minimum = -10,
    maximum = 10,
    scale = 10,
    step = 0.1,
  },
  temperatureAlarmUpper = {
    attr = TEMPERATURE_ALARM_UPPER_ATTR,
    data_type = data_types.Int16,
    field = "rtitek_temperature_alarm_upper",
    paired_field = "rtitek_temperature_alarm_lower",
    paired_preference = "temperatureAlarmLower",
    minimum = -30,
    maximum = 60,
    scale = 100,
    step = 0.1,
    gap = 10,
    is_upper = true,
  },
  temperatureAlarmLower = {
    attr = TEMPERATURE_ALARM_LOWER_ATTR,
    data_type = data_types.Int16,
    field = "rtitek_temperature_alarm_lower",
    paired_field = "rtitek_temperature_alarm_upper",
    paired_preference = "temperatureAlarmUpper",
    minimum = -30,
    maximum = 60,
    scale = 100,
    step = 0.1,
    gap = 10,
    is_upper = false,
  },
  humidityAlarmUpper = {
    attr = HUMIDITY_ALARM_UPPER_ATTR,
    data_type = data_types.Uint16,
    field = "rtitek_humidity_alarm_upper",
    paired_field = "rtitek_humidity_alarm_lower",
    paired_preference = "humidityAlarmLower",
    minimum = 0,
    maximum = 100,
    scale = 100,
    step = 1,
    gap = 100,
    is_upper = true,
  },
  humidityAlarmLower = {
    attr = HUMIDITY_ALARM_LOWER_ATTR,
    data_type = data_types.Uint16,
    field = "rtitek_humidity_alarm_lower",
    paired_field = "rtitek_humidity_alarm_upper",
    paired_preference = "humidityAlarmUpper",
    minimum = 0,
    maximum = 100,
    scale = 100,
    step = 1,
    gap = 100,
    is_upper = false,
  },
}

local function private_endpoint(device)
  return device:get_endpoint(RTI_TEK_PRIVATE_CLUSTER) or 0x01
end

local function round_to_step(value, step)
  local scaled = value / step
  if scaled >= 0 then
    return math.floor(scaled + 0.5) * step
  end
  return math.ceil(scaled - 0.5) * step
end

local function raw_value(value, setting)
  value = math.max(setting.minimum, math.min(setting.maximum, value))
  local raw = round_to_step(value, setting.step) * setting.scale
  if raw >= 0 then
    return math.floor(raw + 0.5)
  end
  return math.ceil(raw - 0.5)
end

local function clamp_paired_limit(raw, paired_raw, is_upper, gap)
  if paired_raw == nil then
    return raw
  end
  if is_upper and raw <= paired_raw then
    return paired_raw + gap
  end
  if not is_upper and raw >= paired_raw then
    return paired_raw - gap
  end
  return raw
end

local function raw_preference_value(preferences, name)
  local setting = PREFERENCE_FIELDS[name]
  local value = preferences and preferences[name]
  if setting == nil or type(value) ~= "number" then
    return nil
  end
  return raw_value(value, setting)
end

local function clamp_raw_to_setting(raw, setting)
  local minimum = raw_value(setting.minimum, setting)
  local maximum = raw_value(setting.maximum, setting)
  return math.max(minimum, math.min(maximum, raw))
end

local function send_private_read(device, attr_id)
  local payload = string.char(attr_id & 0xFF, (attr_id >> 8) & 0xFF)
  local header = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(global_commands.ReadAttribute.ID),
  })
  local address = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    private_endpoint(device),
    zb_const.HA_PROFILE_ID,
    RTI_TEK_PRIVATE_CLUSTER
  )
  device:send(messages.ZigbeeMessageTx({
    address_header = address,
    body = zcl_messages.ZclMessageBody({
      zcl_header = header,
      zcl_body = generic_body.GenericBody(payload),
    }),
  }))
end

local function send_private_write(device, attr_id, data_type, value)
  local record = global_commands.WriteAttribute.AttributeRecord(
    data_types.AttributeId(attr_id),
    data_types.ZigbeeDataType(data_type.ID),
    data_type(value)
  )
  local header = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(global_commands.WriteAttribute.ID),
  })
  local address = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    private_endpoint(device),
    zb_const.HA_PROFILE_ID,
    RTI_TEK_PRIVATE_CLUSTER
  )
  device:send(messages.ZigbeeMessageTx({
    address_header = address,
    body = zcl_messages.ZclMessageBody({
      zcl_header = header,
      zcl_body = global_commands.WriteAttribute({ record }),
    }),
  }))
end

local function log_link_metrics(device, zb_rx)
  if zb_rx ~= nil and (zb_rx.lqi ~= nil or zb_rx.rssi ~= nil) then
    device.log.debug_with({ hub_logs = true }, string.format(
      "Rti-Tek STHZB Zigbee link: LQI %s / RSSI %s dBm",
      tostring(zb_rx.lqi), tostring(zb_rx.rssi)
    ))
  end
end

local function do_refresh(driver, device)
  device:send(TemperatureMeasurement.attributes.MeasuredValue:read(device))
  device:send(RelativeHumidity.attributes.MeasuredValue:read(device))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  for _, attr_id in ipairs(PRIVATE_ATTRIBUTES) do
    send_private_read(device, attr_id)
  end
end

local function do_configure(driver, device)
  device:send(device_management.build_bind_request(
    device, TemperatureMeasurement.ID, driver.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(
    device, RelativeHumidity.ID, driver.environment_info.hub_zigbee_eui))
  device:send(device_management.build_bind_request(
    device, PowerConfiguration.ID, driver.environment_info.hub_zigbee_eui))
  device:send(TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(device, 10, 300, 50))
  device:send(RelativeHumidity.attributes.MeasuredValue:configure_reporting(device, 10, 300, 100))
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 5))
  do_refresh(driver, device)
end

local function init(driver, device)
  for name, value in pairs(DEFAULT_RAW_VALUES) do
    local setting = PREFERENCE_FIELDS[name]
    if device:get_field(setting.field) == nil then
      device:set_field(setting.field, value, { persist = true })
    end
  end
end

local function temperature_handler(driver, device, value, zb_rx)
  if value.value ~= -32768 then
    device:emit_event(capabilities.temperatureMeasurement.temperature({
      value = value.value / 100,
      unit = "C",
    }))
  end
  log_link_metrics(device, zb_rx)
end

local function humidity_handler(driver, device, value, zb_rx)
  if value.value ~= 0xFFFF then
    device:emit_event(capabilities.relativeHumidityMeasurement.humidity({
      value = value.value / 100,
    }))
  end
  log_link_metrics(device, zb_rx)
end

local function battery_handler(driver, device, value, zb_rx)
  local percentage = math.floor(value.value / 2 + 0.5)
  if percentage >= 0 and percentage <= 100 then
    device:emit_event(capabilities.battery.battery(percentage))
  end
  log_link_metrics(device, zb_rx)
end

local function cache_private_value(device, field, value, zb_rx)
  device:set_field(field, value.value, { persist = true })
  log_link_metrics(device, zb_rx)
end

local function temperature_unit_handler(driver, device, value, zb_rx)
  device:set_field("rtitek_temperature_unit", value.value, { persist = true })
  log_link_metrics(device, zb_rx)
end

local function fault_code_handler(driver, device, value, zb_rx)
  device:set_field("rtitek_fault_code", value.value, { persist = true })
  device.log.info_with({ hub_logs = true }, string.format(
    "Rti-Tek STHZB fault code: 0x%X", value.value
  ))
  log_link_metrics(device, zb_rx)
end

local function temperature_alarm_status_handler(driver, device, value, zb_rx)
  local raw = value.value
  device:set_field("rtitek_temperature_alarm_status", raw, { persist = true })
  if raw == 1 then
    device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.freeze())
  elseif raw == 2 then
    device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.heat())
  else
    device:emit_event(capabilities.temperatureAlarm.temperatureAlarm.cleared())
  end
  log_link_metrics(device, zb_rx)
end

local function humidity_alarm_status_handler(driver, device, value, zb_rx)
  device:set_field("rtitek_humidity_alarm_status", value.value, { persist = true })
  device.log.info_with({ hub_logs = true }, string.format(
    "Rti-Tek STHZB humidity alarm status: %s", tostring(value.value)
  ))
  log_link_metrics(device, zb_rx)
end

local function write_preference(device, name, value, preferences)
  local setting = PREFERENCE_FIELDS[name]
  if setting == nil or type(value) ~= "number" then
    return
  end

  local raw = raw_value(value, setting)
  local paired_raw = raw_preference_value(preferences, setting.paired_preference)
  if paired_raw == nil and setting.paired_field ~= nil then
    paired_raw = device:get_field(setting.paired_field)
  end
  raw = clamp_raw_to_setting(clamp_paired_limit(raw, paired_raw, setting.is_upper, setting.gap), setting)
  if raw ~= raw_value(value, setting) then
    device.log.warn_with({ hub_logs = true }, string.format(
      "Rti-Tek STHZB clamped %s from %s to %.1f",
      name, tostring(value), raw / setting.scale
    ))
  end
  device:set_field(setting.field, raw, { persist = true })
  send_private_write(device, setting.attr, setting.data_type, raw)
  send_private_read(device, setting.attr)
end

local function info_changed(driver, device, event, args)
  local old_preferences = args.old_st_store and args.old_st_store.preferences or {}
  local new_preferences = device.preferences or {}

  if old_preferences.temperatureUnit ~= new_preferences.temperatureUnit then
    local unit = tonumber(new_preferences.temperatureUnit)
    if unit == 0 or unit == 1 then
      device:set_field("rtitek_temperature_unit", unit, { persist = true })
      send_private_write(device, TEMPERATURE_UNIT_ATTR, data_types.Enum8, unit)
      send_private_read(device, TEMPERATURE_UNIT_ATTR)
    end
  end

  for name, _ in pairs(PREFERENCE_FIELDS) do
    if old_preferences[name] ~= new_preferences[name] then
      write_preference(device, name, new_preferences[name], new_preferences)
    end
  end
end

local rtitek_sthzb = {
  NAME = "Rti-Tek STHZB",
  can_handle = require "rtitek-sthzb.can_handle",
  lifecycle_handlers = {
    init = init,
    doConfigure = do_configure,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    },
  },
  zigbee_handlers = {
    attr = {
      [TemperatureMeasurement.ID] = {
        [TemperatureMeasurement.attributes.MeasuredValue.ID] = temperature_handler,
      },
      [RelativeHumidity.ID] = {
        [RelativeHumidity.attributes.MeasuredValue.ID] = humidity_handler,
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_handler,
      },
      [RTI_TEK_PRIVATE_CLUSTER] = {
        [TEMPERATURE_UNIT_ATTR] = temperature_unit_handler,
        [FAULT_CODE_ATTR] = fault_code_handler,
        [TEMPERATURE_CALIBRATION_ATTR] = function(d, dev, v, rx)
          cache_private_value(dev, "rtitek_temperature_calibration", v, rx)
        end,
        [HUMIDITY_CALIBRATION_ATTR] = function(d, dev, v, rx)
          cache_private_value(dev, "rtitek_humidity_calibration", v, rx)
        end,
        [TEMPERATURE_ALARM_UPPER_ATTR] = function(d, dev, v, rx)
          cache_private_value(dev, "rtitek_temperature_alarm_upper", v, rx)
        end,
        [TEMPERATURE_ALARM_LOWER_ATTR] = function(d, dev, v, rx)
          cache_private_value(dev, "rtitek_temperature_alarm_lower", v, rx)
        end,
        [HUMIDITY_ALARM_UPPER_ATTR] = function(d, dev, v, rx)
          cache_private_value(dev, "rtitek_humidity_alarm_upper", v, rx)
        end,
        [HUMIDITY_ALARM_LOWER_ATTR] = function(d, dev, v, rx)
          cache_private_value(dev, "rtitek_humidity_alarm_lower", v, rx)
        end,
        [TEMPERATURE_ALARM_STATUS_ATTR] = temperature_alarm_status_handler,
        [HUMIDITY_ALARM_STATUS_ATTR] = humidity_alarm_status_handler,
      },
    },
  },
}

return rtitek_sthzb
