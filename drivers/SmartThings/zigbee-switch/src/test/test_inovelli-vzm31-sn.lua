-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local BasicCluster = clusters.Basic
local OnOffCluster = clusters.OnOff
local LevelCluster = clusters.Level
local SimpleMeteringCluster = clusters.SimpleMetering
local ElectricalMeasurementCluster = clusters.ElectricalMeasurement
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local data_types = require "st.zigbee.data_types"
local utils = require "st.utils"

local PRIVATE_CLUSTER_ID = 0xFC31
local PRIVATE_CMD_NOTIF_ID = 0x01
local PRIVATE_CMD_SCENE_ID =0x00
local MFG_CODE = 0x122F

local parent_profile = t_utils.get_profile_definition("inovelli-vzm31-sn.yml")
local child_profile = t_utils.get_profile_definition("rgbw-bulb-2700K-6500K.yml")

local mock_device = test.mock_device.build_test_zigbee_device({
  label = "Inovelli 2-in-1 Blue Series",
  profile = parent_profile,
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "Inovelli",
      model = "VZM31-SN",
      server_clusters = { 0x0000, 0x0006, 0x0008, 0x0702, 0x0B04 },
    },
    [2] = {
      id = 2,
      manufacturer = "Inovelli",
      model = "VZM31-SN",
      server_clusters = { 0x0006 },
    },
    [3] = {
      id = 3,
      manufacturer = "Inovelli",
      model = "VZM31-SN",
      server_clusters = { 0x0006 },
    },
    [4] = {
      id = 4,
      manufacturer = "Inovelli",
      model = "VZM31-SN",
      server_clusters = { 0x0006 },
    },
  },
  fingerprinted_endpoint_id = 0x01
})

local mock_first_child = test.mock_device.build_test_child_device({
  profile = child_profile,
  device_network_id = string.format("%04X:%02X", mock_device:get_short_address(), 2),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  mock_device:set_field("_configuration_version", 1, {persist = true})
  test.mock_device.add_test_device(mock_device)
  test.socket.capability:__set_channel_ordering("relaxed")
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switchLevel.level(0)))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.powerMeter.power(0)))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.energyMeter.energy(0)))
  test.socket.capability:__expect_send(mock_device:generate_test_message("button1", capabilities.button.supportedButtonValues({"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"}, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("button2", capabilities.button.supportedButtonValues({"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"}, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("button3", capabilities.button.supportedButtonValues({"pushed","held","down_hold","pushed_2x","pushed_3x","pushed_4x","pushed_5x"}, { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("button1", capabilities.button.numberOfButtons({ value = 1 },    { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("button2", capabilities.button.numberOfButtons({ value = 1 },    { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("button3", capabilities.button.numberOfButtons({ value = 1 },    { visibility = { displayed = false } })))

  test.socket.zigbee:__expect_send({mock_device.id, BasicCluster.attributes.SWBuildID:read(mock_device)})

  test.mock_device.add_test_device(mock_first_child)
  test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.colorControl.hue(1)))
  test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.colorControl.saturation(1)))
  test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.colorTemperature.colorTemperature(6500)))
  test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.switchLevel.level(100)))
  test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.switch.switch.off()))

end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "lifecycle configure event should configure device",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         LevelCluster.attributes.CurrentLevel:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMeteringCluster.attributes.InstantaneousDemand:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMeteringCluster.attributes.CurrentSummationDelivered:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMeteringCluster.attributes.Multiplier:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMeteringCluster.attributes.Divisor:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurementCluster.attributes.ActivePower:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurementCluster.attributes.ACPowerMultiplier:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurementCluster.attributes.ACPowerDivisor:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:read(mock_device):to_endpoint(0x02)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:read(mock_device):to_endpoint(0x03)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:read(mock_device):to_endpoint(0x04)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:configure_reporting(mock_device, 0, 300):to_endpoint(1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:configure_reporting(mock_device, 0, 300):to_endpoint(2)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:configure_reporting(mock_device, 0, 300):to_endpoint(3)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         OnOffCluster.attributes.OnOff:configure_reporting(mock_device, 0, 300):to_endpoint(4)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         LevelCluster.attributes.CurrentLevel:configure_reporting(mock_device, 1, 3600, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMeteringCluster.attributes.InstantaneousDemand:configure_reporting(mock_device, 5, 3600, 5)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMeteringCluster.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 5, 3600, 1)
                                       })

      test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        ElectricalMeasurementCluster.attributes.ACPowerMultiplier:configure_reporting(mock_device, 1, 43200, 1)
                                      })
      test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        ElectricalMeasurementCluster.attributes.ACPowerDivisor:configure_reporting(mock_device, 1, 43200, 1)
                                      })
      test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        ElectricalMeasurementCluster.attributes.ActivePower:configure_reporting(mock_device, 5, 3600, 5)
                                      })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         BasicCluster.attributes.SWBuildID:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              ElectricalMeasurementCluster.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              SimpleMeteringCluster.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              LevelCluster.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              OnOffCluster.ID, 1):to_endpoint(1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              OnOffCluster.ID, 2):to_endpoint(2)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              OnOffCluster.ID, 3):to_endpoint(3)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              OnOffCluster.ID, 4):to_endpoint(4)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              PRIVATE_CLUSTER_ID, 2)
                                        })
      test.socket.zigbee:__expect_send({
                                       mock_device.id,
                                       cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 21, MFG_CODE)
                                     })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurementCluster.attributes.ACPowerDivisor:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurementCluster.attributes.ACPowerMultiplier:read(mock_device)
                                       })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
  "parameter258 in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["parameter258"] = "0" }
    }))
    test.mock_time.advance_time(3)
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 258,
        MFG_CODE, data_types.Boolean, false) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      BasicCluster.attributes.SWBuildID:read(mock_device) })
  end
)

test.register_coroutine_test(
  "parameter22 in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["parameter22"] = "0" }
    }))
    test.mock_time.advance_time(3)
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 22,
        MFG_CODE, data_types.Uint8, 0) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      BasicCluster.attributes.SWBuildID:read(mock_device) })
  end
)


test.register_message_test(
  "Capability on command switch on should be handled : parent device",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "on", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOffCluster.server.commands.On(mock_device) }
    }
  }
)

test.register_coroutine_test(
  "Capability on command switch on should be handled : child device",
  function()
    test.socket.capability:__queue_receive({mock_first_child.id, { capability = "switch", component = "main", command = "on", args = {}}})
    test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.switch.switch.on()))
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.wait_for_events()
    test.mock_time.advance_time(60 * 1)
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.build_manufacturer_specific_command(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_CMD_NOTIF_ID, MFG_CODE, utils.serialize_int(16803071,4,false,false)) })
  end
)

test.register_message_test(
  "Capability off command switch on should be handled : parent device",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switch", component = "main", command = "off", args = { } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, OnOffCluster.server.commands.Off(mock_device) }
    }
  }
)

test.register_coroutine_test(
  "Capability on command switch on should be handled : child device",
  function()
    test.socket.capability:__queue_receive({mock_first_child.id, { capability = "switch", component = "main", command = "off", args = {}}})
    test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.switch.switch.off()))
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.wait_for_events()
    test.mock_time.advance_time(60 * 1)
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.build_manufacturer_specific_command(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_CMD_NOTIF_ID, MFG_CODE, utils.serialize_int(0,4,false,false)) })
  end
)


test.register_message_test(
  "Capability setLevel command switch on should be handled : parent device",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 57, 0 } } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, LevelCluster.server.commands.MoveToLevelWithOnOff(mock_device,
                                                                               math.floor(57 * 0xFE / 100),
                                                                               0) }
    }
  }
)

test.register_coroutine_test(
  "Capability setLevel command switch on should be handled : child device",
  function()
    test.socket.capability:__queue_receive({mock_first_child.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 57, 0 }}})
    test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.switchLevel.level(57)))
    test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.switch.switch.on()))
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.wait_for_events()
    test.mock_time.advance_time(60 * 1)
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.build_manufacturer_specific_command(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_CMD_NOTIF_ID, MFG_CODE, utils.serialize_int(16792063,4,false,false)) })
  end
)


test.register_coroutine_test(
  "Capability setColorTemperature command switch on should be handled : child device",
  function()
    test.socket.capability:__queue_receive({mock_first_child.id, { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = { 1800 }}})
    test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.colorControl.hue(100)))
    test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.colorTemperature.colorTemperature(1800)))
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.wait_for_events()
    test.mock_time.advance_time(60 * 1)
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.build_manufacturer_specific_command(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_CMD_NOTIF_ID, MFG_CODE, utils.serialize_int(33514751,4,false,false)) })
  end
)

test.register_coroutine_test(
  "Capability setColor command switch on should be handled : child device",
  function()
    test.socket.capability:__queue_receive({mock_first_child.id, { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 50, saturation = 50 } }}})
    test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.colorControl.hue(50)))
    test.socket.capability:__expect_send(mock_first_child:generate_test_message("main", capabilities.colorControl.saturation(50)))
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.wait_for_events()
    test.mock_time.advance_time(60 * 1)
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.build_manufacturer_specific_command(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_CMD_NOTIF_ID, MFG_CODE, utils.serialize_int(25191679,4,false,false)) })
  end
)

local ENDPOINT = 0x01
local FRAME_CTRL = 0x1D
local PROFILE_ID = 0x0104

local build_scene_message = function(device, payload)
  local message = zigbee_test_utils.build_custom_command_id(
          device,
          PRIVATE_CLUSTER_ID,
          PRIVATE_CMD_SCENE_ID,
          MFG_CODE,
          payload,
          ENDPOINT
  )

  message.body.zcl_header.frame_ctrl.value = FRAME_CTRL
  message.address_header.profile.value = PROFILE_ID

  return message
end

test.register_coroutine_test(
  "Reported private cluster should be handled",
  function()
      test.socket.zigbee:__queue_receive({
        mock_device.id,
        build_scene_message(mock_device, "\x01\x01")
      })
    test.socket.capability:__expect_send(mock_device:generate_test_message("button1", capabilities.button.button.held({state_change = true})))
  end
)

test.register_coroutine_test(
  "Handle Power meter",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      SimpleMeteringCluster.attributes.InstantaneousDemand:build_test_attr_report(mock_device, 60)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 6.0, unit = "W" }))
    )

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      ElectricalMeasurementCluster.attributes.ActivePower:build_test_attr_report(mock_device, 100)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 10.0, unit = "W" }))
    )
  end
)

test.register_coroutine_test(
  "Handle Energy meter",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      SimpleMeteringCluster.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 600)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 6.0, unit = "kWh" }))
    )
  end
)

test.run_registered_tests()
