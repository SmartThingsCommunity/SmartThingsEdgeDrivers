-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
-- package.path = package.path .. ";./?lua"
-- package.loaded["path"] = dofile("mock_path.lua")
local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.generated.zap_clusters"
local button_attr = capabilities.button.button


local mock_device = test.mock_device.build_test_matter_device(
        {
            label = "Bosch_Button_Contact_Sensor",
            profile = t_utils.get_profile_definition("contact-button-battery.yml"),
            manufacturer_info = {
                vendor_id = 0x1209,
                product_id = 0x3015
            },
            endpoints = {
                {
                    endpoint_id = 1,
                    clusters = {
                        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY},
                        {cluster_id = clusters.BooleanState.ID, cluster_type = "SERVER"}
                    },

                },
                {
                    endpoint_id = 2,
                    clusters = {
                        {
                            cluster_id = clusters.Switch.ID,
                            feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH |
                                    clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS |
                                    clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
                            cluster_type = "SERVER",
                        },
                    }
                }
            }
        })

local CLUSTER_SUBSCRIBE_LIST = {
    clusters.Switch.server.events.InitialPress,
    clusters.Switch.server.events.LongPress,
    clusters.Switch.server.events.MultiPressComplete,
    clusters.PowerSource.server.attributes.BatPercentRemaining,
    clusters.BooleanState.attributes.StateValue
}

local function test_init()
    local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
    for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
        if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
    end
    test.socket.matter:__expect_send({mock_device.id, subscribe_request})
    test.mock_device.add_test_device(mock_device)
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    mock_device:set_field("__initial_press_only_2", true, {persist = true})
    test.socket.matter:__expect_send({mock_device.id, clusters.Switch.attributes.MultiPressMax:read(mock_device)})
end

test.set_test_init_function(test_init)

test.register_message_test(
        "Handle single press sequence, no hold", {
            {
                channel = "matter",
                direction = "receive",
                message = {
                    mock_device.id,
                    clusters.Switch.events.InitialPress:build_test_event_report(
                            mock_device, 2, {new_position = 1}  --move to position 1?
                    ),
                }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true})) --should send initial press
            }
        }
)

test.register_message_test(
        "Handle single press sequence, with hold", {
            {
                channel = "matter",
                direction = "receive",
                message = {
                    mock_device.id,
                    clusters.Switch.events.InitialPress:build_test_event_report(
                            mock_device, 2, {new_position = 1}
                    ),
                }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.button.button.pushed({state_change = true})) --should send initial press
            },
            {
                channel = "matter",
                direction = "receive",
                message = {
                    mock_device.id,
                    clusters.Switch.events.LongPress:build_test_event_report(
                            mock_device, 2, {new_position = 1}
                    ),
                }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.button.button.held({state_change = true}))
            }
        }
)

test.register_message_test(
        "Handle release after long press", {
            {
                channel = "matter",
                direction = "receive",
                message = {
                    mock_device.id,
                    clusters.Switch.events.InitialPress:build_test_event_report(
                            mock_device, 2, {new_position = 1}
                    )
                }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.button.button.pushed({state_change = true}))
            },
            {
                channel = "matter",
                direction = "receive",
                message = {
                    mock_device.id,
                    clusters.Switch.events.LongPress:build_test_event_report(
                            mock_device, 2, {new_position = 1}
                    ),
                }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.button.button.held({state_change = true}))
            },
            {
                channel = "matter",
                direction = "receive",
                message = {
                    mock_device.id,
                    clusters.Switch.events.LongRelease:build_test_event_report(
                            mock_device, 2, {previous_position = 1}
                    )
                }
            },
        }
)

test.register_message_test(
        "Receiving a max press attribute of 2 should emit correct event", {
            {
                channel = "matter",
                direction = "receive",
                message = {
                    mock_device.id,
                    clusters.Switch.attributes.MultiPressMax:build_test_report_data(
                            mock_device, 1, 2
                    )
                },
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main",
                        capabilities.button.supportedButtonValues({"pushed", "double"}, {visibility = {displayed = false}}))
            },
        }
)

test.register_message_test(
        "Handle double press", {
            {
                channel = "matter",
                direction = "receive",
                message = {
                    mock_device.id,
                    clusters.Switch.events.InitialPress:build_test_event_report(
                            mock_device, 2, {new_position = 1}
                    )
                }
            },
            { -- again, on a device that reports that it supports double press, this event
                -- will not be generated. See a multi-button test file for that case
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.button.button.pushed({state_change = true}))
            },
            {
                channel = "matter",
                direction = "receive",
                message = {
                    mock_device.id,
                    clusters.Switch.events.MultiPressComplete:build_test_event_report(
                            mock_device, 2, {new_position = 1, total_number_of_presses_counted = 2, previous_position = 0}
                    )
                }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.button.button.double({state_change = true}))
            },

        }
)

test.register_message_test(
        "Handle received BatPercentRemaining from device.", {
            {
                channel = "matter",
                direction = "receive",
                message = {
                    mock_device.id,
                    clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
                            mock_device, 1, 150
                    ),
                },
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message(
                        "main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5))
                ),
            },
        }
)

test.register_message_test(
        "Boolean state reports should generate correct messages",
        {
            {
                channel = "matter",
                direction = "receive",
                message = {
                    mock_device.id,
                    clusters.BooleanState.server.attributes.StateValue:build_test_report_data(mock_device, 1, false)
                }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.open())
            },
            {
                channel = "matter",
                direction = "receive",
                message = {
                    mock_device.id,
                    clusters.BooleanState.server.attributes.StateValue:build_test_report_data(mock_device, 1, true)
                }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed())
            }
        }
)

test.run_registered_tests()
