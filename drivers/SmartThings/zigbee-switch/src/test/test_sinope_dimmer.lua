-- Copyright 2022 SmartThings
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

local base64 = require "st.base64"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local zcl_clusters = require "st.zigbee.zcl.clusters"
local Basic = zcl_clusters.Basic
local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff

local SINOPE_DIMMER_CLUSTER = 0xFF01
local SINOPE_MAX_INTENSITY_ON_ATTRIBUTE = 0x0052
local SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE = 0x0053
local SINOPE_MIN_LIGHT_INTENSITY_ATTRIBUTE = 0x0055

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("on-off-level-intensity.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Sinope Technologies",
          model = "DM2500ZB",
          server_clusters = {0xFF01, 0x0000, 0x0008, 0x0006}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "infochanged to check for necessary preferences settings or updated when ledIntensity and minimalIntensity preference settings are non-zero, with swBuild > 106",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

      local updates = {
        preferences = {
          minimalIntensity = 10,
          ledIntensity = 10
        }
      }

      test.socket.zigbee:__queue_receive({
          mock_device.id,
          Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device, 107)
        })

      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MIN_LIGHT_INTENSITY_ATTRIBUTE),
                data_types.validate_or_build_type(2250, data_types.Uint16, "payload"))})
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(updates.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(updates.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__set_channel_ordering("relaxed")

   end
  )

test.register_coroutine_test(
    "infochanged to check for necessary preferences settings or updated when ledIntensity and minimalIntensity preference settings are non-zero, with swBuild = 106",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

      local updates = {
        preferences = {
          minimalIntensity = 10,
          ledIntensity = 10
        }
      }

      test.socket.zigbee:__queue_receive({
          mock_device.id,
          Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device, 106)
        })

      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(updates.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(updates.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__set_channel_ordering("relaxed")

   end
  )
test.register_coroutine_test(
    "infochanged to check for necessary preferences settings or updated when ledIntensity and minimalIntensity preference settings are zero with swBuild > 106",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

      local updates = {
        preferences = {
          minimalIntensity = 0,
          ledIntensity = 0
        }
      }

      test.socket.zigbee:__queue_receive({
          mock_device.id,
          Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device, 107)
        })

      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MIN_LIGHT_INTENSITY_ATTRIBUTE),
                data_types.validate_or_build_type(600, data_types.Uint16, "payload"))})
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(updates.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(updates.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__set_channel_ordering("relaxed")

   end
  )

test.register_coroutine_test(
    "infochanged to check for necessary preferences settings or updated when ledIntensity and minimalIntensity preference settings are zero with swBuild = 106",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

      local updates = {
        preferences = {
          minimalIntensity = 0,
          ledIntensity = 0
        }
      }

      test.socket.zigbee:__queue_receive({
          mock_device.id,
          Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device, 106)
        })

      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(updates.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(updates.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__set_channel_ordering("relaxed")

   end
  )

test.register_coroutine_test(
    "infochanged to check for necessary preferences settings or updated when ledIntensity and minimalIntensity preference settings are not present with swBuild version > 106",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

      local updates = {
        preferences = {
        }
      }

      test.socket.zigbee:__queue_receive({
          mock_device.id,
          Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device, 107)
        })

      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MIN_LIGHT_INTENSITY_ATTRIBUTE),
                data_types.validate_or_build_type(600, data_types.Uint16, "payload"))})
      test.socket.zigbee:__set_channel_ordering("relaxed")

   end
  )

test.register_coroutine_test(
    "infochanged to check for necessary preferences settings or updated when ledIntensity and minimalIntensity preference settings are not present with swBuild version = 106. No commands are sent to driver",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

      local updates = {
        preferences = {
        }
      }

      test.socket.zigbee:__queue_receive({
          mock_device.id,
          Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device, 106)
        })

      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
      test.socket.zigbee:__set_channel_ordering("relaxed")

   end
  )

test.register_coroutine_test(
    "infochanged to check for necessary preferences settings or updated when ledIntensity preference setting is > 50 and minimalIntensity preference settings are zero",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

      local updates = {
        preferences = {
          minimalIntensity = 1,
          ledIntensity = 70
        }
      }

      test.socket.zigbee:__queue_receive({
          mock_device.id,
          Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device, 107)
        })

      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MIN_LIGHT_INTENSITY_ATTRIBUTE),
                data_types.validate_or_build_type(100, data_types.Uint16, "payload"))})
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(updates.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(updates.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__set_channel_ordering("relaxed")

   end
  )

test.register_coroutine_test(
    "infochanged to check for necessary preferences settings or updated when ledIntensity preference setting is > 50 and minimalIntensity preference settings are zero with swBuild version equal to 106",
    function()
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })

      local updates = {
        preferences = {
          minimalIntensity = 1,
          ledIntensity = 70
        }
      }

      test.socket.zigbee:__queue_receive({
          mock_device.id,
          Basic.attributes.ApplicationVersion:build_test_attr_report(mock_device, 106)
        })

      test.wait_for_events()
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(updates.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_attribute(mock_device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(updates.preferences.ledIntensity, data_types.Uint8, "payload"))})
      test.socket.zigbee:__set_channel_ordering("relaxed")

   end
  )

test.register_message_test(
    "Refresh should read all necessary attributes",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = {mock_device.id, "added"}
      },
      {
        channel = "capability",
        direction = "receive",
        message = {mock_device.id, {capability = "refresh", component = "main", command = "refresh", args = {}}}
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          OnOff.attributes.OnOff:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Level.attributes.CurrentLevel:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Basic.attributes.ApplicationVersion:read(mock_device)
        }
      },
    }
)

test.run_registered_tests()
