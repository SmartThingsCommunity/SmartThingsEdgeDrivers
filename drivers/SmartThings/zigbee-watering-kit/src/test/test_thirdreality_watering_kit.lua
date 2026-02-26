local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"

local IASZone = clusters.IASZone
local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration

local THIRDREALITY_WATERING_CLUSTER = 0xFFF2
local WATERING_TIME_ATTR = 0x0000
local WATERING_INTERVAL_ATTR = 0x0001

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("watering-kit-thirdreality.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Third Reality, Inc",
        model = "3RWK0148Z",
        server_clusters = {0x0001, 0x0006, 0x0500, 0xFFF2}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "lifecycle - added test",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.hardwareFault.hardwareFault.clear()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.fanSpeed.fanSpeed(10)))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.mode.mode("0")))
  end,
  {
     min_api_version = 19
  }
)

test.register_message_test(
    "Battery percentage report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 100) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(50))
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Reported on off status should be handled <receive from device>: on",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device, true) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Reported on off status should be handled <receive from device>: off",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device, false) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    " Switch OnOff command <send to device> : On ",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "switch", component = "main", command = "on", args = {} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.On(mock_device) }
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    " Switch OnOff command <send to device> : Off ",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "switch", component = "main", command = "off", args = {} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, OnOff.server.commands.Off(mock_device) }
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
  "Reported hardwareFault should be handled: detected",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0001) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.hardwareFault.hardwareFault.detected())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Reported hardwareFault should be handled: clear",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0000) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.hardwareFault.hardwareFault.clear())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "fanspeed reported should be handled: 10",
  function()
    local attr_report_data = {
      { WATERING_TIME_ATTR, data_types.Uint16.ID, 10}
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, THIRDREALITY_WATERING_CLUSTER, attr_report_data, 0x1407)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.fanSpeed.fanSpeed(10)))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "fanspeed reported should be handled: 30",
  function()
    local attr_report_data = {
      { WATERING_TIME_ATTR, data_types.Uint16.ID, 30}
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, THIRDREALITY_WATERING_CLUSTER, attr_report_data, 0x1407)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.fanSpeed.fanSpeed(30)))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "mode reported should be handled: 4",
  function()
    local attr_report_data = {
      { WATERING_INTERVAL_ATTR, data_types.OctetString.ID, "4"}
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, THIRDREALITY_WATERING_CLUSTER, attr_report_data, 0x1407)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.mode.mode("4")))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "setFanSpeed: 20",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "fanSpeed", component = "main", command = "setFanSpeed", args = { 20 } } })
    test.socket.zigbee:__expect_send({ mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device,
    THIRDREALITY_WATERING_CLUSTER, WATERING_TIME_ATTR, 0x1407, data_types.Uint16, 20) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "setMode: 2",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "mode", component = "main", command = "setMode", args = { "2" } } })
    test.socket.zigbee:__expect_send({ mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device,
    THIRDREALITY_WATERING_CLUSTER, WATERING_INTERVAL_ATTR, 0x1407, data_types.Uint8, 2) })
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
