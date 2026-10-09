-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"

--If this line is removed, an error will occur.
test.add_package_capability("sensitivityAdjustment.yaml")

local sensitivityAdjustment = capabilities["stse.sensitivityAdjustment"]
local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration

local PREF_SENSITIVITY_VALUE_HIGH = 3
local PREF_SENSITIVITY_VALUE_MEDIUM = 2
local PREF_SENSITIVITY_VALUE_LOW = 1
local IASZone_PRIVATE_COMMAND_ID = 0xF4

-- Needed for building iaszone_private_cmd msg
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"

local zcl_messages = require "st.zigbee.zcl"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("motion-battery-illuminance-sensitivity-frequency-no-fw-update.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "MultIR",
        model = "MIR-IR100",
        server_clusters = { PowerConfiguration.ID ,IASZone.ID}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle added lifecycle",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.motionSensor.motion.inactive()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      sensitivityAdjustment.sensitivityAdjustment.High()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.battery.battery(100)))
    test.socket.zigbee:__expect_send({ mock_device.id,
      IASZone.attributes.CurrentZoneSensitivityLevel:read(mock_device)})
  end,
  {
     min_api_version = 19
  }
)

local function build_iaszone_private_cmd(device, priv_cmd, data)
  local frame_ctrl = FrameCtrl(0x00)
  frame_ctrl:set_cluster_specific()

  local zclh = zcl_messages.ZclHeader({
    frame_ctrl = frame_ctrl,
    cmd = data_types.ZCLCommandId(priv_cmd)
  })

  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = data_types.Uint16(data)
  })

  local addr_header = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(IASZone.ID),
    zb_const.HA_PROFILE_ID,
    IASZone.ID
  )

  local msg = messages.ZigbeeMessageTx({
    address_header = addr_header,
    body = message_body
  })

  return msg
end

test.register_coroutine_test(
  "Handle detectionFrequency preference in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({preferences = {detectionfrequency = 63}}))
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        build_iaszone_private_cmd(mock_device,IASZone_PRIVATE_COMMAND_ID, 63)
      }
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Reported CurrentZoneSensitivityLevel 1 should be Low",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.CurrentZoneSensitivityLevel:build_test_attr_report(mock_device,
                                                                                                1) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",  sensitivityAdjustment.sensitivityAdjustment.Low())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Reported CurrentZoneSensitivityLevel 2 should be Medium",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.CurrentZoneSensitivityLevel:build_test_attr_report(mock_device,
                                                                                                2) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",  sensitivityAdjustment.sensitivityAdjustment.Medium())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Reported CurrentZoneSensitivityLevel 3 should be High",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.CurrentZoneSensitivityLevel:build_test_attr_report(mock_device,
                                                                                                3) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",  sensitivityAdjustment.sensitivityAdjustment.High())
    }
  },
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Capability sensitivityAdjustment High should be handled",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "stse.sensitivityAdjustment", component = "main", command = "setSensitivityAdjustment", args = {"High"} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      IASZone.attributes.CurrentZoneSensitivityLevel:write(mock_device, PREF_SENSITIVITY_VALUE_HIGH) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      IASZone.attributes.CurrentZoneSensitivityLevel:read(mock_device) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Capability sensitivityAdjustment Medium should be handled",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "stse.sensitivityAdjustment", component = "main", command = "setSensitivityAdjustment", args = {"Medium"} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      IASZone.attributes.CurrentZoneSensitivityLevel:write(mock_device, PREF_SENSITIVITY_VALUE_MEDIUM) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      IASZone.attributes.CurrentZoneSensitivityLevel:read(mock_device) })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Capability sensitivityAdjustment Low should be handled",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "stse.sensitivityAdjustment", component = "main", command = "setSensitivityAdjustment", args = {"Low"} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      IASZone.attributes.CurrentZoneSensitivityLevel:write(mock_device, PREF_SENSITIVITY_VALUE_LOW) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      IASZone.attributes.CurrentZoneSensitivityLevel:read(mock_device) })
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
