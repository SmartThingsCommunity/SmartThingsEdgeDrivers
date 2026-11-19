-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local t_utils = require "integration_test.utils"

local MODE = clusters.OccupancySensing.attributes.PIRUnoccupiedToOccupiedThreshold
-- nil on hub libraries that predate this attribute, as the sub-driver allows
local HOLD_TIME = clusters.OccupancySensing.attributes.HoldTime

-- Endpoint and cluster layout of the device firmware
local matter_endpoints = {
  {
    endpoint_id = 0,
    clusters = {
      {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY},
    },
    device_types = {
      {device_type_id = 0x0016, device_type_revision = 1}, -- RootNode
      {device_type_id = 0x0011, device_type_revision = 1} -- PowerSource
    }
  },
  {
    endpoint_id = 1,
    clusters = {
      {
        cluster_id = clusters.OccupancySensing.ID,
        cluster_type = "SERVER",
        feature_map = clusters.OccupancySensing.types.Feature.PASSIVE_INFRARED | clusters.OccupancySensing.types.Feature.RADAR
      },
    },
    device_types = {
      {device_type_id = 0x0107, device_type_revision = 1} -- OccupancySensor
    }
  },
  {
    endpoint_id = 2,
    clusters = {
      {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
    },
    device_types = {
      {device_type_id = 0x0302, device_type_revision = 1} -- TemperatureSensor
    }
  },
  {
    endpoint_id = 3,
    clusters = {
      {cluster_id = clusters.IlluminanceMeasurement.ID, cluster_type = "SERVER"},
    },
    device_types = {
      {device_type_id = 0x0106, device_type_revision = 1} -- LightSensor
    }
  },
  {
    endpoint_id = 4,
    clusters = {
      {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
    },
    device_types = {
      {device_type_id = 0x0307, device_type_revision = 1} -- HumiditySensor
    }
  },
}

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thingsone-presence-sensor.yml"),
  manufacturer_info = {vendor_id = 0x1241, product_id = 0x8010},
  endpoints = matter_endpoints
})

local function subscribe_request(dev)
  local request = clusters.OccupancySensing.attributes.Occupancy:subscribe(dev)
  request:merge(clusters.TemperatureMeasurement.attributes.MeasuredValue:subscribe(dev))
  request:merge(clusters.TemperatureMeasurement.attributes.MinMeasuredValue:subscribe(dev))
  request:merge(clusters.TemperatureMeasurement.attributes.MaxMeasuredValue:subscribe(dev))
  request:merge(clusters.IlluminanceMeasurement.attributes.MeasuredValue:subscribe(dev))
  request:merge(clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:subscribe(dev))
  request:merge(clusters.PowerSource.attributes.BatPercentRemaining:subscribe(dev))
  request:merge(MODE:subscribe(dev))
  if HOLD_TIME ~= nil then
    request:merge(HOLD_TIME:subscribe(dev))
  end
  return request
end

local function test_init()
  test.socket.matter:__expect_send({mock_device.id, subscribe_request(mock_device)})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local function preference(id, value)
  return mock_device:generate_info_changed({preferences = {[id] = value}})
end

local function expect_write(attr, value)
  test.socket.matter:__expect_send({mock_device.id, attr:write(mock_device, 1, value)})
  test.socket.matter:__expect_send({mock_device.id, attr:read(mock_device)})
end

local function report(attr, value)
  return {mock_device.id, attr:build_test_report_data(mock_device, 1, value)}
end

test.register_coroutine_test(
  "doConfigure should keep the ThingsOne profile instead of reading the PowerSource AttributeList",
  function()
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
    mock_device:expect_metadata_update({profile = "thingsone-presence-sensor"})
    -- When doConfigure completes successfully, the framework automatically provisions the device
    mock_device:expect_metadata_update({provisioning_state = "PROVISIONED"})
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "driverSwitched should set the ThingsOne profile and provision the device",
  function()
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "driverSwitched"})
    mock_device:expect_metadata_update({profile = "thingsone-presence-sensor"})
    mock_device:expect_metadata_update({provisioning_state = "PROVISIONED"})
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "A profile change should renew the subscription",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({profile = {id = "00000000-1111-2222-3333-000000000004"}}))
    test.socket.matter:__expect_send({mock_device.id, subscribe_request(mock_device)})
    test.wait_for_events()
  end
)

test.register_message_test(
  "Occupancy reports should be passed on at once by the base driver",
  {
    {
      channel = "matter",
      direction = "receive",
      message = report(clusters.OccupancySensing.attributes.Occupancy, 1)
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.presenceSensor.presence("present"))
    },
    {
      channel = "matter",
      direction = "receive",
      message = report(clusters.OccupancySensing.attributes.Occupancy, 0)
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.presenceSensor.presence("not present"))
    }
  }
)

local function expect_no_write(attr, value)
  test.socket.matter:__queue_receive(report(attr, value))
  test.wait_for_events()
end

local function expect_rewrites_then_give_up(attr, wanted, other)
  for _ = 1, 3 do
    test.socket.matter:__queue_receive(report(attr, other))
    expect_write(attr, wanted)
    test.wait_for_events()
  end
  expect_no_write(attr, other)
end

test.register_coroutine_test(
  "The first and later tempOffset changes should re-read only the temperature",
  function()
    test.socket.device_lifecycle:__queue_receive(preference("tempOffset", "1"))
    test.socket.matter:__expect_send({mock_device.id, clusters.TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)})
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(preference("tempOffset", "2"))
    test.socket.matter:__expect_send({mock_device.id, clusters.TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)})
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(preference("tempOffset", "2"))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "The first and later humidityOffset changes should re-read only the humidity",
  function()
    test.socket.device_lifecycle:__queue_receive(preference("humidityOffset", "-3"))
    test.socket.matter:__expect_send({mock_device.id, clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:read(mock_device)})
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(preference("humidityOffset", "2"))
    test.socket.matter:__expect_send({mock_device.id, clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:read(mock_device)})
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "A sensitivity change should write the operation mode on EP1 and read it back",
  function()
    test.socket.device_lifecycle:__queue_receive(preference("stse.sensitivity", "3"))
    expect_write(MODE, 3)
    test.wait_for_events()
    expect_no_write(MODE, 3)
    test.socket.device_lifecycle:__queue_receive(preference("stse.sensitivity", "1"))
    expect_write(MODE, 1)
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "A sensitivity that maps to the current target should not be written",
  function()
    test.socket.device_lifecycle:__queue_receive(preference("stse.sensitivity", "2"))
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(preference("stse.sensitivity", "3"))
    expect_write(MODE, 3)
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(preference("stse.sensitivity", "3"))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "A sensitivity outside 1..3 should be clamped",
  function()
    test.socket.device_lifecycle:__queue_receive(preference("stse.sensitivity", "5"))
    expect_write(MODE, 3)
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(preference("stse.sensitivity", "0"))
    expect_write(MODE, 1)
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "A write that does not take should be retried three times, then given up",
  function()
    test.socket.device_lifecycle:__queue_receive(preference("stse.sensitivity", "3"))
    expect_write(MODE, 3)
    test.wait_for_events()
    expect_rewrites_then_give_up(MODE, 3, 2)
  end
)

test.register_coroutine_test(
  "A new setting after giving up should be written and retried again",
  function()
    test.socket.device_lifecycle:__queue_receive(preference("stse.sensitivity", "3"))
    expect_write(MODE, 3)
    test.wait_for_events()
    expect_rewrites_then_give_up(MODE, 3, 2)
    test.socket.device_lifecycle:__queue_receive(preference("stse.sensitivity", "1"))
    expect_write(MODE, 1)
    test.wait_for_events()
    test.socket.matter:__queue_receive(report(MODE, 2))
    expect_write(MODE, 1)
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "A value written by another controller should be left alone",
  function()
    expect_no_write(MODE, 3)
    test.socket.device_lifecycle:__queue_receive(preference("stse.sensitivity", "1"))
    expect_write(MODE, 1)
    test.wait_for_events()
    expect_no_write(MODE, 1)
    expect_no_write(MODE, 3)
  end
)

if HOLD_TIME ~= nil then
  test.register_coroutine_test(
    "A presence hold time change should write HoldTime as 20 s plus the setting on EP1 and read it back",
    function()
      test.socket.device_lifecycle:__queue_receive(preference("stse.presenceHoldTime", "60"))
      expect_write(HOLD_TIME, 80)
      test.wait_for_events()
      expect_no_write(HOLD_TIME, 80)
      expect_no_write(HOLD_TIME, 120)
      test.socket.device_lifecycle:__queue_receive(preference("stse.presenceHoldTime", "5"))
      expect_write(HOLD_TIME, 25)
      test.wait_for_events()
    end
  )

  test.register_coroutine_test(
    "The default presence hold time of 0 should not be written, the device already holds 20 s",
    function()
      test.socket.device_lifecycle:__queue_receive(preference("stse.presenceHoldTime", "0"))
      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(preference("stse.presenceHoldTime", "30"))
      expect_write(HOLD_TIME, 50)
      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(preference("stse.presenceHoldTime", "0"))
      expect_write(HOLD_TIME, 20)
      test.wait_for_events()
    end
  )

  test.register_coroutine_test(
    "A numeric or fractional presence hold time should be written as whole seconds",
    function()
      test.socket.device_lifecycle:__queue_receive(preference("stse.presenceHoldTime", 15))
      expect_write(HOLD_TIME, 35)
      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(preference("stse.presenceHoldTime", 30.0))
      expect_write(HOLD_TIME, 50)
      test.wait_for_events()
    end
  )

  test.register_coroutine_test(
    "A presence hold time outside 0..280 s should be clamped so HoldTime stays within 20..300 s",
    function()
      test.socket.device_lifecycle:__queue_receive(preference("stse.presenceHoldTime", "600"))
      expect_write(HOLD_TIME, 300)
      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(preference("stse.presenceHoldTime", "-5"))
      expect_write(HOLD_TIME, 20)
      test.wait_for_events()
    end
  )

  test.register_coroutine_test(
    "A HoldTime write that does not take should be retried three times, then given up",
    function()
      test.socket.device_lifecycle:__queue_receive(preference("stse.presenceHoldTime", "60"))
      expect_write(HOLD_TIME, 80)
      test.wait_for_events()
      expect_rewrites_then_give_up(HOLD_TIME, 80, 10)
    end
  )
end

test.run_registered_tests()
