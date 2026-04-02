-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local constants = require "st.zigbee.constants"

local LAST_REPORT_TIME = "LAST_REPORT_TIME"

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("frient-power-meter-consumption-report.yml"),
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "Develco Products A/S",
      model = "EMIZB-132",
      server_clusters = {SimpleMetering.ID, ElectricalMeasurement.ID}
    }
  }
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  mock_device:set_field("_configuration_version", 1, {persist = true})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "frient device_init sets divisor fields",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
    test.wait_for_events()
  end
)

test.register_message_test(
        "Refresh should read all necessary attributes",
        {
            {
                channel = "capability",
                direction = "receive",
                message = { mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} }}
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id, SimpleMetering.attributes.InstantaneousDemand:read(mock_device) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id, ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_device) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id, ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_device) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = {
                    mock_device.id, ElectricalMeasurement.attributes.ActivePower:read(mock_device) }
            }
        },
        {
            inner_block_ordering = "relaxed"
        }
)

test.register_coroutine_test(
  "frient instantaneous demand report emits power",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Divisor:build_test_attr_report(mock_device, 1000) })
    test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Multiplier:build_test_attr_report(mock_device, 1) })
    test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.InstantaneousDemand:build_test_attr_report(mock_device, 40) })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 40.0, unit = "W" }))
    )
  end
)

test.register_coroutine_test(
  "frient current summation delivered emits energy and consumption report",
  function()
    local current_time = os.time() - 60 * 16
    mock_device:set_field(LAST_REPORT_TIME, current_time)

    test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Divisor:build_test_attr_report(mock_device, 1000) })
    test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Multiplier:build_test_attr_report(mock_device, 1) })
    test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 2700) })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 2700.0, unit = "Wh" }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({
          start = "1969-12-31T23:44:00Z",
          ["end"] = "1969-12-31T23:59:59Z",
          deltaEnergy = 0.0,
          energy = 2700.0
        })
      )
    )
  end
)

test.register_coroutine_test(
  "frient current summation delivered skips consumption report when interval is short",
  function()
    local current_time = os.time() - 60 * 14
    mock_device:set_field(LAST_REPORT_TIME, current_time)

    test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Divisor:build_test_attr_report(mock_device, 1000) })
    test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Multiplier:build_test_attr_report(mock_device, 1) })
    test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 2700) })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 2700.0, unit = "Wh" }))
    )
  end
)

test.register_coroutine_test(
  "frient divisor report updates divisor field",
  function()
    test.socket.zigbee:__queue_receive({ mock_device.id, SimpleMetering.attributes.Divisor:build_test_attr_report(mock_device, 0) })
    test.wait_for_events()
    assert(mock_device:get_field(constants.SIMPLE_METERING_DIVISOR_KEY) == 1000,
      "SIMPLE_METERING_DIVISOR_KEY should be 1000")
  end
)

test.register_coroutine_test(
  "frient lifecycle configure event should configure device",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, SimpleMetering.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      SimpleMetering.attributes.InstantaneousDemand:configure_reporting(mock_device, 5, 3600, 5)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 5, 3600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, ElectricalMeasurement.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.ActivePower:configure_reporting(mock_device, 5, 3600, 5)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.ACPowerMultiplier:configure_reporting(mock_device, 1, 43200, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.ACPowerDivisor:configure_reporting(mock_device, 1, 43200, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      SimpleMetering.attributes.Divisor:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      SimpleMetering.attributes.Multiplier:read(mock_device)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
     min_api_version = 17
  }
)

test.run_registered_tests()
