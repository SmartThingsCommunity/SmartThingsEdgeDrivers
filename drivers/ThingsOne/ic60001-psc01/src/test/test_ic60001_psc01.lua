-- Copyright 2026 Samjin
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local t_utils = require "integration_test.utils"

-- Endpoints as the IC60001-PSC01 firmware exposes them
local matter_endpoints = {
  {
    endpoint_id = 0,
    clusters = {
      {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
    },
    device_types = {
      {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
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
  {
    endpoint_id = 5,
    clusters = {
      {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY},
    },
    device_types = {
      {device_type_id = 0x0011, device_type_revision = 1} -- PowerSource
    }
  },
}

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("ic60001-psc01.yml"),
  manufacturer_info = {vendor_id = 0x1241, product_id = 0x8010},
  endpoints = matter_endpoints
})

local function subscribe_on_init(dev)
  local subscribe_request = clusters.OccupancySensing.attributes.Occupancy:subscribe(dev)
  subscribe_request:merge(clusters.TemperatureMeasurement.attributes.MeasuredValue:subscribe(dev))
  subscribe_request:merge(clusters.IlluminanceMeasurement.attributes.MeasuredValue:subscribe(dev))
  subscribe_request:merge(clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:subscribe(dev))
  subscribe_request:merge(clusters.PowerSource.attributes.BatPercentRemaining:subscribe(dev))
  subscribe_request:merge(clusters.OccupancySensing.attributes.PIRUnoccupiedToOccupiedThreshold:subscribe(dev))
  return subscribe_request
end

local function test_init()
  test.socket.matter:__expect_send({mock_device.id, subscribe_on_init(mock_device)})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local function occupancy_report(value)
  return {mock_device.id, clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 1, value)}
end

local function presence(value)
  return mock_device:generate_test_message("main", capabilities.presenceSensor.presence(value))
end

test.register_coroutine_test(
  "Occupancy 1 should report present at once",
  function()
    test.socket.matter:__queue_receive(occupancy_report(1))
    test.socket.capability:__expect_send(presence("present"))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Occupancy 0 in an empty room should report not present at once",
  function()
    test.socket.matter:__queue_receive(occupancy_report(0))
    test.socket.capability:__expect_send(presence("not present"))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Occupancy 0 after present should wait the default 10 s off delay",
  function()
    test.socket.matter:__queue_receive(occupancy_report(1))
    test.socket.capability:__expect_send(presence("present"))
    test.wait_for_events()
    test.timer.__create_and_queue_test_time_advance_timer(10, "oneshot")
    test.socket.matter:__queue_receive(occupancy_report(0))
    test.wait_for_events()
    test.mock_time.advance_time(10)
    test.socket.capability:__expect_send(presence("not present"))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Occupancy 1 within the off delay should cancel not present",
  function()
    test.socket.matter:__queue_receive(occupancy_report(1))
    test.socket.capability:__expect_send(presence("present"))
    test.wait_for_events()
    test.timer.__create_and_queue_test_time_advance_timer(10, "oneshot")
    test.socket.matter:__queue_receive(occupancy_report(0))
    test.wait_for_events()
    test.socket.matter:__queue_receive(occupancy_report(1))
    test.socket.capability:__expect_send(presence("present"))
    test.wait_for_events()
    test.mock_time.advance_time(10)
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "The offDelay preference should set the wait",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({preferences = {["publicguide63260.offDelay"] = "30"}}))
    test.wait_for_events()
    test.socket.matter:__queue_receive(occupancy_report(1))
    test.socket.capability:__expect_send(presence("present"))
    test.wait_for_events()
    test.timer.__create_and_queue_test_time_advance_timer(30, "oneshot")
    test.socket.matter:__queue_receive(occupancy_report(0))
    test.wait_for_events()
    test.mock_time.advance_time(30)
    test.socket.capability:__expect_send(presence("not present"))
    test.wait_for_events()
  end
)

test.register_message_test(
  "Temperature reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.attributes.MeasuredValue:build_test_report_data(mock_device, 2, 2650)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 26.5, unit = "C"}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.attributes.MeasuredValue:build_test_report_data(mock_device, 2, -1050)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = -10.5, unit = "C"}))
    }
  }
)

test.register_message_test(
  "Illuminance reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.IlluminanceMeasurement.attributes.MeasuredValue:build_test_report_data(mock_device, 3, 21370)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({value = 137}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.IlluminanceMeasurement.attributes.MeasuredValue:build_test_report_data(mock_device, 3, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({value = 0}))
    }
  }
)

test.register_message_test(
  "Relative humidity reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:build_test_report_data(mock_device, 4, 4049)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({value = 40}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:build_test_report_data(mock_device, 4, 4050)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({value = 41}))
    }
  }
)

test.register_message_test(
  "Battery percent reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(mock_device, 5, 151)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(76))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(mock_device, 5, 200)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
    }
  }
)

local function refresh_commands(dev)
  local req = clusters.OccupancySensing.attributes.Occupancy:read(dev)
  req:merge(clusters.TemperatureMeasurement.attributes.MeasuredValue:read(dev))
  req:merge(clusters.IlluminanceMeasurement.attributes.MeasuredValue:read(dev))
  req:merge(clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:read(dev))
  req:merge(clusters.PowerSource.attributes.BatPercentRemaining:read(dev))
  req:merge(clusters.OccupancySensing.attributes.PIRUnoccupiedToOccupiedThreshold:read(dev))
  return req
end

test.register_message_test(
  "Refresh should read every subscribed attribute",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        {capability = "refresh", component = "main", command = "refresh", args = {}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        refresh_commands(mock_device)
      }
    }
  }
)

test.register_coroutine_test(
  "A tempOffset change should re-read only the temperature",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({preferences = {tempOffset = "1"}}))
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({preferences = {tempOffset = "2"}}))
    test.socket.matter:__expect_send({mock_device.id, clusters.TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)})
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "A humidityOffset change should re-read only the humidity",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({preferences = {humidityOffset = "0"}}))
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({preferences = {humidityOffset = "-3"}}))
    test.socket.matter:__expect_send({mock_device.id, clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:read(mock_device)})
    test.wait_for_events()
  end
)

local MODE = clusters.OccupancySensing.attributes.PIRUnoccupiedToOccupiedThreshold

local function sensitivity(value)
  return mock_device:generate_info_changed({preferences = {motionSensitivity = value}})
end

local function expect_mode_write(mode)
  test.socket.matter:__expect_send({mock_device.id, MODE:write(mock_device, 1, mode)})
  test.socket.matter:__expect_send({mock_device.id, MODE:read(mock_device)})
end

local function mode_report(mode)
  return {mock_device.id, MODE:build_test_report_data(mock_device, 1, mode)}
end

test.register_coroutine_test(
  "A motionSensitivity change should write the mode on EP1 and read it back",
  function()
    test.socket.device_lifecycle:__queue_receive(sensitivity("3"))
    expect_mode_write(3)
    test.wait_for_events()
    test.socket.matter:__queue_receive(mode_report(3))
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(sensitivity("1"))
    expect_mode_write(1)
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "motionSensitivity disabled (0) should write the lowest mode",
  function()
    test.socket.device_lifecycle:__queue_receive(sensitivity("0"))
    expect_mode_write(1)
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "A repeated motionSensitivity should be written only once",
  function()
    test.socket.device_lifecycle:__queue_receive(sensitivity("2"))
    expect_mode_write(2)
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(sensitivity("2"))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "A device mode that differs from the setting should be rewritten, at most three times",
  function()
    test.socket.device_lifecycle:__queue_receive(sensitivity("3"))
    expect_mode_write(3)
    test.wait_for_events()
    for _ = 1, 3 do
      test.socket.matter:__queue_receive(mode_report(2))
      expect_mode_write(3)
      test.wait_for_events()
    end
    test.socket.matter:__queue_receive(mode_report(2))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "With no setting yet, the motionSensitivity default 2 should be enforced",
  function()
    test.socket.matter:__queue_receive(mode_report(3))
    expect_mode_write(2)
    test.wait_for_events()
    test.socket.matter:__queue_receive(mode_report(2))
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "A further 0 during the off delay should keep the original deadline",
  function()
    test.socket.matter:__queue_receive(occupancy_report(1))
    test.socket.capability:__expect_send(presence("present"))
    test.wait_for_events()
    test.timer.__create_and_queue_test_time_advance_timer(10, "oneshot")
    test.socket.matter:__queue_receive(occupancy_report(0))
    test.wait_for_events()
    test.mock_time.advance_time(5)
    test.socket.matter:__queue_receive(occupancy_report(0))
    test.wait_for_events()
    test.mock_time.advance_time(5)
    test.socket.capability:__expect_send(presence("not present"))
    test.wait_for_events()
  end
)

test.run_registered_tests()
