-- Copyright 2026 SmartThings
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
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("sonoff-buttons-battery.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "SONOFF",
        model = "SNZB-01M",
        server_clusters = { 0x0001, 0xFC12 }
      },
      [2] = {
        id = 2,
        manufacturer = "SONOFF",
        model = "SNZB-01M",
        server_clusters = { 0x0001, 0xFC12 }
      },
      [3] = {
        id = 3,
        manufacturer = "SONOFF",
        model = "SNZB-01M",
        server_clusters = { 0x0001, 0xFC12 }
      },
      [4] = {
        id = 4,
        manufacturer = "SONOFF",
        model = "SNZB-01M",
        server_clusters = { 0x0001, 0xFC12 }
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
  "added lifecycle event",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

    -- Check initial events for button 1
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "button1",
        capabilities.button.supportedButtonValues({ "pushed", "double", "held", "pushed_3x" }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "button1",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", capabilities.button.button.pushed({ state_change = false }))
    )

    -- Check initial events for button 2
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "button2",
        capabilities.button.supportedButtonValues({ "pushed", "double", "held", "pushed_3x" }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "button2",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button2", capabilities.button.button.pushed({ state_change = false }))
    )

    -- Check initial events for button 3
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "button3",
        capabilities.button.supportedButtonValues({ "pushed", "double", "held", "pushed_3x" }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "button3",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button3", capabilities.button.button.pushed({ state_change = false }))
    )

    -- Check initial events for button 4
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "button4",
        capabilities.button.supportedButtonValues({ "pushed", "double", "held", "pushed_3x" }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "button4",
        capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } })
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button4", capabilities.button.button.pushed({ state_change = false }))
    )

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 21600, 1)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, clusters.PowerConfiguration.ID) 
    })

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Button pushed message should generate event",
  function()
    -- 0xFC12, 0x0000, 0x01 = pushed
    local attr_report = cluster_base.build_custom_report_attribute(
      mock_device,
      0xFC12,
      0x0000,
      0x20, -- Uint8
      data_types.Uint8(0x01)
    )

    test.socket.zigbee:__queue_receive({ mock_device.id, attr_report })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", capabilities.button.button.pushed({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "Button double message should generate event",
  function()
    -- 0xFC12, 0x0000, 0x02 = double
    local attr_report = cluster_base.build_custom_report_attribute(
      mock_device,
      0xFC12,
      0x0000,
      0x20, -- Uint8
      data_types.Uint8(0x02)
    )

    test.socket.zigbee:__queue_receive({ mock_device.id, attr_report })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", capabilities.button.button.double({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "Button held message should generate event",
  function()
    -- 0xFC12, 0x0000, 0x03 = held
    local attr_report = cluster_base.build_custom_report_attribute(
      mock_device,
      0xFC12,
      0x0000,
      0x20, -- Uint8
      data_types.Uint8(0x03)
    )

    test.socket.zigbee:__queue_receive({ mock_device.id, attr_report })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", capabilities.button.button.held({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "Button pushed_3x message should generate event",
  function()
    -- 0xFC12, 0x0000, 0x04 = pushed_3x
    local attr_report = cluster_base.build_custom_report_attribute(
      mock_device,
      0xFC12,
      0x0000,
      0x20, -- Uint8
      data_types.Uint8(0x04)
    )

    test.socket.zigbee:__queue_receive({ mock_device.id, attr_report })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button1", capabilities.button.button.pushed_3x({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "Button 2 pushed message should generate event on button2 component",
  function()
    -- Endpoint 2 test
    local attr_report = cluster_base.build_custom_report_attribute(
      mock_device,
      0xFC12,
      0x0000,
      0x20, -- Uint8
      data_types.Uint8(0x01)
    )
    -- Modify endpoint to 2
    attr_report.address_header.src_endpoint.value = 2

    test.socket.zigbee:__queue_receive({ mock_device.id, attr_report })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("button2", capabilities.button.button.pushed({ state_change = true }))
    )
  end
)

test.register_coroutine_test(
  "Battery percentage report should generate event",
  function()
    -- 0x0001 PowerConfiguration, 0x0021 BatteryPercentageRemaining
    -- Driver logic: math.floor(value / 2)
    local battery_report = clusters.PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 180) -- 180/2 = 90%

    test.socket.zigbee:__queue_receive({ mock_device.id, battery_report })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.battery.battery(90))
    )
  end
)

return test
