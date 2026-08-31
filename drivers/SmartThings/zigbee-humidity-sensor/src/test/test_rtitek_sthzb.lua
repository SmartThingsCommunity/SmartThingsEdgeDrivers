-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local generic_body = require "st.zigbee.generic_body"
local global_commands = require "st.zigbee.zcl.global_commands"
local messages = require "st.zigbee.messages"
local report_attr = require "st.zigbee.zcl.global_commands.report_attribute"
local t_utils = require "integration_test.utils"
local write_attr = require "st.zigbee.zcl.global_commands.write_attribute"
local zb_const = require "st.zigbee.constants"
local zcl_messages = require "st.zigbee.zcl"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local PowerConfiguration = clusters.PowerConfiguration
local RelativeHumidity = clusters.RelativeHumidity
local TemperatureMeasurement = clusters.TemperatureMeasurement

local FD22 = 0xFD22
local UNIT = 0x0000
local FAULT = 0x0002
local TEMP_CAL = 0xE005
local HUMIDITY_CAL = 0xE006
local TEMP_HIGH = 0xE00A
local TEMP_LOW = 0xE00B
local HUMIDITY_HIGH = 0xE00C
local HUMIDITY_LOW = 0xE00D
local TEMP_ALARM = 0xE00E
local HUMIDITY_ALARM = 0xE00F

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("rtitek-sthzb.yml"),
  preferences = {
    temperatureUnit = "0",
    temperatureCalibration = 0,
    humidityCalibration = 0,
    temperatureAlarmUpper = 26,
    temperatureAlarmLower = 20,
    humidityAlarmUpper = 60,
    humidityAlarmLower = 30,
  },
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "Rti-Tek",
      model = "STHZB",
      server_clusters = { 0x0001, 0x0402, 0x0405, FD22 },
    },
  },
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

local function fd22_address(source)
  if source then
    return messages.AddressHeader(
      mock_device:get_short_address(), 0x01, zb_const.HUB.ADDR,
      zb_const.HUB.ENDPOINT, zb_const.HA_PROFILE_ID, FD22
    )
  end
  return messages.AddressHeader(
    zb_const.HUB.ADDR, zb_const.HUB.ENDPOINT, mock_device:get_short_address(),
    0x01, zb_const.HA_PROFILE_ID, FD22
  )
end

local function build_fd22_read(attr_id)
  local payload = string.char(attr_id & 0xFF, (attr_id >> 8) & 0xFF)
  return messages.ZigbeeMessageTx({
    address_header = fd22_address(false),
    body = zcl_messages.ZclMessageBody({
      zcl_header = zcl_messages.ZclHeader({
        cmd = data_types.ZCLCommandId(global_commands.ReadAttribute.ID),
      }),
      zcl_body = generic_body.GenericBody(payload),
    }),
  })
end

local function build_fd22_write(attr_id, data_type, value)
  local record = write_attr.WriteAttribute.AttributeRecord(
    data_types.AttributeId(attr_id),
    data_types.ZigbeeDataType(data_type.ID),
    data_type(value)
  )
  return messages.ZigbeeMessageTx({
    address_header = fd22_address(false),
    body = zcl_messages.ZclMessageBody({
      zcl_header = zcl_messages.ZclHeader({
        cmd = data_types.ZCLCommandId(write_attr.WriteAttribute.ID),
      }),
      zcl_body = write_attr.WriteAttribute({ record }),
    }),
  })
end

local function build_fd22_report(attr_id, data_type, value)
  local report = report_attr.ReportAttribute({
    report_attr.ReportAttributeAttributeRecord(attr_id, data_type.ID, value),
  })
  return messages.ZigbeeMessageRx({
    address_header = fd22_address(true),
    body = zcl_messages.ZclMessageBody({
      zcl_header = zcl_messages.ZclHeader({
        cmd = data_types.ZCLCommandId(report.ID),
      }),
      zcl_body = report,
    }),
  })
end

test.register_message_test(
  "STHZB standard temperature report is exposed in Celsius",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 2630),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main", capabilities.temperatureMeasurement.temperature({ value = 26.3, unit = "C" })
      ),
    },
  },
  { min_api_version = 14 }
)

test.register_message_test(
  "STHZB standard humidity report is exposed as percent",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_device, 5830),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main", capabilities.relativeHumidityMeasurement.humidity({ value = 58.3 })
      ),
    },
  },
  { min_api_version = 14 }
)

test.register_message_test(
  "STHZB standard battery percentage is exposed",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 150),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(75)),
    },
  },
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "STHZB refresh reads standard and private attributes",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} },
    })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({
      mock_device.id, TemperatureMeasurement.attributes.MeasuredValue:read(mock_device),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id, RelativeHumidity.attributes.MeasuredValue:read(mock_device),
    })
    test.socket.zigbee:__expect_send({
      mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device),
    })
    for _, attr_id in ipairs({
      UNIT, FAULT, TEMP_CAL, HUMIDITY_CAL, TEMP_HIGH,
      TEMP_LOW, HUMIDITY_HIGH, HUMIDITY_LOW, TEMP_ALARM, HUMIDITY_ALARM,
    }) do
      test.socket.zigbee:__expect_send({ mock_device.id, build_fd22_read(attr_id) })
    end
    test.wait_for_events()
  end,
  { min_api_version = 14 }
)

local function register_temperature_alarm_test(name, raw, event)
  test.register_message_test(
    name,
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, build_fd22_report(TEMP_ALARM, data_types.Enum8, raw) },
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", event),
      },
    },
    { min_api_version = 14 }
  )
end

register_temperature_alarm_test(
  "STHZB maps normal temperature alarm to cleared",
  0,
  capabilities.temperatureAlarm.temperatureAlarm.cleared()
)
register_temperature_alarm_test(
  "STHZB maps low temperature alarm to freeze",
  1,
  capabilities.temperatureAlarm.temperatureAlarm.freeze()
)
register_temperature_alarm_test(
  "STHZB maps high temperature alarm to heat",
  2,
  capabilities.temperatureAlarm.temperatureAlarm.heat()
)

test.register_coroutine_test(
  "STHZB writes calibration and temperature unit preferences with device precision",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = {
        temperatureUnit = "1",
        temperatureCalibration = -4.1,
        humidityCalibration = 3.2,
      },
    }))
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({
      mock_device.id, build_fd22_write(UNIT, data_types.Enum8, 1),
    })
    test.socket.zigbee:__expect_send({ mock_device.id, build_fd22_read(UNIT) })
    test.socket.zigbee:__expect_send({
      mock_device.id, build_fd22_write(TEMP_CAL, data_types.Int8, -41),
    })
    test.socket.zigbee:__expect_send({ mock_device.id, build_fd22_read(TEMP_CAL) })
    test.socket.zigbee:__expect_send({
      mock_device.id, build_fd22_write(HUMIDITY_CAL, data_types.Int8, 32),
    })
    test.socket.zigbee:__expect_send({ mock_device.id, build_fd22_read(HUMIDITY_CAL) })
    test.wait_for_events()
  end,
  { min_api_version = 14 }
)

test.register_coroutine_test(
  "STHZB validates alarm limits against saved preferences instead of stale device values",
  function()
    -- The device has a stale lower limit of 17.2 C, while the App setting is 20 C.
    mock_device:set_field("rtitek_temperature_alarm_lower", 1720, { persist = true })
    mock_device:set_field("rtitek_humidity_alarm_lower", 3000, { persist = true })
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = {
        temperatureAlarmUpper = 19,
        temperatureAlarmLower = 20,
        humidityAlarmUpper = 21.22,
        humidityAlarmLower = 30,
      },
    }))
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({
      mock_device.id, build_fd22_write(TEMP_HIGH, data_types.Int16, 2010),
    })
    test.socket.zigbee:__expect_send({ mock_device.id, build_fd22_read(TEMP_HIGH) })
    test.socket.zigbee:__expect_send({
      mock_device.id, build_fd22_write(HUMIDITY_HIGH, data_types.Uint16, 3100),
    })
    test.socket.zigbee:__expect_send({ mock_device.id, build_fd22_read(HUMIDITY_HIGH) })
    test.wait_for_events()
  end,
  { min_api_version = 14 }
)

test.run_registered_tests()
