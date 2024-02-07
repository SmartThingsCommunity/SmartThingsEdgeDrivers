local test = require "integration_test"
local t_utils = require "integration_test.utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local FanControl = clusters.FanControl
local OnOff = clusters.OnOff
local Level = clusters.Level

local mock_parent_device = test.mock_device.build_test_zigbee_device(
        {
            profile = t_utils.get_profile_definition("itm-fan-light.yml"),
            zigbee_endpoints = {
                [1] = {
                    id = 1,
                    manufacturer = "Samsung Electronics",
                    model = "SAMSUNG-ITM-Z-003",
                    server_clusters = { 0x0000, 0x0003, 0x0006, 0x0008, 0x0202, 0x0300 }
                }
            },
            fingerprinted_endpoint_id = 0x01
        }
)

local mock_child_device = test.mock_device.build_test_child_device(
        {
            profile = t_utils.get_profile_definition("switch-level.yml"),
            device_network_id = string.format("%04X:%02X", mock_parent_device:get_short_address(), 2),
            parent_device_id = mock_parent_device.id,
            parent_assigned_child_key = string.format("%02X", 2)
        }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
    test.mock_device.add_test_device(mock_parent_device)
    test.mock_device.add_test_device(mock_child_device)
    zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
        " Light Dim command <send> : 100% ",
        {
            {
                channel = "device_lifecycle",
                direction = "receive",
                message = { mock_parent_device.id, "init" }
            },
            {
                channel = "capability",
                direction = "receive",
                message = { mock_child_device.id, { capability = "switchLevel", component = "light",
                                                    command = "setLevel", args = { 100, 0 } } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_parent_device.id, Level.server.commands.MoveToLevelWithOnOff
                            (mock_parent_device, 254, 0) }
            }
        }
)

test.register_message_test(
        " Light Dim command <send> : 50% ",
        {
            {
                channel = "device_lifecycle",
                direction = "receive",
                message = { mock_parent_device.id, "init" }
            },
            {
                channel = "capability",
                direction = "receive",
                message = { mock_child_device.id, { capability = "switchLevel", component = "light",
                                                    command = "setLevel", args = { 50, 0 } } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_parent_device.id, Level.server.commands.MoveToLevelWithOnOff
                (mock_parent_device, 127, 0) }
            }
        }
)

test.register_message_test(
        " Light switch <receive> : on ",
        {
            {
                channel = "device_lifecycle",
                direction = "receive",
                message = { mock_parent_device.id, "init" }

            },
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_parent_device.id, OnOff.attributes.OnOff:
                           build_test_attr_report(mock_parent_device, true):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_parent_device:generate_test_message("light", capabilities.switch.switch.on())
            }
        }
)

test.register_message_test(
        " Light switch <receive> : off ",
        {
            {
                channel = "device_lifecycle",
                direction = "receive",
                message = { mock_parent_device.id, "init" }

            },
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_parent_device.id, OnOff.attributes.OnOff:
                           build_test_attr_report(mock_parent_device, false):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_parent_device:generate_test_message("light", capabilities.switch.switch.off())
            }
        }
)

test.register_message_test(
        " Light level <receive> : 100% ",
        {
            {
                channel = "device_lifecycle",
                direction = "receive",
                message = { mock_parent_device.id, "init" }

            },
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_parent_device.id, Level.attributes.CurrentLevel:
                           build_test_attr_report(mock_parent_device, 254):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_parent_device:generate_test_message("light", capabilities.switchLevel.level(100))
            }
        }
)

test.register_message_test(
        " Light level <receive> : 50% ",
        {
            {
                channel = "device_lifecycle",
                direction = "receive",
                message = { mock_parent_device.id, "init" }

            },
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_parent_device.id, Level.attributes.CurrentLevel:
                build_test_attr_report(mock_parent_device, 127):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_parent_device:generate_test_message("light", capabilities.switchLevel.level(50))
            }
        }
)

test.register_message_test(
        " Light level & added lifecycle <receive> : 0%",
        {
            {
                channel = "device_lifecycle",
                direction = "receive",
                message = { mock_child_device.id, "added" }
            },
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_parent_device.id, Level.attributes.CurrentLevel:
                build_test_attr_report(mock_parent_device, 0):from_endpoint(0x01) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_parent_device:generate_test_message("light", capabilities.switchLevel.level(0))
            }
        }
)

test.register_message_test(
        " FanSpeed control <send> : 0% ",
        {
            {
                channel = "device_lifecycle",
                direction = "receive",
                message = { mock_parent_device.id, "init" }
            },
            {
                channel = "capability",
                direction = "receive",
                message = { mock_parent_device.id, { capability = "fanSpeed", command = "setFanSpeed", args = { 0 } } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_parent_device.id, FanControl.attributes.FanMode:write(mock_parent_device, 0x00) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_parent_device.id, FanControl.attributes.FanMode:read(mock_parent_device) }
            }
        }
)

test.register_message_test(
        " 'FanSpeed control <send> : Low ",
        {
            {
                channel = "device_lifecycle",
                direction = "receive",
                message = { mock_parent_device.id, "init" }
            },
            {
                channel = "capability",
                direction = "receive",
                message = { mock_parent_device.id, { capability = "fanSpeed", command = "setFanSpeed", args = { 1 } } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_parent_device.id, FanControl.attributes.FanMode:write(mock_parent_device, 0x01) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_parent_device.id, FanControl.attributes.FanMode:read(mock_parent_device) }
            }
        }
)

test.register_message_test(
        " 'FanSpeed control <send> : High ",
        {
            {
                channel = "device_lifecycle",
                direction = "receive",
                message = { mock_parent_device.id, "init" }
            },
            {
                channel = "capability",
                direction = "receive",
                message = { mock_parent_device.id, { capability = "fanSpeed", command = "setFanSpeed", args = { 3 } } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_parent_device.id, FanControl.attributes.FanMode:write(mock_parent_device, 0x03) }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_parent_device.id, FanControl.attributes.FanMode:read(mock_parent_device) }
            }
        }
)

test.register_message_test(
        " Light OnOff command <send> : Off ",
        {
            {
                channel = "capability",
                direction = "receive",
                message = { mock_child_device.id, { capability = "switch", component = "light", command = "off",
                                                    args = {} } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_parent_device.id, OnOff.server.commands.Off(mock_parent_device) }
            }
        }
)

test.register_message_test(
        " Light OnOff command <send> : On ",
        {
            {
                channel = "capability",
                direction = "receive",
                message = { mock_child_device.id, { capability = "switch", component = "light", command = "on",
                                                     args = {} } }
            },
            {
                channel = "zigbee",
                direction = "send",
                message = { mock_parent_device.id, OnOff.server.commands.On(mock_parent_device) }
            }
        }
)

test.run_registered_tests()
