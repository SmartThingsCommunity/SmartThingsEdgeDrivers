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

local test = require "integration_test"
local cluster_base = require "st.zigbee.cluster_base"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0xFFF1
local MFG_CODE = 0x115F

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-pet-feeder.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "",
        model = "aqara.feeder.acn001",
        server_clusters = { PRIVATE_CLUSTER_ID }
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
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.zigbee:__expect_send({ mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device,
      PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.OctetString, "\x00\x02\x01\x04\x18\x00\x55\x01\x00") })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.feederOperatingState.feederOperatingState("idle")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.feederPortion.feedPortion({value=1, unit="servings"})))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.powerSource.powerSource("dc")))
  end
)

test.register_coroutine_test(
  "refresh test",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.feederPortion.feedPortion({value=0, unit="servings"})))
    test.socket.zigbee:__expect_send({ mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device,
      PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.OctetString, "\x00\x05\x01\x08\x00\x07\xD1\x01\x00") })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.feederOperatingState.feederOperatingState("idle")))
  end
)

test.register_coroutine_test(
  "preference - handle Button Lock Setting in inforchanged",
  function()
    local updates = {
      preferences = {
        ["stse.buttonLock"] = true
      }
    }
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device,
      PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.OctetString, "\x00\x02\x01\x04\x16\x00\x55\x01\x01") })
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    -- No events should be emitted
    updates.preferences["stse.buttonLock"] = false
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device,
      PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.OctetString, "\x00\x02\x02\x04\x16\x00\x55\x01\x00") })
  end
)

test.register_coroutine_test(
  "power source - connecting the DC adapter",
  function()
    local attr_report_data = {
      { PRIVATE_ATTRIBUTE_ID, data_types.OctetString.ID, "\x00\x05\x01\x0D\x09\x00\x55\x01\x00" }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.powerSource.powerSource("dc")))
  end
)

test.register_coroutine_test(
  "power source - connecting the battery",
  function()
    local attr_report_data = {
      { PRIVATE_ATTRIBUTE_ID, data_types.OctetString.ID, "\x00\x05\x01\x0D\x09\x00\x55\x01\x01" }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.powerSource.powerSource("battery")))
  end
)

test.register_coroutine_test(
  "click the feeding physical button",
  function()
    mock_device:set_field("FeedingSource", 0)
    local attr_report_data = {
      { PRIVATE_ATTRIBUTE_ID, data_types.OctetString.ID, "\x00\x05\x33\x0D\x68\x00\x55\x02\x00\x06" }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.feederOperatingState.feederOperatingState("feeding")))
  end
)

test.register_coroutine_test(
  "feederOperatingState capability - click the feeding button",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "feederOperatingState", component = "main", command = "startFeeding", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device,
      PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.OctetString, "\x00\x02\x01\x04\x15\x00\x55\x01\x01") })
  end
)

test.register_coroutine_test(
  "feederOperatingState capability - feeding state",
  function()
    local attr_report_data = {
      { PRIVATE_ATTRIBUTE_ID, data_types.OctetString.ID, "\x00\x05\x01\x04\x15\x00\x55\x01\x01" }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    mock_device:set_field("FeedingSource", 1)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.feederOperatingState.feederOperatingState("feeding")))
  end
)

test.register_coroutine_test(
  "feederOperatingState capability - idle state",
  function()
    local feed_timer = 1
    test.timer.__create_and_queue_test_time_advance_timer(feed_timer, "oneshot")
    local attr_report_data = {
      { PRIVATE_ATTRIBUTE_ID, data_types.OctetString.ID, "\x00\x05\x01\x0D\x68\x00\x55\x02\x00\x06" }
    }
    mock_device:set_field("FeedingSource", 1)
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.mock_time.advance_time(feed_timer)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.feederOperatingState.feederOperatingState("idle")))
  end
)

test.register_coroutine_test(
  "feederPortion capability - set the portion(in serving) that will dispense",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "feederPortion", component = "main", command = "setPortion", args = { 5 } } })
    test.socket.zigbee:__expect_send({ mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device,
      PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.OctetString, "\x00\x02\x01\x0E\x5C\x00\x55\x04\x00\x00\x00\x05") })
  end
)

test.register_coroutine_test(
  "feederPortion capability - portion settings event handling",
  function()
    local attr_report_data = {
      { PRIVATE_ATTRIBUTE_ID, data_types.OctetString.ID, "\x00\x02\x01\x0E\x5C\x00\x55\x01\x05" }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.feederPortion.feedPortion({value=5, unit="servings"})))
  end
)

test.run_registered_tests()
