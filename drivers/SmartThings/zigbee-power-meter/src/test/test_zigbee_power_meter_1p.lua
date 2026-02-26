local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"


-- Mock out globals
local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("power-meter-1p.yml"),
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "BITUO TECHNIK",
      model = "SPM01X",
      server_clusters = {SimpleMetering.ID, ElectricalMeasurement.ID}
    }
  }
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "SimpleMetering event should be handled by powerConsumptionReport capability",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(15*60, "oneshot")
      -- #1 : 15 minutes have passed
      test.mock_time.advance_time(15*60)
      test.socket.zigbee:__queue_receive({
                                          mock_device.id,
                                          SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device,150)
                                        })
      test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({energy = 1500.0, deltaEnergy = 0.0 }))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 1.5, unit = "kWh"}))
      )
      -- #2 : Not even 15 minutes passed
      test.wait_for_events()
      test.mock_time.advance_time(1*60)
      test.socket.zigbee:__queue_receive({
                                          mock_device.id,
                                          SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device,170)
                                        })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 1.7, unit = "kWh"}))
      )
      -- #3 : 15 minutes have passed
      test.wait_for_events()
      test.mock_time.advance_time(14*60)
      test.socket.zigbee:__queue_receive({
                                          mock_device.id,
                                          SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device,200)
                                         })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({energy = 2000.0, deltaEnergy = 500.0 }))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 2.0, unit = "kWh"}))
      )
    end,
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "ActivePower Report should be handled. Sensor value is in W, capability attribute value is in hectowatts",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_device,
                                                                                                        27) },
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("PhaseA", capabilities.powerMeter.power({ value = 27.0, unit = "W" }))
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "ActivePower Report should be handled. Sensor value is in W, capability attribute value is in hectowatts",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_device,
                                                                                                        27) },
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("PhaseA", capabilities.powerMeter.power({ value = 27.0, unit = "W" }))
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
  "RMSCurrent Report for PhaseA should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, ElectricalMeasurement.attributes.RMSCurrent:build_test_attr_report(mock_device,
                                                                                                      34) },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("PhaseA", capabilities.currentMeasurement.current({ value = 0.34, unit = "A" }))
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "RMSVoltage Report for PhaseA should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, ElectricalMeasurement.attributes.RMSVoltage:build_test_attr_report(mock_device,
                                                                                                      22000) },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("PhaseA", capabilities.voltageMeasurement.voltage({ value = 220.0, unit = "V" }))
    }
  },
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device configure lifecycle event should configure device properly",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, SimpleMetering.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, ElectricalMeasurement.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 30, 120, 0)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.ActivePower:configure_reporting(mock_device, 30, 120, 0)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.RMSVoltage:configure_reporting(mock_device, 30, 120, 0)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.RMSCurrent:configure_reporting(mock_device, 30, 120, 0)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.configure_reporting(mock_device, data_types.ClusterId(SimpleMetering.ID), data_types.AttributeId(0x0001), data_types.ZigbeeDataType(SimpleMetering.attributes.CurrentSummationDelivered.base_type.ID), 30, 120, 0)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.ACPowerDivisor:configure_reporting(mock_device, 1, 43200, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      SimpleMetering.attributes.InstantaneousDemand:configure_reporting(mock_device, 5, 3600, 5)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.ACPowerMultiplier:configure_reporting(mock_device, 1, 43200, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      SimpleMetering.attributes.InstantaneousDemand:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.read_attribute(mock_device, data_types.ClusterId(SimpleMetering.ID), data_types.AttributeId(0x0001))
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.ActivePower:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.RMSVoltage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.RMSCurrent:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_device)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()