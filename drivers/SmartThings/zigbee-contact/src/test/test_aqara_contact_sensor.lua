-- Copyright 2024 SmartThings
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
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"

local IASZone = clusters.IASZone

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("contact-battery-profile.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.magnet.agl02",
        server_clusters = { 0x0000, 0x0001, 0x0003, 0x0500 }
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
  "Configure should configure all necessary attributes",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.battery.battery(100)))
  end
)

test.register_coroutine_test(
  "closed contact events",
  function()
    local attr_report_data = {
      { IASZone.attributes.ZoneStatus.ID, data_types.Bitmap16.ID, 0x0020 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, IASZone.ID, attr_report_data, 0x115F)
    })
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed()))
  end
)

test.register_coroutine_test(
  "open contact events",
  function()
    local attr_report_data = {
      { IASZone.attributes.ZoneStatus.ID, data_types.Bitmap16.ID, 0x0021}
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, IASZone.ID, attr_report_data, 0x115F)
    })
    test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.contactSensor.contact.open()))
  end
)

test.run_registered_tests()
