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
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local FanControl = clusters.FanControl
local OnOff = clusters.OnOff
local Level = clusters.Level

-- create test device (Multifunction)
local mock_base_device = test.mock_device.build_test_zigbee_device(
        {
            profile = t_utils.get_profile_definition("kichler-fan-light.yml"),
            zigbee_endpoints = {
                [1] = {
                    id = 1,
                    manufacturer = "KICHLER",
                    model = "KICHLER-FANLIGHT-Z-301",
                    server_clusters = { 0x0000, 0x0003, 0x0006, 0x0008, 0x0202, 0x0300 }
                }
            },
            fingerprinted_endpoint_id = 0x01
        }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
    test.mock_device.add_test_device(mock_base_device)
    zigbee_test_utils.init_noop_health_check_timer()
end
test.set_test_init_function(test_init)

-- create test commands
test.register_message_test(
        " #1 Light switchLevel command <send to device> : 100% ",
        {
            {
                channel = "capability",
                direction = "receive",
                message = { mock_base_device.id, { capability = "switchLevel", component = "light",
                                                    command = "setLevel", args = { 100, 0 } } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, Level.server.commands.MoveToLevelWithOnOff
                            (mock_base_device, 254, 0) }
            }
        }
)

test.register_message_test(
        " #2 Light switchLevel command <send to device> : 50% ",
        {
            {
                channel = "capability",
                direction = "receive",
                message = { mock_base_device.id, { capability = "switchLevel", component = "light",
                                                    command = "setLevel", args = { 50, 0 } } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, Level.server.commands.MoveToLevelWithOnOff
                (mock_base_device, 127, 0) }
            }
        }
)

test.register_message_test(
        " #3 Light switchLevel command <send to device> : 0% ",
        {
            {
                channel = "capability",
                direction = "receive",
                message = { mock_base_device.id, { capability = "switchLevel", component = "light",
                                                   command = "setLevel", args = { 0, 0 } } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, Level.server.commands.MoveToLevelWithOnOff
                (mock_base_device, 0, 0) }
            }
        }
)

test.register_message_test(
        " #4 Light OnOff command <send to device> : Off ",
        {
            {
                channel = "capability",
                direction = "receive",
                message = { mock_base_device.id, { capability = "switch", component = "light", command = "off",
                                                   args = {} } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, Level.server.commands.MoveToLevelWithOnOff
                (mock_base_device, 0, 0xFFFF) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, FanControl.attributes.FanMode:read(mock_base_device) }
            }
        }
)

test.register_message_test(
        " #5 Light OnOff command <send to device> : On ",
        {
            {
                channel = "capability",
                direction = "receive",
                message = { mock_base_device.id, { capability = "switch", component = "light", command = "on",
                                                   args = {} } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, Level.server.commands.MoveToLevelWithOnOff
                (mock_base_device, 254, 0xFFFF) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, FanControl.attributes.FanMode:read(mock_base_device) }
            }
        }
)

test.register_message_test(
        " #6 Light switch attribute <receive from device> : on ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_base_device.id, OnOff.attributes.OnOff:
                           build_test_attr_report(mock_base_device, true):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("light", capabilities.switch.switch.on())
            }
        }
)

test.register_message_test(
        " #7 Light switch attribute <receive from device> : off ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_base_device.id, OnOff.attributes.OnOff:
                           build_test_attr_report(mock_base_device, false):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("light", capabilities.switch.switch.off())
            }
        }
)

test.register_message_test(
        " #8 Light level attribute <receive from device> : 100% ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_base_device.id, Level.attributes.CurrentLevel:
                           build_test_attr_report(mock_base_device, 254):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("light", capabilities.switchLevel.level(100))
            }
        }
)

test.register_message_test(
        " #9 Light level attribute <receive from device> : 50% ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_base_device.id, Level.attributes.CurrentLevel:
                build_test_attr_report(mock_base_device, 127):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("light", capabilities.switchLevel.level(50))
            }
        }
)

test.register_message_test(
        " #10 Light level attribute <receive from device> : 0% ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_base_device.id, Level.attributes.CurrentLevel:
                build_test_attr_report(mock_base_device, 0):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("light", capabilities.switchLevel.level(0))
            }
        }
)

test.register_message_test(
        " #11 FanSpeed command <send to device> : 0% ",
        {
            {
                channel = "capability",
                direction = "receive",
                message = { mock_base_device.id, { capability = "fanSpeed", command = "setFanSpeed", args = { 0 } } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, FanControl.attributes.FanMode:write(mock_base_device, 0x00) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, FanControl.attributes.FanMode:read(mock_base_device) }
            }
        }
)

test.register_message_test(
        " #12 FanSpeed command <send to device> : Low ",
        {
            {
                channel = "capability",
                direction = "receive",
                message = { mock_base_device.id, { capability = "fanSpeed", command = "setFanSpeed", args = { 1 } } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, FanControl.attributes.FanMode:write(mock_base_device, 0x01) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, FanControl.attributes.FanMode:read(mock_base_device) }
            }
        }
)

test.register_message_test(
        " #13 FanSpeed command <send to device> : High ",
        {
            {
                channel = "capability",
                direction = "receive",
                message = { mock_base_device.id, { capability = "fanSpeed", command = "setFanSpeed", args = { 3 } } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, FanControl.attributes.FanMode:write(mock_base_device, 0x03) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_base_device.id, FanControl.attributes.FanMode:read(mock_base_device) }
            }
        }
)

test.register_message_test(
        " #14 FanSpeed attribute <receive from device> : LOW ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_base_device.id, FanControl.attributes.FanMode:
                build_test_attr_report(mock_base_device, 1):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("main", capabilities.fanSpeed.fanSpeed(1))
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("main", capabilities.switch.switch.on({ visibility = { displayed = true } }))
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("main", capabilities.fanSpeed.fanSpeed(1))
            }
        }
)

test.register_message_test(
        " #15 FanSpeed attribute <receive from device> : Middle ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_base_device.id, FanControl.attributes.FanMode:
                build_test_attr_report(mock_base_device, 2):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("main", capabilities.fanSpeed.fanSpeed(2))
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("main", capabilities.switch.switch.on({ visibility = { displayed = true } }))
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("main", capabilities.fanSpeed.fanSpeed(2))
            }
        }
)

test.register_message_test(
        " #16 FanSpeed attribute <receive from device> : High ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_base_device.id, FanControl.attributes.FanMode:
                build_test_attr_report(mock_base_device, 3):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("main", capabilities.fanSpeed.fanSpeed(3))
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("main", capabilities.switch.switch.on({ visibility = { displayed = true } }))
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("main", capabilities.fanSpeed.fanSpeed(3))
            }
        }
)

test.register_message_test(
        " #17 Fan control attribute  <receive from device> : Off ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_base_device.id, FanControl.attributes.FanMode:
                build_test_attr_report(mock_base_device, 0):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("main", capabilities.fanSpeed.fanSpeed(0))
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("main", capabilities.switch.switch.off({ visibility = { displayed = true } }))
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_base_device:generate_test_message("main", capabilities.fanSpeed.fanSpeed(0))
            }
        }
)

test.register_message_test(
        " #18 Fan control attribute <receive from device> : Breezemode Enabled ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_base_device.id, FanControl.attributes.FanMode:
                build_test_attr_report(mock_base_device, 4):from_endpoint(0x01) }
            },
        }
)

test.register_message_test(
        " #19 Fan control attribute <receive from device> : Breezemode Disabled ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_base_device.id, FanControl.attributes.FanMode:
                build_test_attr_report(mock_base_device, 5):from_endpoint(0x01) }
            },
        }
)

test.register_message_test(
        " #20 Fan control attribute <receive from device> : Fandirection Toggle ",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_base_device.id, FanControl.attributes.FanMode:
                build_test_attr_report(mock_base_device, 6):from_endpoint(0x01) }
            },
        }
)

test.register_coroutine_test(
        " #21 Breezemode changed <receive from lifecycle handler infoChanged> : Breeze mode Enabled ",
        function()
            test.socket.device_lifecycle():__queue_receive(mock_base_device:generate_info_changed(
                    { preferences = { trim = 10,
                                      breezemode = 1,
                                      fandirection = 1 }}))
            test.socket.zigbee:__expect_send({ mock_base_device.id, FanControl.attributes.FanMode:write(mock_base_device, 4)})
        end
)

test.register_coroutine_test(
        " #22 Breezemode changed <receive from lifecycle handler infoChanged> : Breeze mode Disabled ",
        function()
            test.socket.device_lifecycle():__queue_receive(mock_base_device:generate_info_changed(
                    { preferences = { trim = 10,
                                      breezemode = 1,
                                      fandirection = 1 }}))
            test.socket.zigbee:__expect_send({ mock_base_device.id, FanControl.attributes.FanMode:write(mock_base_device, 4)})
            test.wait_for_events()
            test.socket.device_lifecycle():__queue_receive(mock_base_device:generate_info_changed(
                    { preferences = { trim = 10,
                                      breezemode = 0,
                                      fandirection = 1 }}))
            test.socket.zigbee:__expect_send({ mock_base_device.id, FanControl.attributes.FanMode:write(mock_base_device, 5)})
            test.socket.zigbee:__expect_send({ mock_base_device.id, FanControl.attributes.FanMode:write(mock_base_device, 1)})
        end
)

test.register_coroutine_test(
        " #23 Fandirection changed <receive from lifecycle handler infoChanged> : Forward to Reverse ",
        function()
            test.socket.device_lifecycle():__queue_receive(mock_base_device:generate_info_changed(
                    { preferences = { trim = 10,
                                      breezemode = 0,
                                      fandirection = 0 }}))
            test.socket.zigbee:__expect_send({ mock_base_device.id, FanControl.attributes.FanMode:write(mock_base_device, 6)})
        end
)

test.register_coroutine_test(
        " #24 Trim changed higher value <receive from lifecycle handler infoChanged> : 10% to 25% ",
function()
            test.socket.device_lifecycle():__queue_receive(mock_base_device:generate_info_changed(
                    { preferences = { trim = 10, breezemode = 0, fandirection = 1 }}))
            test.socket.capability:__queue_receive({ mock_base_device.id, { capability = "switchLevel", component = "light",
command = "setLevel", args = { 5, 0 } } })
            test.socket.capability:__expect_send(mock_base_device:generate_test_message("light", capabilities.switchLevel.level(5)))
            test.socket.zigbee:__expect_send({ mock_base_device.id, Level.server.commands.MoveToLevelWithOnOff
(mock_base_device, 25, 0) })
            test.socket.capability:__expect_send(mock_base_device:generate_test_message("light", capabilities.switchLevel.level(10)))
            test.wait_for_events()
            test.socket.device_lifecycle():__queue_receive(mock_base_device:generate_info_changed(
                    { preferences = { trim = 25, breezemode = 0, fandirection = 1 }}))
            test.socket.zigbee:__expect_send({ mock_base_device.id, Level.server.commands.MoveToLevelWithOnOff
(mock_base_device, 63, 0) })
        end
)

test.register_coroutine_test(
        " #25 Trim changed lower value <receive from lifecycle handler infoChanged> : 25% to 10% ",
function()
            test.socket.device_lifecycle():__queue_receive(mock_base_device:generate_info_changed(
                    { preferences = { trim = 25, breezemode = 0, fandirection = 1 }}))
            test.socket.zigbee:__expect_send({ mock_base_device.id, Level.server.commands.MoveToLevelWithOnOff
(mock_base_device, 254, 0) })
            test.socket.device_lifecycle():__queue_receive(mock_base_device:generate_info_changed(
                    { preferences = { trim = 10, breezemode = 0, fandirection = 1 }}))
            test.socket.zigbee:__expect_send({ mock_base_device.id, Level.server.commands.MoveToLevelWithOnOff
(mock_base_device, 254, 0) })
        end
)

test.register_message_test(
        " #26 Trim triggered condition <send to device> : 5% @trim 10% ",
{
            {
                channel = "capability",
direction = "receive",
message = { mock_base_device.id, { capability = "switchLevel", component = "light",
command = "setLevel", args = { 5, 0 } } }
            },
{
                channel = "capability",
direction = "send",
message = mock_base_device:generate_test_message("light", capabilities.switchLevel.level(5))
            },
{
                channel = "zigbee",
direction = "send",
message = { mock_base_device.id, Level.server.commands.MoveToLevelWithOnOff
(mock_base_device, 25, 0) }
            },
{
                channel = "capability",
direction = "send",
message = mock_base_device:generate_test_message("light", capabilities.switchLevel.level(10))
            },
}
)

test.run_registered_tests()

