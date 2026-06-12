-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local data_types = require "st.matter.data_types"
local st_utils = require "st.utils"
local dkjson = require "dkjson"

local clusters = require "st.matter.clusters"
local cluster_base = require "st.matter.cluster_base"
local descriptor = require "st.matter.generated.zap_clusters.Descriptor"

local MATTER_DEVICE_ID = "MATTER_DEVICE_ID"
local PARENT_ID = "PARENT_ID"
local BUTTON_EPS = "__button_eps"


local function create_parent_device(product_id)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 4x Button",
        profile = t_utils.get_profile_definition("matter-bridge.yml"),
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = product_id,
        },
        endpoints = {
            {
                endpoint_id = 0,
                clusters = { { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" } },
                device_types = { { device_type_id = 0x0016, device_type_revision = 1 } }
            },
            {
                endpoint_id = 1,
                clusters = {
                    { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" }
                },
                device_types = { { device_type_id = 0x000E, device_type_revision = 1 } } -- AggregateNode
            },
            {
                endpoint_id = 2,
                clusters = {
                    {
                        cluster_id = clusters.Descriptor.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                    }
                },
                device_types = { { device_type_id = 0x0039, device_type_revision = 1 } } -- BridgedNode
            }
        }
    })
end

local function create_matter_device(profile_name, parent)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 4x Button",
        profile = t_utils.get_profile_definition(profile_name .. ".yml"),
        type = "MATTER",
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = 0x0006,
        },
        parent_device_id = parent.id,
        endpoints = {
            {
                endpoint_id = 0,
                clusters = { { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" } },
                device_types = { { device_type_id = 0x0016, device_type_revision = 1 } }
            },
            {
                endpoint_id = 8,
                clusters = {
                    {
                        cluster_id = clusters.Switch.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
                        attributes = {
                            [clusters.Switch.attributes.MultiPressMax.ID] = 2
                        }
                    }
                },
                device_types = { { device_type_id = 0x003B, device_type_revision = 1 } }
            },
            {
                endpoint_id = 9,
                clusters = {
                    {
                        cluster_id = clusters.Switch.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
                        attributes = {
                            [clusters.Switch.attributes.MultiPressMax.ID] = 2
                        }
                    }
                },
                device_types = { { device_type_id = 0x003B, device_type_revision = 1 } }
            },
            {
                endpoint_id = 10,
                clusters = {
                    {
                        cluster_id = clusters.Switch.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
                        attributes = {
                            [clusters.Switch.attributes.MultiPressMax.ID] = 2
                        }
                    }
                },
                device_types = { { device_type_id = 0x003B, device_type_revision = 1 } }
            },
            {
                endpoint_id = 11,
                clusters = {
                    {
                        cluster_id = clusters.Switch.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
                        attributes = {
                            [clusters.Switch.attributes.MultiPressMax.ID] = 2
                        }
                    }
                },
                device_types = { { device_type_id = 0x003B, device_type_revision = 1 } }
            },
        }
    })
end

-- Create Hager 2G Relay device with endpoints 3 & 4 (OnOff clusters)
local function create_hager_2g_relay(profile_name, parent)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 2G Relay",
        profile = t_utils.get_profile_definition(profile_name .. ".yml"),
        type = "MATTER",
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = 0x0006,
        },
        parent_device_id = parent.id,
        endpoints = {
            {
                endpoint_id = 0,
                clusters = { { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" } },
                device_types = { { device_type_id = 0x0016, device_type_revision = 1 } }
            },
            {
                endpoint_id = 3,
                clusters = {
                    {
                        cluster_id = clusters.OnOff.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        attributes = {
                            [clusters.OnOff.attributes.OnOff.ID] = false
                        }
                    }
                },
                device_types = { { device_type_id = 0x0100, device_type_revision = 1 } }
            },
            {
                endpoint_id = 4,
                clusters = {
                    {
                        cluster_id = clusters.OnOff.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        attributes = {
                            [clusters.OnOff.attributes.OnOff.ID] = false
                        }
                    }
                },
                device_types = { { device_type_id = 0x0100, device_type_revision = 1 } }
            },
        }
    })
end

-- Create Hager Dimmer device with ONLY dimmable endpoint (3) - no button endpoints
local function create_hager_dimmer_device_1g(profile_name, parent)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 Dimmer",
        profile = t_utils.get_profile_definition(profile_name .. ".yml"),
        type = "MATTER",
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = 0x0005,
        },
        parent_device_id = parent.id,
        endpoints = {
            {
                endpoint_id = 0,
                clusters = { { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" } },
                device_types = { { device_type_id = 0x0016, device_type_revision = 1 } }
            },
            {
                endpoint_id = 4,
                clusters = {
                    {
                        cluster_id = clusters.OnOff.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        attributes = {
                            [clusters.OnOff.attributes.OnOff.ID] = false
                        }
                    },
                    {
                        cluster_id = clusters.LevelControl.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        attributes = {
                            [clusters.LevelControl.attributes.CurrentLevel.ID] = 254
                        }
                    }
                },
                device_types = { { device_type_id = 0x0101, device_type_revision = 1 } }
            },
        }
    })
end

local function create_hager_dimmer_device_2g(profile_name, parent)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 Dimmer",
        profile = t_utils.get_profile_definition(profile_name .. ".yml"),
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = 0x0006,
        },
        parent_device_id = parent.id,
        endpoints = {
            {
                endpoint_id = 0,
                clusters = { { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" } },
                device_types = { { device_type_id = 0x0016, device_type_revision = 1 } }
            },
            {
                endpoint_id = 3,
                clusters = {
                    {
                        cluster_id = clusters.OnOff.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        attributes = {
                            [clusters.OnOff.attributes.OnOff.ID] = false
                        }
                    },
                    {
                        cluster_id = clusters.LevelControl.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        attributes = {
                            [clusters.LevelControl.attributes.CurrentLevel.ID] = 254
                        }
                    }
                },
                device_types = { { device_type_id = 0x0101, device_type_revision = 1 } }
            },
            {
                endpoint_id = 8,
                clusters = {
                    {
                        cluster_id = clusters.Switch.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
                        attributes = {
                            [clusters.Switch.attributes.MultiPressMax.ID] = 2
                        }
                    }
                },
                device_types = { { device_type_id = 0x003B, device_type_revision = 1 } }
            },
            {
                endpoint_id = 9,
                clusters = {
                    {
                        cluster_id = clusters.Switch.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
                        attributes = {
                            [clusters.Switch.attributes.MultiPressMax.ID] = 2
                        }
                    }
                },
                device_types = { { device_type_id = 0x003B, device_type_revision = 1 } }
            },
        }
    })
end

local function create_matter_device_with_window(profile_name, parent)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 matter device with Window Covering",
        profile = t_utils.get_profile_definition(profile_name .. ".yml"),
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = 0x0006,
        },
        parent_device_id = parent.id,
        endpoints = {
            {
                endpoint_id = 0,
                clusters = { { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" } },
                device_types = { { device_type_id = 0x0016, device_type_revision = 1 } }
            },
            {
                endpoint_id = 8,
                clusters = {
                    {
                        cluster_id = clusters.Switch.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
                        attributes = {
                            [clusters.Switch.attributes.MultiPressMax.ID] = 2
                        }
                    }
                },
                device_types = { { device_type_id = 0x003B, device_type_revision = 1 } }
            },
            {
                endpoint_id = 9,
                clusters = {
                    {
                        cluster_id = clusters.Switch.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
                        attributes = {
                            [clusters.Switch.attributes.MultiPressMax.ID] = 2
                        }
                    }
                },
                device_types = { { device_type_id = 0x003B, device_type_revision = 1 } }
            },
            {
                endpoint_id = 12,
                clusters = {
                    {
                        cluster_id = clusters.WindowCovering.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        feature_map = clusters.WindowCovering.types.Feature.LIFT |
                                clusters.WindowCovering.types.Feature.POSITION_AWARE_LIFT |
                                clusters.WindowCovering.types.Feature.ABSOLUTE_POSITION,
                        attributes = {
                            [clusters.WindowCovering.attributes.OperationalStatus.ID] = 0x00,
                            [clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID] = 0x0000,
                        }
                    }
                },
                device_types = { { device_type_id = 0x0202, device_type_revision = 1 } }
            },
        }
    })
end

local function create_hager_pir_device(profile_name, parent)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 PIR with Buttons and Motion/Illuminance/Dimmer",
        profile = t_utils.get_profile_definition(profile_name .. ".yml"),
        type = "MATTER",
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = 0x0007,
        },
        parent_device_id = parent.id,
        endpoints = {
            {
                endpoint_id = 0,
                clusters = { { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" } },
                device_types = { { device_type_id = 0x0016, device_type_revision = 1 } }
            },
            {
                endpoint_id = 3,
                clusters = {
                    {
                        cluster_id = clusters.OnOff.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        attributes = {
                            [clusters.OnOff.attributes.OnOff.ID] = false
                        }
                    },
                    {
                        cluster_id = clusters.LevelControl.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        attributes = {
                            [clusters.LevelControl.attributes.CurrentLevel.ID] = 254
                        }
                    }
                },
                device_types = { { device_type_id = 0x0101, device_type_revision = 1 } }
            },
            {
                endpoint_id = 4,
                clusters = {
                    {
                        cluster_id = clusters.OccupancySensing.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        attributes = {
                            [clusters.OccupancySensing.attributes.Occupancy.ID] = 0
                        }
                    }
                },
                device_types = { { device_type_id = 0x0107, device_type_revision = 1 } }
            },
            {
                endpoint_id = 5,
                clusters = {
                    {
                        cluster_id = clusters.IlluminanceMeasurement.ID,
                        cluster_type = "SERVER",
                        cluster_revision = 1,
                        attributes = {
                            [clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID] = 0
                        }
                    }
                },
                device_types = { { device_type_id = 0x0106, device_type_revision = 1 } }
            },
        }
    })
end

local function add_parent_device(parent)
    test.mock_device.add_test_device(parent)
    test.socket.device_lifecycle:__queue_receive({ parent.id, "added" })
    test.socket.device_lifecycle:__queue_receive({ parent.id, "init" })
    test.mock_time.advance_time(5)
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 2, descriptor.ID, descriptor.attributes.PartsList.ID, nil)
    })
end

local function subscribe_switch_events(parent, button_eps)
    for _, ep in ipairs(button_eps) do
        test.socket.matter:__expect_send({
            parent.id,
            clusters.Switch.events.MultiPressComplete:subscribe(parent, ep)
        })
        test.socket.matter:__expect_send({
            parent.id,
            clusters.Switch.events.LongPress:subscribe(parent, ep)
        })
    end
end

local function add_matter_device(matter_device, parent)
    test.mock_device.add_test_device(matter_device)
    test.socket.device_lifecycle:__queue_receive({ matter_device.id, "added" })
    test.socket.device_lifecycle:__queue_receive({ matter_device.id, "init" })

    matter_device:set_field(PARENT_ID, parent.id, { persist = true })
    matter_device:set_field(MATTER_DEVICE_ID, matter_device.id, { persist = true })
    parent:set_field(PARENT_ID, parent.id, { persist = true })
    parent:set_field(MATTER_DEVICE_ID, matter_device.id, { persist = true })
end

local function button_supported_values (matter_device)
    test.socket.capability:__expect_send(matter_device:generate_test_message("main", capabilities.button.supportedButtonValues({ "pushed", "double", "held" })))
    test.socket.capability:__expect_send(matter_device:generate_test_message("button2", capabilities.button.supportedButtonValues({ "pushed", "double", "held" })))
    test.socket.capability:__expect_send(matter_device:generate_test_message("button3", capabilities.button.supportedButtonValues({ "pushed", "double", "held" })))
    test.socket.capability:__expect_send(matter_device:generate_test_message("button4", capabilities.button.supportedButtonValues({ "pushed", "double", "held" })))
end

local function configure_parent(device)
    test.socket.device_lifecycle:__queue_receive({ device.id, "doConfigure" })

    device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function configure_matter_device(matter_device, expected_profile_change)
    test.socket.device_lifecycle:__queue_receive({ matter_device.id, "doConfigure" })
    matter_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end
-- Global parent device for tests
local parent = create_parent_device(0x0006)  -- 2G button product
local parent_1g = create_parent_device(0x0005)  -- 1G button product
local parent_pir = create_parent_device(0x0007)  -- PIR product

local function test_init()
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
end

test.set_test_init_function(test_init)

test.register_coroutine_test("Test: 4-Button Device Detection - Profile Changes from matter-bridge to 4-button When Four Button Endpoints Present", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    add_parent_device(parent)
    local matter_device = create_matter_device("matter-bridge", parent)

    -- Initialize HOST device
    add_matter_device(matter_device, parent)

    matter_device:expect_metadata_update({ profile = "4-button" })

    test.wait_for_events()

    local matter_device_parent_id = matter_device:get_field(PARENT_ID)
    local matter_device_id = matter_device:get_field(MATTER_DEVICE_ID)
    local parent_id = parent:get_field(PARENT_ID)
    local parent_matter_device_id = parent:get_field(MATTER_DEVICE_ID)

    assert(matter_device_parent_id == parent.id, "link_host_and_subhub 1/4")
    assert(matter_device_id == matter_device.id, "link_host_and_subhub 2/4")
    assert(parent_id == parent.id, "link_host_and_subhub 3/4")
    assert(parent_matter_device_id == matter_device.id, "link_host_and_subhub 4/4")

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
            data_types.Uint16(10),
            data_types.Uint16(11),
        }))
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 0x08)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 0x09)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 0x0A)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 0x0B)
    })
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 8, data_types.Array({
            { device_type = 0x000F, revision = 0x0003 }
        }))
    })
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 9, data_types.Array({
            { device_type = 0x000F, revision = 0x0003 }
        }))
    })
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 10, data_types.Array({
            { device_type = 0x000F, revision = 0x0003 }
        }))
    })
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 11, data_types.Array({
            { device_type = 0x000F, revision = 0x0003 }
        }))
    })
end)

test.register_coroutine_test("Test: Button Event Handling - Pushed, Double Press, and Held Events on 4-Button Device", function()
    -- Create HOST device with 4-button profile
    test.socket.matter:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")

    add_parent_device(parent)
    local matter_device = create_matter_device("4-button", parent)

    add_matter_device(matter_device, parent)
    matter_device:expect_metadata_update({ profile = "4-button" })

    -- Configure both devices
    configure_parent(parent)
    configure_matter_device(matter_device, "4-button")

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
            data_types.Uint16(10),
            data_types.Uint16(11),
        }))
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 0x08)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 0x09)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 0x0A)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 0x0B)
    })
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 8, data_types.Array({
            { device_type = 0x000F, revision = 0x0003 }
        }))
    })
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 9, data_types.Array({
            { device_type = 0x000F, revision = 0x0003 }
        }))
    })
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 10, data_types.Array({
            { device_type = 0x000F, revision = 0x0003 }
        }))
    })
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 11, data_types.Array({
            { device_type = 0x000F, revision = 0x0003 }
        }))
    })
    test.wait_for_events()
    local button_eps = parent:get_field(BUTTON_EPS)
    assert(#button_eps ~= 4, "Expected 4 button endpoints")
    assert(button_eps[1] == 8, "Expected button endpoint 1 to be 8")
    assert(button_eps[2] == 9, "Expected button endpoint 2 to be 9")
    assert(button_eps[3] == 10, "Expected button endpoint 3 to be 10")
    assert(button_eps[4] == 11, "Expected button endpoint 4 to be 11")

    test.socket.device_lifecycle:__queue_receive(matter_device:generate_info_changed({ profile = { id = "matter-bridge" } }))
    test.socket.device_lifecycle:__queue_receive(matter_device:generate_info_changed({ profile = { id = "4-button" } }))

    test.mock_time.advance_time(3)
    subscribe_switch_events(parent, button_eps)
    button_supported_values(matter_device)


    -- Test single press (pushed) on endpoint 8 (button1)
    test.wait_for_events()
    test.socket.matter:__queue_receive({
        matter_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
                matter_device, 8, {
                    new_position = 1,
                    previous_position = 1,
                    total_number_of_presses_counted = 1  -- Single press
                }
        )
    })
    test.socket.capability:__expect_send(matter_device:generate_test_message("main", capabilities.button.button.pushed({ state_change = true })))
    --
    --Test double press on endpoint 8 (button1)
    test.socket.matter:__queue_receive({
        matter_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
                matter_device, 8, {
                    new_position = 1,
                    previous_position = 1,
                    total_number_of_presses_counted = 2
                }
        )
    })
    test.socket.capability:__expect_send(matter_device:generate_test_message("main", capabilities.button.button.double({ state_change = true })))
    test.socket.matter:__queue_receive({
        matter_device.id,
        clusters.Switch.events.LongPress:build_test_event_report(
                matter_device, 8, {
                    new_position = 1,
                    previous_position = 0,
                }
        )
    })
    test.socket.capability:__expect_send(matter_device:generate_test_message("main", capabilities.button.button.held({ state_change = true })))

    -- Test press on endpoint 9 (button2)
    test.socket.matter:__queue_receive({
        matter_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
                matter_device, 9, {
                    new_position = 1,
                    previous_position = 1,
                    total_number_of_presses_counted = 1
                }
        )
    })
    test.socket.capability:__expect_send(matter_device:generate_test_message("button2", capabilities.button.button.pushed({ state_change = true })))
    test.socket.matter:__queue_receive({
        matter_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
                matter_device, 9, {
                    new_position = 1,
                    previous_position = 1,
                    total_number_of_presses_counted = 2
                }
        )
    })
    test.socket.capability:__expect_send(matter_device:generate_test_message("button2", capabilities.button.button.double({ state_change = true })))
    test.socket.matter:__queue_receive({
        matter_device.id,
        clusters.Switch.events.LongPress:build_test_event_report(
                matter_device, 9, {
                    new_position = 1,
                    previous_position = 0,
                }
        )
    })
    test.socket.capability:__expect_send(matter_device:generate_test_message("button2", capabilities.button.button.held({ state_change = true })))

    -- Test press on endpoint 10 (button3)
    test.socket.matter:__queue_receive({
        matter_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
                matter_device, 10, {
                    new_position = 1,
                    previous_position = 1,
                    total_number_of_presses_counted = 1
                }
        )
    })
    test.socket.capability:__expect_send(matter_device:generate_test_message("button3", capabilities.button.button.pushed({ state_change = true })))
    test.socket.matter:__queue_receive({
        matter_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
                matter_device, 10, {
                    new_position = 1,
                    previous_position = 1,
                    total_number_of_presses_counted = 2
                }
        )
    })
    test.socket.capability:__expect_send(matter_device:generate_test_message("button3", capabilities.button.button.double({ state_change = true })))
    test.socket.matter:__queue_receive({
        matter_device.id,
        clusters.Switch.events.LongPress:build_test_event_report(
                matter_device, 10, {
                    new_position = 1,
                    previous_position = 0,
                }
        )
    })
    test.socket.capability:__expect_send(matter_device:generate_test_message("button3", capabilities.button.button.held({ state_change = true })))

    -- Test press on endpoint 11 (button4)
    test.socket.matter:__queue_receive({
        matter_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
                matter_device, 11, {
                    new_position = 1,
                    previous_position = 1,
                    total_number_of_presses_counted = 1
                }
        )
    })
    test.socket.capability:__expect_send(matter_device:generate_test_message("button4", capabilities.button.button.pushed({ state_change = true })))
    test.socket.matter:__queue_receive({
        matter_device.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
                matter_device, 11, {
                    new_position = 1,
                    previous_position = 1,
                    total_number_of_presses_counted = 2
                }
        )
    })
    test.socket.capability:__expect_send(matter_device:generate_test_message("button4", capabilities.button.button.double({ state_change = true })))
    test.socket.matter:__queue_receive({
        matter_device.id,
        clusters.Switch.events.LongPress:build_test_event_report(
                matter_device, 11, {
                    new_position = 1,
                    previous_position = 0,
                }
        )
    })
    test.socket.capability:__expect_send(matter_device:generate_test_message("button4", capabilities.button.button.held({ state_change = true })))

end)

test.register_coroutine_test("Test: Device Type Handler - Handles Button (Type 15) and OnOff (Type 256) Device Types with Child Creation", function()
    test.socket.matter:__set_channel_ordering("relaxed")

    local matter_device = create_matter_device("4-button", parent)
    add_parent_device(parent)

    add_matter_device(matter_device, parent)
    matter_device:expect_metadata_update({ profile = "4-button" })

    -- Configure both devices
    configure_parent(parent)
    configure_matter_device(matter_device, "4-button")

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(9),
            data_types.Uint16(8),
            data_types.Uint16(6),
        }))
    })

    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 9)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 8)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 6)
    })

    test.wait_for_events()

    -- Receive DeviceTypeList report with device type 15 (button) for endpoint 8
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 8, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })

    -- Receive DeviceTypeList report with device type 256 (OnOff) for endpoint 6
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 6, data_types.Array {
            {
                device_type = data_types.Uint32(256),
                revision = data_types.Uint16(1)
            }
        })
    })
    parent:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button 1",
        profile = "light-binary",
        parent_device_id = parent.id,
        parent_assigned_child_key = "6"
    })

end)

test.register_coroutine_test("Test: 2G Relay - Profile Changes Between light-binary and 2-button Based On Endpoint Availability", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    add_parent_device(parent)

    local relay = create_hager_2g_relay("matter-bridge", parent)
    add_matter_device(relay, parent)
    configure_parent(parent)
    configure_matter_device(relay, "light-binary")
    relay:expect_metadata_update({ profile = "light-binary" })
    test.wait_for_events()
    -- Scenario 1: EP3 + EP4 present → light-binary profile
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(3),
            data_types.Uint16(4),
        }))
    })

    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 3)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 4)
    })
    relay:expect_metadata_update({ profile = "light-binary" })
    test.wait_for_events()
    ---- Both endpoints are device type 256 (OnOff)
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 3, data_types.Array {
            {
                device_type = data_types.Uint32(256),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 4, data_types.Array {
            {
                device_type = data_types.Uint32(256),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__expect_send({
        parent.id,
        clusters.OnOff.attributes.OnOff:subscribe(parent, 3)
    })

    parent:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button 1",
        profile = "light-binary",
        parent_device_id = parent.id,
        parent_assigned_child_key = "4"
    })

     --Scenario 2: EP4 removed → profile changes to 2-button, child created for EP3
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(3),
            data_types.Uint16(8),
            data_types.Uint16(9),
        }))
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 9)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 8)
    })

    parent:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button 1",
        profile = "light-binary",
        parent_device_id = parent.id,
        parent_assigned_child_key = "3"
    })

    relay:expect_metadata_update({ profile = "2-button" })

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 8, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 9, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })


    -- Scenario 3: EP4 reappears → profile changes back to light-binary
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(3),
            data_types.Uint16(4),
        }))
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 4)
    })
    relay:expect_metadata_update({ profile = "light-binary" })

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 4, data_types.Array {
            {
                device_type = data_types.Uint32(256),
                revision = data_types.Uint16(1)
            }
        })
    })

    parent:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button 1",
        profile = "light-binary",
        parent_device_id = parent.id,
        parent_assigned_child_key = "4"
    })

    -- Scenario 4: EP3 removed → profile changes to 2-button, child created for EP4
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(4),
            data_types.Uint16(12),
            data_types.Uint16(13),
        }))
    })

    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 12)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 13)
    })
    relay:expect_metadata_update({ profile = "2-button" })

    -- Scenario 5: EP3 and EP4 removed → 4-button profile
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
            data_types.Uint16(10),
            data_types.Uint16(11),
        }))
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 8)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 9)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 10)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 11)
    })
    relay:expect_metadata_update({ profile = "4-button" })

    -- Scenario 6: Only EP4 present → 2-button profile, child created
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(4),
            data_types.Uint16(8),
            data_types.Uint16(9),
        }))
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 4)
    })
    relay:expect_metadata_update({ profile = "2-button" })

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 4, data_types.Array {
            {
                device_type = data_types.Uint32(256),
                revision = data_types.Uint16(1)
            }
        })
    })

    parent:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button 1",
        profile = "light-binary",
        parent_device_id = parent.id,
        parent_assigned_child_key = "4"
    })
end)

test.register_coroutine_test("Test: Dimmer Device - Child Creation for Dimmable Endpoint with Button Support", function()
    test.socket.matter:__set_channel_ordering("relaxed")

    local dimmer = create_hager_dimmer_device_2g("matter-bridge", parent)
    add_parent_device(parent)

    add_matter_device(dimmer, parent)
    dimmer:expect_metadata_update({ profile = "2-button" })
    configure_parent(parent)
    configure_matter_device(dimmer, "2-button")
    test.wait_for_events()

    -- Scenario 1: 2 button endpoints (8, 9) detected → 2-button profile
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
            data_types.Uint16(3)
        }))
    })

    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 8)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 9)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 3)
    })
    dimmer:expect_metadata_update({ profile = "2-button" })

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 3, data_types.Array {
            {
                device_type = data_types.Uint32(257),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 3, clusters.OnOff.ID, clusters.OnOff.attributes.OnOff.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 3, clusters.LevelControl.ID, clusters.LevelControl.attributes.CurrentLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 3, clusters.LevelControl.ID, clusters.LevelControl.attributes.MaxLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 3, clusters.LevelControl.ID, clusters.LevelControl.attributes.MinLevel.ID, nil)
    })

    parent:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button 1",
        profile = "light-level",
        parent_device_id = parent.id,
        parent_assigned_child_key = "3"
    })

    -- Create mock child device for EP3
    local child_dimmer = test.mock_device.build_test_child_device({
        profile = t_utils.get_profile_definition("light-level.yml"),
        device_network_id = string.format("%s:3", parent.id),
        parent_device_id = parent.id,
        parent_assigned_child_key = "3"
    })

    test.socket.capability:__queue_receive({ child_dimmer.id, { capability = "switch", component = "main", command = "on", args = {} } })--

    test.socket.capability:__queue_receive({ child_dimmer.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 20 } } })

end)

test.register_coroutine_test("Test: 1G Dimmer - Initialization and Profile Update to light-level", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    add_parent_device(parent_1g)

    local dimmer = create_hager_dimmer_device_1g("matter-bridge", parent_1g)
    add_matter_device(dimmer, parent_1g)
    dimmer:expect_metadata_update({ profile = "light-level" })
    configure_parent(parent_1g)
    configure_matter_device(dimmer, "light-level")
    test.wait_for_events()

end)

test.register_coroutine_test("Test: 1G Dimmer - Host Commands and Level Control Capabilities", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")
    add_parent_device(parent_1g)
    local dimmer = create_hager_dimmer_device_1g("light-level", parent_1g)
    add_matter_device(dimmer, parent_1g)
    dimmer:expect_metadata_update({ profile = "light-level" })
    configure_parent(parent_1g)
    configure_matter_device(dimmer, "light-level")
    test.wait_for_events()
    test.wait_for_events()

    -- Send dimmable endpoint 4 detection (device type 257) to trigger profile change and subscriptions
    test.socket.matter:__queue_receive({
        parent_1g.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent_1g, 2, data_types.Array({
            data_types.Uint16(4),
        }))
    })

    test.socket.matter:__expect_send({
        parent_1g.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent_1g, 4)
    })

    test.wait_for_events()

    test.socket.matter:__queue_receive({
        parent_1g.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent_1g, 4, data_types.Array {
            {
                device_type = data_types.Uint32(257),
                revision = data_types.Uint16(1)
            }
        })
    })

    --subscriptions from device_type_handler
    test.socket.matter:__expect_send({
        parent_1g.id,
        cluster_base.subscribe(parent_1g, 4, clusters.OnOff.ID, clusters.OnOff.attributes.OnOff.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent_1g.id,
        cluster_base.subscribe(parent_1g, 4, clusters.LevelControl.ID, clusters.LevelControl.attributes.CurrentLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent_1g.id,
        cluster_base.subscribe(parent_1g, 4, clusters.LevelControl.ID, clusters.LevelControl.attributes.MaxLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent_1g.id,
        cluster_base.subscribe(parent_1g, 4, clusters.LevelControl.ID, clusters.LevelControl.attributes.MinLevel.ID, nil)
    })

    test.socket.device_lifecycle:__queue_receive(dimmer:generate_info_changed({ profile = { id = "matter-bridge" } }))
    test.socket.device_lifecycle:__queue_receive(dimmer:generate_info_changed({ profile = { id = "light-level" } }))

    -- Trigger 3-second delay in device_init to change FIELD_MAIN_ONOFF_EP from 3 to 4
    test.mock_time.advance_time(3)
    test.socket.matter:__expect_send({ parent_1g.id, clusters.OnOff.attributes.OnOff:read(parent_1g) })
    test.socket.matter:__expect_send({ parent_1g.id, clusters.LevelControl.attributes.CurrentLevel:read(parent_1g) })

end)

test.register_coroutine_test("Test: PIR Device - Initialization with Motion and Illuminance Capabilities", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    add_parent_device(parent_pir)
    local pir_device = create_hager_pir_device("matter-bridge", parent_pir)

    add_matter_device(pir_device, parent_pir)
    pir_device:expect_metadata_update({ profile = "motion-illuminance" })
    configure_parent(parent_pir)
    configure_matter_device(pir_device, nil)

end)

test.register_coroutine_test("Test: PIR Device - Complete Functionality with Motion, Illuminance, and Dimmer Support", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")

    add_parent_device(parent_pir)
    local pir_device = create_hager_pir_device("motion-illuminance", parent_pir)
    add_matter_device(pir_device, parent_pir)
    pir_device:expect_metadata_update({ profile = "motion-illuminance" })

    test.wait_for_events()
    configure_parent(parent_pir)
    configure_matter_device(pir_device, nil)
    test.mock_time.advance_time(5)
    test.wait_for_events()

    test.socket.matter:__queue_receive({
        parent_pir.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent_pir, 2, data_types.Array({
            data_types.Uint16(3),
            data_types.Uint16(4),
            data_types.Uint16(5)

        }))
    })
    test.socket.matter:__expect_send({
        parent_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent_pir, 3)
    })
    test.socket.matter:__expect_send({
        parent_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent_pir, 4)
    })
    test.socket.matter:__expect_send({
        parent_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent_pir, 5)
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
        parent_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent_pir, 4, data_types.Array {
            {
                device_type = data_types.Uint32(263),
                revision = data_types.Uint16(1)
            }
        })
    })
    test.socket.matter:__queue_receive({
        parent_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent_pir, 5, data_types.Array {
            {
                device_type = data_types.Uint32(262),
                revision = data_types.Uint16(1)
            }
        })
    })
    test.socket.matter:__queue_receive({
        parent_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent_pir, 3, data_types.Array {
            {
                device_type = data_types.Uint32(257),
                revision = data_types.Uint16(1)
            }
        })
    })
    test.socket.matter:__expect_send({
        parent_pir.id,
        cluster_base.subscribe(parent_pir, 4, clusters.OccupancySensing.ID, clusters.OccupancySensing.attributes.Occupancy.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent_pir.id,
        cluster_base.subscribe(parent_pir, 5, clusters.IlluminanceMeasurement.ID, clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent_pir.id,
        cluster_base.subscribe(parent_pir, 3, clusters.OnOff.ID, clusters.OnOff.attributes.OnOff.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent_pir.id,
        cluster_base.subscribe(parent_pir, 3, clusters.LevelControl.ID, clusters.LevelControl.attributes.CurrentLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent_pir.id,
        cluster_base.subscribe(parent_pir, 3, clusters.LevelControl.ID, clusters.LevelControl.attributes.MaxLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent_pir.id,
        cluster_base.subscribe(parent_pir, 3, clusters.LevelControl.ID, clusters.LevelControl.attributes.MinLevel.ID, nil)
    })
    test.socket.device_lifecycle:__queue_receive(pir_device:generate_info_changed({ profile = { id = "matter-bridge" } }))
    test.socket.device_lifecycle:__queue_receive(pir_device:generate_info_changed({ profile = { id = "motion-illuminance" } }))

    test.mock_time.advance_time(3)

    test.socket.matter:__expect_send({
        parent_pir.id,
        clusters.OccupancySensing.attributes.Occupancy:read(parent_pir)
    })
    test.socket.matter:__expect_send({
        parent_pir.id,
        clusters.OccupancySensing.attributes.Occupancy:read(parent_pir)
    })
    test.socket.matter:__expect_send({
        parent_pir.id,
        clusters.IlluminanceMeasurement.attributes.MeasuredValue:read(parent_pir)
    })
    test.socket.matter:__expect_send({
        parent_pir.id,
        clusters.IlluminanceMeasurement.attributes.MeasuredValue:read(parent_pir)
    })

    parent_pir:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button 1",
        profile = "light-level",
        parent_device_id = parent_pir.id,
        parent_assigned_child_key = "3"
    })
    local child_dimmer = test.mock_device.build_test_child_device({
        label = "Hager G2 4x Button 1",
        profile = t_utils.get_profile_definition("light-level.yml"),
        device_network_id = string.format("%s:3", parent_pir.id),
        parent_device_id = parent_pir.id,
        parent_assigned_child_key = "3"

    })
    test.mock_device.add_test_device(child_dimmer)
    test.wait_for_events()
    -- Verify motion detected event
    test.socket.matter:__queue_receive({
        parent_pir.id,
        clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(parent_pir, 4, 1)
    })

    test.socket.capability:__expect_send(pir_device:generate_test_message("main", capabilities.motionSensor.motion.active()))

    -- Verify illuminance measurement event
    test.socket.matter:__queue_receive({
        parent_pir.id,
        clusters.IlluminanceMeasurement.attributes.MeasuredValue:build_test_report_data(parent_pir, 5, 21370)
    })
    test.socket.capability:__expect_send(pir_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance(137)))

    -- Send on command to OnOff endpoint (dimmer)
    child_dimmer.expect_native_cmd_handler_registration(child_dimmer, "switch", "on")

    test.socket.capability:__queue_receive({ child_dimmer.id, { capability = "switch", component = "main", command = "on", args = {} } })
    test.socket.matter:__expect_send({
        parent_pir.id,
        clusters.OnOff.commands.On(parent_pir, 3)
    })
    -- Verify on state via attribute report
    test.socket.matter:__queue_receive({
        parent_pir.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(parent_pir, 3, true)
    })
    test.socket.capability:__expect_send(child_dimmer:generate_test_message("main", capabilities.switch.switch.on()))
    parent_pir.expect_native_attr_handler_registration(parent_pir, "switch", "switch")

    -- Set dimmer level to 50%
    test.socket.capability:__queue_receive({ child_dimmer.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 50 } } })
    test.socket.matter:__expect_send({
        parent_pir.id,
        clusters.LevelControl.commands.MoveToLevelWithOnOff(parent_pir, 3, 127, nil, 0, 0)
    })
    child_dimmer.expect_native_cmd_handler_registration(child_dimmer, "switchLevel", "setLevel")

    -- Verify level via attribute report
    test.socket.matter:__queue_receive({
        parent_pir.id,
        clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(parent_pir, 3, 127)
    })
    test.socket.capability:__expect_send(child_dimmer:generate_test_message("main", capabilities.switchLevel.level(50)))
    parent_pir.expect_native_attr_handler_registration(parent_pir, "switchLevel", "level")

end)

test.register_coroutine_test("Test: Host with Window Covering - 2-Button Profile with Window Covering Child Device", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    add_parent_device(parent)
    test.wait_for_events()
    local window_covering_device = create_matter_device_with_window("2-button", parent)
    add_matter_device(window_covering_device, parent)
    window_covering_device:expect_metadata_update({ profile = "2-button" })
    configure_parent(parent)
    configure_matter_device(window_covering_device, "2-button")

    test.wait_for_events()

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
            data_types.Uint16(12),
        }))
    })

    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 8)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 9)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 12)
    })

    -- DeviceTypeList report for window covering endpoint (type 514 = Window Covering Device)
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 12, data_types.Array {
            {
                device_type = data_types.Uint32(514),
                revision = data_types.Uint16(1)
            }
        })
    })
    --
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 12, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.OperationalStatus.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 12, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID, nil)
    })

    parent:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button 1",
        profile = "window-covering",
        parent_device_id = parent.id,
        parent_assigned_child_key = "12"
    })

    local child_wc = test.mock_device.build_test_child_device({
        profile = t_utils.get_profile_definition("window-covering.yml"),
        device_network_id = string.format("%s:12", parent.id),
        parent_device_id = parent.id,
        parent_assigned_child_key = "12"
    })
    test.mock_device.add_test_device(child_wc)
    test.wait_for_events()

    -- Open command
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShade", component = "main", command = "open", args = {} } })
    test.socket.matter:__expect_send({ parent.id, clusters.WindowCovering.commands.UpOrOpen(parent, 12) })
    test.wait_for_events()

    -- Verify open state via attribute report
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.WindowCovering.attributes.OperationalStatus:build_test_report_data(parent, 12, 0x01)
    })
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShade.windowShade.opening()))


    -- Close command
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShade", component = "main", command = "close", args = {} } })
    test.socket.matter:__expect_send({ parent.id, clusters.WindowCovering.commands.DownOrClose(parent, 12) })

    -- Verify close state via attribute report
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.WindowCovering.attributes.OperationalStatus:build_test_report_data(parent, 12, 0x02)
    })
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShade.windowShade.closing()))

    -- Pause command
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShade", component = "main", command = "pause", args = {} } })
    test.socket.matter:__expect_send({ parent.id, clusters.WindowCovering.commands.StopMotion(parent, 12) })
    test.wait_for_events()

    -- Set shade level to 50%
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 50 } } })
    test.socket.matter:__expect_send({ parent.id, clusters.WindowCovering.commands.GoToLiftPercentage(parent, 12, 5000, nil, 0, 0) })
    test.wait_for_events()

    -- Verify shade level via attribute report
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(parent, 12, 5000)
    })
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50)))
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShade.windowShade.partially_open()))


    -- Set shade level to 100%
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 100 } } })
    test.socket.matter:__expect_send({ parent.id, clusters.WindowCovering.commands.GoToLiftPercentage(parent, 12, 0, nil, 0, 0) })
    test.wait_for_events()

    -- Verify shade level via attribute report
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(parent, 12, 0)
    })
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100)))
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShade.windowShade.open()))

    -- Set shade level to 0%
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 0 } } })
    test.socket.matter:__expect_send({ parent.id, clusters.WindowCovering.commands.GoToLiftPercentage(parent, 12, 10000, nil, 0, 0) })

    -- Verify shade level via attribute report
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(parent, 12, 10000)
    })
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0)))
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShade.windowShade.closed()))

end)

test.register_coroutine_test("Test: Window Covering - Preference Changes for Reverse Polarity and Preset Position", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    add_parent_device(parent)
    test.wait_for_events()
    local window_covering_device = create_matter_device_with_window("2-button", parent)
    add_matter_device(window_covering_device, parent)
    window_covering_device:expect_metadata_update({ profile = "2-button" })
    configure_parent(parent)
    configure_matter_device(window_covering_device, "2-button")

    test.wait_for_events()

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
            data_types.Uint16(12),
        }))
    })
    --
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 8)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 9)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 12)
    })
    test.wait_for_events()

    -- DeviceTypeList reports for button endpoints (type 15 = Generic Switch)
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 8, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 9, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })

    -- DeviceTypeList report for window covering endpoint (type 514 = Window Covering Device)
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 12, data_types.Array {
            {
                device_type = data_types.Uint32(514),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 12, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.OperationalStatus.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 12, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID, nil)
    })

    parent:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button 1",
        profile = "window-covering",
        parent_device_id = parent.id,
        parent_assigned_child_key = "12"
    })

    local child_wc = test.mock_device.build_test_child_device({
        profile = t_utils.get_profile_definition("window-covering.yml"),
        device_network_id = string.format("%s:12", parent.id),
        parent_device_id = parent.id,
        parent_assigned_child_key = "12"
    })
    test.mock_device.add_test_device(child_wc)

    test.socket.device_lifecycle():__queue_receive(child_wc:generate_info_changed({ preferences = { reverse = "false" } }))
    test.socket.device_lifecycle():__queue_receive(child_wc:generate_info_changed({ preferences = { reverse = "true" } }))
    test.wait_for_events()
    local reverse_preference_set = child_wc:get_field("__reverse_polarity")
    assert(reverse_preference_set == true, "reverse_preference_set is True")

    --Send open command - with reverse_polarity true, this should send DownOrClose
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShade", component = "main", command = "open", args = {} } })
    test.socket.matter:__expect_send({ parent.id, clusters.WindowCovering.commands.DownOrClose(parent, 12) })

    -- Send close command - with reverse_polarity true, this should send UpOrOpen
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShade", component = "main", command = "close", args = {} } })
    test.socket.matter:__expect_send({ parent.id, clusters.WindowCovering.commands.UpOrOpen(parent, 12) })

    -- Send Pause command
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShade", component = "main", command = "pause", args = {} } })
    test.socket.matter:__expect_send({ parent.id, clusters.WindowCovering.commands.StopMotion(parent, 12) })

    -- Position preset testing
    test.socket.device_lifecycle():__queue_receive(child_wc:generate_info_changed({ preferences = { presetPosition = "50" } }))
    test.socket.device_lifecycle():__queue_receive(child_wc:generate_info_changed({ preferences = { presetPosition = "20" } }))

    test.wait_for_events()

    local PRESET_LEVEL_KEY = child_wc:get_field("__preset_level_key")
    assert(PRESET_LEVEL_KEY == "20", " __preset_level_key is set to 20")

    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} } })
    test.socket.matter:__expect_send(
            { parent.id, clusters.WindowCovering.server.commands.GoToLiftPercentage(parent, 12, 8000) }
    )

    test.socket.device_lifecycle():__queue_receive(child_wc:generate_info_changed({ preferences = { presetPosition = "20" } }))

    test.wait_for_events()
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
        }))
    })

    test.wait_for_events()

    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.mock_time.advance_time(5)
    local BUTTON_EPS_FIELD = parent:get_field(BUTTON_EPS)
    assert(BUTTON_EPS_FIELD[1] == 8)
    assert(BUTTON_EPS_FIELD[2] == 9)

    test.wait_for_events()
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
            data_types.Uint16(12),
        }))
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 12)
    })
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 12, data_types.Array {
            {
                device_type = data_types.Uint32(514),
                revision = data_types.Uint16(1)
            }
        })
    })
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 12, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.OperationalStatus.ID, nil)
    })
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 12, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID, nil)
    })
    child_wc:expect_metadata_update({ profile = "window-covering" })
end)

test.register_coroutine_test("Test: info_changed - Profile Change from 4-button to 2-button Triggers Button Reconfiguration", function()

    test.socket.matter:__set_channel_ordering("relaxed")
    add_parent_device(parent)
    test.wait_for_events()
    local matter_device = create_matter_device("4-button", parent)
    add_matter_device(matter_device, parent)
    matter_device:expect_metadata_update({ profile = "4-button" })
    configure_parent(parent)
    configure_matter_device(matter_device, "4-button")

    test.wait_for_events()

    local device_info_copy = st_utils.deep_copy(matter_device.raw_st_data)
    device_info_copy.profile.id = "4-button"
    local device_info_json = dkjson.encode(device_info_copy)
    test.socket.device_lifecycle:__queue_receive({ matter_device.id, "infoChanged", device_info_json })

    -- Scenario 1: EP3 (onoff) + EP8, EP9 (buttons) present → 2-button profile
    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(parent, 2, data_types.Array({
            data_types.Uint16(3),
            data_types.Uint16(8),
            data_types.Uint16(9),
        }))
    })

    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 3)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 8)
    })
    test.socket.matter:__expect_send({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(parent, 9)
    })

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 8, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__queue_receive({
        parent.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(parent, 9, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })
    matter_device:expect_metadata_update({ profile = "2-button" })
    parent:set_field(BUTTON_EPS, { 8, 9 }, { persist = true })

    test.wait_for_events()
    device_info_copy.profile.id = "2-button"
    device_info_json = dkjson.encode(device_info_copy)
    test.socket.device_lifecycle:__queue_receive({ matter_device.id, "infoChanged", device_info_json })

    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.mock_time.advance_time(5)
    test.socket.capability:__expect_send(matter_device:generate_test_message("main", capabilities.button.supportedButtonValues({ "pushed", "double", "held" })))
    test.socket.capability:__expect_send(matter_device:generate_test_message("button2", capabilities.button.supportedButtonValues({ "pushed", "double", "held" })))

    -- Expect Switch event subscriptions for button endpoints (8, 9)
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 8, clusters.Switch.ID, nil, clusters.Switch.events.MultiPressComplete.ID)
    })
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 8, clusters.Switch.ID, nil, clusters.Switch.events.LongPress.ID)
    })
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 9, clusters.Switch.ID, nil, clusters.Switch.events.MultiPressComplete.ID)
    })
    test.socket.matter:__expect_send({
        parent.id,
        cluster_base.subscribe(parent, 9, clusters.Switch.ID, nil, clusters.Switch.events.LongPress.ID)
    })
end)

test.run_registered_tests()
