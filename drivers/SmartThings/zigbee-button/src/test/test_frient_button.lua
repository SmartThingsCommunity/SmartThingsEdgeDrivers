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

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local cluster_base = require "st.zigbee.cluster_base"

local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local BasicInput = clusters.BasicInput
local OnOff = clusters.OnOff

local panicAlarm = capabilities.panicAlarm.panicAlarm
local button_attr = capabilities.button.button


local DEVELCO_MANUFACTURER_CODE = 0x1015

local data_types = require "st.zigbee.data_types"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("button-profile-frient.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "frient A/S",
          model = "SBTZB-110",
          server_clusters = {OnOff.ID},
        },
        [0x20] = {
            id = 0x20,
            server_clusters = {BasicInput.ID,  PowerConfiguration.ID},
            client_clusters = {OnOff.ID},

        },
      }
    }
)
local mock_device_panic = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("button-profile-panic-frient.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "frient A/S",
          model = "SBTZB-110",
          server_clusters = {OnOff.ID},
        },
        [0x20] = {
            id = 0x20,
            server_clusters = {BasicInput.ID,  PowerConfiguration.ID},
            client_clusters = {OnOff.ID},

        },
        [0x23] = {
            id = 0x23,
            server_clusters = {IASZone.ID}
        }
      }
    }
)
zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_device_panic)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Reported button should be handled: pushed",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, BasicInput.attributes.PresentValue:build_test_attr_report(mock_device, true) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", button_attr.pushed({ state_change = true }))
      }
    }
)

test.register_message_test("Refresh should read all necessary attributes", {
    {
        channel = "capability",
        direction = "receive",
        message = {
            mock_device.id,
            { capability = "refresh", component = "main", command = "refresh", args = {} }
        }
    },
    {
        channel = "zigbee",
        direction = "send",
        message = {mock_device.id, PowerConfiguration.attributes.BatteryVoltage:read(mock_device)}
    },
    {
        channel = "zigbee",
        direction = "send",
        message = {mock_device.id, BasicInput.attributes.PresentValue:read(mock_device)}
    },
})

test.register_coroutine_test("panicAlarm should be triggered and cleared", function()

    local panic_report = IASZone.attributes.ZoneStatus.build_test_attr_report(
            IASZone.attributes.ZoneStatus,
            mock_device_panic,
            0x0002
    )

    test.socket.zigbee:__queue_receive({
        mock_device_panic.id,
        panic_report
    })

    test.socket.capability:__expect_send(mock_device_panic:generate_test_message("main", panicAlarm.panic({value = "panic", state_change = true})))

    test.wait_for_events()

    local clear_report = IASZone.attributes.ZoneStatus.build_test_attr_report(
            IASZone.attributes.ZoneStatus,
            mock_device_panic,
            0x0001
    )
    test.socket.zigbee:__queue_receive({
        mock_device_panic.id,
        clear_report
    })

    test.socket.capability:__expect_send(mock_device_panic:generate_test_message("main", panicAlarm.clear({value = "clear", state_change = true})))
    test.wait_for_events()

end)

test.register_coroutine_test(
    "Battery Voltage test cases",
    function()
        local battery_table = {
            [33] = 100,
            [32] = 100,
            [27] = 50,
            [26] = 30,
            [23] = 10,
            [15] = 0,
            [10] = 0
        }
        test.socket.device_lifecycle:__queue_receive({mock_device.id, "added"})
        test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed"}, {visibility = { displayed = false }})))
        test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.numberOfButtons({value = 1})))
        test.socket.capability:__expect_send(mock_device:generate_test_message("main", button_attr.pushed({ state_change = false})))
        test.wait_for_events()


      for voltage, batt_perc in pairs(battery_table) do
        test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, voltage) })
        test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )

      end
    end
)

test.register_coroutine_test(
        "added , init, and doConfigure should configure all necessary attributes",
    function()
        test.socket.zigbee:__set_channel_ordering("relaxed")
        test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
        test.wait_for_events()

        test.socket.device_lifecycle:__queue_receive({mock_device.id, "added"})
        test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed"}, {visibility = { displayed = false }})))
        test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.numberOfButtons({value = 1})))
        test.socket.capability:__expect_send(mock_device:generate_test_message("main", button_attr.pushed({ state_change = false})))

        test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})

        test.socket.zigbee:__expect_send({mock_device.id, zigbee_test_utils.build_bind_request(
                mock_device,
                zigbee_test_utils.mock_hub_eui,
                PowerConfiguration.ID,
                0x20
        ):to_endpoint(0x20)})

        test.socket.zigbee:__expect_send({mock_device.id, zigbee_test_utils.build_bind_request(
                mock_device,
                zigbee_test_utils.mock_hub_eui,
                BasicInput.ID,
                0x20
        ):to_endpoint(0x20)})

        test.socket.zigbee:__expect_send({mock_device.id, PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30,21600, 1 ):to_endpoint(0x20)})
        test.socket.zigbee:__expect_send({mock_device.id, BasicInput.attributes.PresentValue:configure_reporting(mock_device, 0,21600, 1 ):to_endpoint(0x20)})

        test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device, OnOff.ID, 0x8002, DEVELCO_MANUFACTURER_CODE, data_types.Enum8, 2):to_endpoint(0x20)})
        test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device, OnOff.ID, 0x8001, DEVELCO_MANUFACTURER_CODE, data_types.Uint16, 100):to_endpoint(0x20)})
        test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device, BasicInput.ID, 0x8000, DEVELCO_MANUFACTURER_CODE, data_types.Uint16, 65535):to_endpoint(0x20)})

        mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test("info_changed for OnOff cluster attributes should run properly",
function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(
            {
                preferences = {
                    ledColor = 1,
                    buttonDelay = 300,
                }
            }
    ))

    local ledColor_msg = cluster_base.write_manufacturer_specific_attribute(mock_device,OnOff.ID, 0x8002, DEVELCO_MANUFACTURER_CODE, data_types.Enum8, 1)
    ledColor_msg.body.zcl_header.frame_ctrl.value = 0x0C
    ledColor_msg.address_header.dest_endpoint.value = 0x20
    test.socket.zigbee:__expect_send({mock_device.id, ledColor_msg})

    local buttonDelay_msg = cluster_base.write_manufacturer_specific_attribute(mock_device,OnOff.ID, 0x8001, DEVELCO_MANUFACTURER_CODE, data_types.Uint16, 0x012C)
    buttonDelay_msg.body.zcl_header.frame_ctrl.value = 0x0C
    buttonDelay_msg.address_header.dest_endpoint.value = 0x20
    test.socket.zigbee:__expect_send({mock_device.id, buttonDelay_msg})
end)

test.register_coroutine_test(" Configuration and Switching to button-profile-panic-frient deviceProfile should be triggered", function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(
            {
                preferences = {
                    panicButton = "0x002C"
                }
            }
    ))
    mock_device:expect_metadata_update({ profile = "button-profile-panic-frient" })
    test.socket.zigbee:__expect_send({mock_device.id, cluster_base.write_manufacturer_specific_attribute(mock_device, BasicInput.ID, 0x8000, DEVELCO_MANUFACTURER_CODE, data_types.Uint16,0x002C)})

    local attributes = {
        {attr = 0x8002, payload = 0x07D0, data_type = data_types.Uint16},
        {attr = 0x8003, payload = 0x07D0, data_type = data_types.Uint16},
        {attr = 0x8004, payload = 0x0A, data_type = data_types.Uint16},
        {attr = 0x8005, payload = 0, data_type = data_types.Enum8}
    }
    -- waiting for IASzone configuration execution
    test.mock_time.advance_time(5)
    for _, attr in ipairs(attributes) do
        local msg = cluster_base.write_manufacturer_specific_attribute(mock_device,IASZone.ID, attr.attr, DEVELCO_MANUFACTURER_CODE, attr.data_type, attr.payload)
        msg.address_header.dest_endpoint.value = 0x23
        test.socket.zigbee:__expect_send({mock_device.id, msg})
    end
    -- Unable to check if the emit went through successfully due to the framework limitations in swapping mock device's deviceProfile
    --test.socket.capability:__expect_send({mock_device.id, capabilities.panicAlarm.panicAlarm.clear({state_change = true})})
end)

test.register_coroutine_test("Switching from button-profile-panic-frient to button-profile-frient should work", function()
    test.socket.device_lifecycle:__queue_receive(mock_device_panic:generate_info_changed(
            {
                preferences = {
                    panicButton = "0xFFFF"
                },
            }
    ))
    mock_device_panic:expect_metadata_update({ profile = "button-profile-frient" })
    test.socket.zigbee:__expect_send({mock_device_panic.id, cluster_base.write_manufacturer_specific_attribute(mock_device_panic,BasicInput.ID,0x8000,DEVELCO_MANUFACTURER_CODE,data_types.Uint16,0xFFFF)})
end)

test.register_coroutine_test("New preferences after switching the profile should work", function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive(mock_device_panic:generate_info_changed(
            {
                preferences = {
                    buttonAlarmDelay = 1,
                    buttonCancelDelay = 300,
                    autoCancel = 20,
                    alarmBehavior = 1
                }
            }
    ))
    test.socket.zigbee:__expect_send({mock_device_panic.id, cluster_base.write_manufacturer_specific_attribute(mock_device_panic, IASZone.ID,0x8002,DEVELCO_MANUFACTURER_CODE,data_types.Uint16, 1)})
    test.socket.zigbee:__expect_send({mock_device_panic.id, cluster_base.write_manufacturer_specific_attribute(mock_device_panic, IASZone.ID,0x8003,DEVELCO_MANUFACTURER_CODE,data_types.Uint16, 300)})
    test.socket.zigbee:__expect_send({mock_device_panic.id, cluster_base.write_manufacturer_specific_attribute(mock_device_panic, IASZone.ID,0x8004,DEVELCO_MANUFACTURER_CODE,data_types.Uint16, 20)})
    test.socket.zigbee:__expect_send({mock_device_panic.id, cluster_base.write_manufacturer_specific_attribute(mock_device_panic, IASZone.ID,0x8005,DEVELCO_MANUFACTURER_CODE,data_types.Enum8, 1)})
end)

test.run_registered_tests()
