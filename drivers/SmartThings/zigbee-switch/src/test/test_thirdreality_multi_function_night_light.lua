local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local OnOff = clusters.OnOff
local IlluminanceMeasurement = clusters.IlluminanceMeasurement
local THIRDREALITY_MOTION_CLUSTER = 0xFC00
local MOTION_DETECT = 0x0001
local MOTION_NO_DETECT = 0x0000

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("on-off-level-rgbw-motion-sensor"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Third Reality, Inc",
        model = "3RSNL02043Z",
        server_clusters = { 0x0000, 0x0006, 0x0008, 0x0300, 0x0400, 0xFC00 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Reported on off status should be handled: on",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                                true) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: off",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_device,
                                                                                                false) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
  "Reported motion should be handled: active",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, THIRDREALITY_MOTION_CLUSTER.attributes.PresentValue:build_test_attr_report(mock_device, MOTION_DETECT) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    }
  }
)

test.register_message_test(
  "Reported motion should be handled: inactive",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, THIRDREALITY_MOTION_CLUSTER.attributes.PresentValue:build_test_attr_report(mock_device, MOTION_NO_DETECT) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    }
  }
)

test.register_message_test(
  "Illuminance report should be handled",
  {
     {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_device.id,
          IlluminanceMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 21370)
        }
     },
     {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({ value = 137 }))
     }
  }
)


test.run_registered_tests()
