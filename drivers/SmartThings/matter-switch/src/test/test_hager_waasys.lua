-- Copyright © 2025 SmartThings, Inc.
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

local HOST_ID = "HOST_ID"
local SUBHUB_ID = "SUBHUB_ID"
local BUTTON_EPS = "__button_eps"

test.disable_startup_messages()
test.socket.matter:__set_channel_ordering("relaxed")

local function create_subhub_device(product_id)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 4x Button Subhub",
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

local function add_subhub_device(subhub)
    test.mock_device.add_test_device(subhub)
    test.socket.device_lifecycle:__queue_receive({ subhub.id, "added" })
    test.socket.device_lifecycle:__queue_receive({ subhub.id, "init" })
    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 2, descriptor.ID, descriptor.attributes.PartsList.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 0, descriptor.ID, descriptor.attributes.PartsList.ID, nil)
    })
end

local function create_host_device(profile_name, parent_subhub)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 4x Button Host",
        profile = t_utils.get_profile_definition(profile_name .. ".yml"),
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = 0x0006,
        },
        parent_device_id = parent_subhub.id,
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
local function create_hager_2g_relay(profile_name, parent_subhub)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 2G Relay",
        profile = t_utils.get_profile_definition(profile_name .. ".yml"),
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = 0x0006,
        },
        parent_device_id = parent_subhub.id,
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
local function create_hager_dimmer_device_1g(profile_name, parent_subhub)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 Dimmer Host Only",
        profile = t_utils.get_profile_definition(profile_name .. ".yml"),
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = 0x0005,
        },
        parent_device_id = parent_subhub.id,
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
                device_types = { { device_type_id = 0x0101, device_type_revision = 1 } } -- Dimmable Light
            },
        }
    })
end

-- Create Hager Dimmer device with 2 button endpoints (8, 9) + 1 dimmable OnOff endpoint (3)
local function create_hager_dimmer_device_2g(profile_name, parent_subhub)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 Dimmer Host Only",
        profile = t_utils.get_profile_definition(profile_name .. ".yml"),
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = 0x0006,
        },
        parent_device_id = parent_subhub.id,
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

local function subscribe_switch_events(host)
    local CLUSTER_SUBSCRIBE_LIST = {
        clusters.Switch.server.events.InitialPress,
        clusters.Switch.server.events.LongPress,
        clusters.Switch.server.events.ShortRelease,
        clusters.Switch.server.events.MultiPressComplete,
    }

    local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(host)
    for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
        if i > 1 then
            subscribe_request:merge(clus:subscribe(host))
        end
    end

    test.socket.matter:__expect_send({ host.id, subscribe_request })
end

local function subscribe_dimmer_attr(host)
    local CLUSTER_SUBSCRIBE_LIST = {

        clusters.OnOff.attributes.OnOff,
        clusters.LevelControl.attributes.CurrentLevel,
        clusters.LevelControl.attributes.MaxLevel,
        clusters.LevelControl.attributes.MinLevel,
    }

    local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(host)
    for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
        if i > 1 then
            subscribe_request:merge(clus:subscribe(host))
        end
    end

    test.socket.matter:__expect_send({ host.id, subscribe_request })
end

-- Initialize HOST device (add to test, queue lifecycle events, link to SUBHUB)
local function four_button_2g_button_init(host)
    test.socket.capability:__expect_send(host:generate_test_message("main", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("main", capabilities.button.button.pushed({ state_change = false })))

    test.socket.capability:__expect_send(host:generate_test_message("button2", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("button2", capabilities.button.button.pushed({ state_change = false })))

    test.socket.capability:__expect_send(host:generate_test_message("button3", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("button3", capabilities.button.button.pushed({ state_change = false })))

    test.socket.capability:__expect_send(host:generate_test_message("button4", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("button4", capabilities.button.button.pushed({ state_change = false })))
end

local function add_host_device(host, parent_subhub)
    test.mock_device.add_test_device(host)
    test.socket.device_lifecycle:__queue_receive({ host.id, "added" })
    test.socket.device_lifecycle:__queue_receive({ host.id, "init" })

    host:set_field(SUBHUB_ID, parent_subhub.id, { persist = true })
    host:set_field(HOST_ID, host.id, { persist = true })
    parent_subhub:set_field(SUBHUB_ID, parent_subhub.id, { persist = true })
    parent_subhub:set_field(HOST_ID, host.id, { persist = true })
end

local function button_supported_values (host)
    test.socket.capability:__expect_send(host:generate_test_message("main", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("main", capabilities.button.button.pushed({ state_change = false })))

    test.socket.capability:__expect_send(host:generate_test_message("button2", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("button2", capabilities.button.button.pushed({ state_change = false })))

    test.socket.capability:__expect_send(host:generate_test_message("button3", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("button3", capabilities.button.button.pushed({ state_change = false })))

    test.socket.capability:__expect_send(host:generate_test_message("button4", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("button4", capabilities.button.button.pushed({ state_change = false })))
end

local function configure_subhub(device)
    test.socket.device_lifecycle:__queue_receive({ device.id, "doConfigure" })

    device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function configure_host(host, expected_profile_change)
    test.socket.device_lifecycle:__queue_receive({ host.id, "doConfigure" })

    if expected_profile_change then
        host:expect_metadata_update({ profile = expected_profile_change })
    end

    host:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.socket.matter:__expect_send({
        host.id,
        cluster_base.subscribe(host, 2, descriptor.ID, descriptor.attributes.PartsList.ID, nil)
    })
    test.socket.matter:__expect_send({
        host.id,
        cluster_base.subscribe(host, 0, descriptor.ID, descriptor.attributes.PartsList.ID, nil)
    })
end

-- Create Hager PIR device with 2 button endpoints + motion/illuminance/dimmer endpoint
local function create_hager_pir_device(profile_name, parent_subhub)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 PIR with Buttons and Motion/Illuminance/Dimmer",
        profile = t_utils.get_profile_definition(profile_name .. ".yml"),
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = 0x0007,
        },
        parent_device_id = parent_subhub.id,
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

-- Global subhub for tests
local subhub = create_subhub_device(0x0006)  -- 2G button product
local subhub_1g = create_subhub_device(0x0005)  -- 1G button product
local subhub_pir = create_subhub_device(0x0007)  -- PIR product

local function test_init()
    add_subhub_device(subhub)
    add_subhub_device(subhub_1g)
    add_subhub_device(subhub_pir)
end

test.set_test_init_function(test_init)

test.register_coroutine_test("Test: 4-Button Device Detection - Profile Changes from matter-bridge to 4-button When Four Button Endpoints Present", function()
    test.socket.matter:__set_channel_ordering("relaxed")

    local host = create_host_device("matter-bridge", subhub)

    -- Initialize HOST device
    add_host_device(host, subhub)

    -- Configure both devices
    configure_subhub(subhub)
    configure_host(host, "4-button")

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 0, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
            data_types.Uint16(10),
            data_types.Uint16(11),
        }))
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 0x08)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 0x09)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 0x0A)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 0x0B)
    })
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 8, data_types.Array({
            { device_type = 0x000F, revision = 0x0003 }
        }))
    })
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 9, data_types.Array({
            { device_type = 0x000F, revision = 0x0003 }
        }))
    })
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 10, data_types.Array({
            { device_type = 0x000F, revision = 0x0003 }
        }))
    })
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 11, data_types.Array({
            { device_type = 0x000F, revision = 0x0003 }
        }))
    })
end)

test.register_coroutine_test("Test: Button Event Handling - Pushed, Double Press, and Held Events on 4-Button Device", function()
    -- Create HOST device with 4-button profile
    test.socket.matter:__set_channel_ordering("relaxed")

    local host = create_host_device("4-button", subhub)

    -- Initialize HOST device
    add_host_device(host, subhub)

    -- Configure both devices
    configure_subhub(subhub)
    configure_host(host, "4-button")

    subscribe_switch_events(host)

    test.socket.capability:__expect_send(host:generate_test_message("main", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("main", capabilities.button.button.pushed({ state_change = false })))

    test.socket.capability:__expect_send(host:generate_test_message("button2", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("button2", capabilities.button.button.pushed({ state_change = false })))

    test.socket.capability:__expect_send(host:generate_test_message("button3", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("button3", capabilities.button.button.pushed({ state_change = false })))

    test.socket.capability:__expect_send(host:generate_test_message("button4", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("button4", capabilities.button.button.pushed({ state_change = false })))
    test.wait_for_events()

    -- Test single press (pushed) on endpoint 8 (button1)
    test.socket.matter:__queue_receive({
        host.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
                host, 8, { new_position = 1 }
        )
    })

    test.socket.capability:__expect_send(host:generate_test_message("main", capabilities.button.button.pushed({ state_change = true })))

    --Test double press on endpoint 8 (button1)
    test.socket.matter:__queue_receive({
        host.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
                host, 8, { new_position = 0, total_number_of_presses_counted = 2, previous_position = 1 }
        )
    })

    test.socket.capability:__expect_send(host:generate_test_message("main", capabilities.button.button.double({ state_change = true })))
    test.socket.matter:__queue_receive({
        host.id,
        clusters.Switch.events.LongPress:build_test_event_report(
                host, 8, { new_position = 1 }
        )
    })
    test.socket.capability:__expect_send(host:generate_test_message("main", capabilities.button.button.held({ state_change = true })))

    -- Test long press (held) on endpoint 9 (button2)
    test.socket.matter:__queue_receive({
        host.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
                host, 9, { new_position = 1 }
        )
    })
    test.socket.capability:__expect_send(host:generate_test_message("button2", capabilities.button.button.pushed({ state_change = true })))
    test.socket.matter:__queue_receive({
        host.id,
        clusters.Switch.events.LongPress:build_test_event_report(
                host, 9, { new_position = 1 }
        )
    })
    test.socket.capability:__expect_send(host:generate_test_message("button2", capabilities.button.button.held({ state_change = true })))

    test.wait_for_events()
end)

test.register_coroutine_test("Test: Device Type Handler - Handles Button (Type 15) and OnOff (Type 256) Device Types with Child Creation", function()
    test.socket.matter:__set_channel_ordering("relaxed")

    local host = create_host_device("4-button", subhub)
    add_host_device(host, subhub)
    configure_subhub(subhub)
    configure_host(host, "4-button")
    subscribe_switch_events(host)
    four_button_2g_button_init(host)
    test.wait_for_events()

    -- Receive PartsList with endpoints 8 (button) and 6 (OnOff)
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 0, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(6),
        }))
    })

    -- Expect DeviceTypeList reads for both endpoints
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 8)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 6)
    })

    test.wait_for_events()

    -- Receive DeviceTypeList report with device type 15 (button) for endpoint 8
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 8, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.wait_for_events()

    -- Receive DeviceTypeList report with device type 256 (OnOff) for endpoint 6
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 6, data_types.Array {
            {
                device_type = data_types.Uint32(256),
                revision = data_types.Uint16(1)
            }
        })
    })
    subhub:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button Subhub 1",
        profile = "light-binary",
        parent_device_id = subhub.id,
        parent_assigned_child_key = "6"
    })

    test.wait_for_events()

    assert(subhub:get_field("__multi_button_8") == true, "Expected __multi_button_8 to be set to true")

    local button_eps = subhub:get_field("__button_eps")
    assert(button_eps ~= nil, "Expected __button_eps field to be set")
    assert(type(button_eps) == "table", "Expected __button_eps to be a table")
    assert(button_eps[1] == 8, "Expected __button_eps to contain endpoint 8")
end)

test.register_coroutine_test("Test: 2G Relay - Profile Changes Between light-binary and 2-button Based On Endpoint Availability", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")

    local relay = create_hager_2g_relay("matter-bridge", subhub)
    add_host_device(relay, subhub)
    configure_subhub(subhub)
    configure_host(relay, "light-binary")
    test.wait_for_events()

    -- Scenario 1: EP3 + EP4 present → light-binary profile
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 0, data_types.Array({
            data_types.Uint16(3),
            data_types.Uint16(4),
        }))
    })

    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 3)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 4)
    })

    -- Both endpoints are device type 256 (OnOff)
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 3, data_types.Array {
            {
                device_type = data_types.Uint32(256),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 4, data_types.Array {
            {
                device_type = data_types.Uint32(256),
                revision = data_types.Uint16(1)
            }
        })
    })
    relay:expect_metadata_update({ profile = "light-binary" })
    relay:expect_metadata_update({ profile = "light-binary" })
    subhub:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button Subhub 1",
        profile = "light-binary",
        parent_device_id = subhub.id,
        parent_assigned_child_key = "4"
    })

    -- Scenario 2: EP4 removed → profile changes to 2-button, child created for EP3
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 0, data_types.Array({
            data_types.Uint16(3),
        }))
    })

    relay:expect_metadata_update({ profile = "2-button" })

    --
    subhub:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button Subhub 2",
        profile = "light-binary",
        parent_device_id = subhub.id,
        parent_assigned_child_key = "3"
    })

    --
    local child_3 = test.mock_device.build_test_child_device({
        profile = t_utils.get_profile_definition("light-binary.yml"),
        device_network_id = string.format("%s:3", subhub.id),
        parent_device_id = subhub.id,
        parent_assigned_child_key = "3"
    })
    test.mock_device.add_test_device(child_3)

    test.wait_for_events()

    -- Scenario 3: EP4 reappears → profile changes back to light-binary
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 0, data_types.Array({
            data_types.Uint16(3),
            data_types.Uint16(4),
        }))
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 4)
    })
    relay:expect_metadata_update({ profile = "light-binary" })

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 4, data_types.Array {
            {
                device_type = data_types.Uint32(256),
                revision = data_types.Uint16(1)
            }
        })
    })

    subhub:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button Subhub 3",
        profile = "light-binary",
        parent_device_id = subhub.id,
        parent_assigned_child_key = "4"
    })
    test.wait_for_events()
    -- Scenario 4: EP3 removed → profile changes to 2-button, child created for EP4
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 2, data_types.Array({
            data_types.Uint16(4),
            data_types.Uint16(12),
            data_types.Uint16(13),
        }))
    })
    test.mock_time.advance_time(5)

    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 12)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 13)
    })
    test.wait_for_events()

    ---- Scenario 5: EP4 removed without EP3, no button endpoints → 4-button profile
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 0, data_types.Array({
        }))
    })

    relay:expect_metadata_update({ profile = "4-button" })

    ---- Scenario 6: Only EP4 present → 2-button profile, child created
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 0, data_types.Array({
            data_types.Uint16(4),
        }))
    })
    relay:expect_metadata_update({ profile = "2-button" })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 4)
    })

    test.wait_for_events()

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 4, data_types.Array {
            {
                device_type = data_types.Uint32(256),
                revision = data_types.Uint16(1)
            }
        })
    })

    subhub:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button Subhub 4",
        profile = "light-binary",
        parent_device_id = subhub.id,
        parent_assigned_child_key = "4"
    })
end)


--Test 5.1: Dimmer child device creation and profile behavior
test.register_coroutine_test("Test: Dimmer Device - Child Creation for Dimmable Endpoint with Button Support", function()
    test.socket.matter:__set_channel_ordering("relaxed")

    local dimmer = create_hager_dimmer_device_2g("matter-bridge", subhub)
    add_host_device(dimmer, subhub)
    configure_subhub(subhub)
    test.socket.matter:__expect_send({
        dimmer.id,
        clusters.LevelControl.attributes.Options:write(dimmer, 3, 1)
    })
    configure_host(dimmer, "2-button")
    test.wait_for_events()

    -- Scenario 1: 2 button endpoints (8, 9) detected → 2-button profile
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 2, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
        }))
    })

    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 8)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 9)
    })

    test.wait_for_events()

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 8, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 9, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })

    dimmer:expect_metadata_update({ profile = "2-button" })

    test.wait_for_events()

    -- Scenario 2: Dimmable endpoint 3 (device type 257/260) appears → child device created with light-level profile
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 2, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
            data_types.Uint16(3),
        }))
    })

    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 3)
    })

    test.wait_for_events()

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 3, data_types.Array {
            {
                device_type = data_types.Uint32(257),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 3, clusters.OnOff.ID, clusters.OnOff.attributes.OnOff.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 3, clusters.LevelControl.ID, clusters.LevelControl.attributes.CurrentLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 3, clusters.LevelControl.ID, clusters.LevelControl.attributes.MaxLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 3, clusters.LevelControl.ID, clusters.LevelControl.attributes.MinLevel.ID, nil)
    })

    subhub:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button Subhub 1",
        profile = "light-level",
        parent_device_id = subhub.id,
        parent_assigned_child_key = "3"
    })

    test.wait_for_events()

    -- Create mock child device for EP3
    local child_dimmer = test.mock_device.build_test_child_device({
        profile = t_utils.get_profile_definition("light-level.yml"),
        device_network_id = string.format("%s:3", subhub.id),
        parent_device_id = subhub.id,
        parent_assigned_child_key = "3"
    })
    test.mock_device.add_test_device(child_dimmer)

    -- Test 1: Turn on the dimmer (OnOff command)
    test.socket.capability:__queue_receive({ child_dimmer.id, { capability = "switch", component = "main", command = "on", args = {} } })
    test.socket.matter:__expect_send({ subhub.id, clusters.OnOff.commands.On(subhub, 3) })

    -- Test 2: Turn off the dimmer (OnOff command)
    test.socket.capability:__queue_receive({ child_dimmer.id, { capability = "switch", component = "main", command = "off", args = {} } })
    test.socket.matter:__expect_send({ subhub.id, clusters.OnOff.commands.Off(subhub, 3) })

    -- Test 3: Set dimmer level to 50% (LevelControl command)
    test.socket.capability:__queue_receive({ child_dimmer.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 20 } } })
    test.socket.matter:__expect_send({ subhub.id, clusters.LevelControl.commands.MoveToLevelWithOnOff(subhub, 3, 50, nil, 0, 0) })

    -- OnOff attribute changes - device reports on state
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.OnOff.server.attributes.OnOff:build_test_report_data(subhub, 3, true)
    })
    test.socket.capability:__expect_send(child_dimmer:generate_test_message("main", capabilities.switch.switch.on()))

    -- OnOff attribute changes - device reports off state
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.OnOff.server.attributes.OnOff:build_test_report_data(subhub, 3, false)
    })
    test.socket.capability:__expect_send(child_dimmer:generate_test_message("main", capabilities.switch.switch.off()))

    -- LevelControl attribute changes - device reports value 8
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(subhub, 3, 20)
    })
    test.socket.capability:__expect_send(child_dimmer:generate_test_message("main", capabilities.switchLevel.level(8)))

    -- LevelControl attribute changes - device reports value 0
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(subhub, 3, 0)
    })
    test.socket.capability:__expect_send(child_dimmer:generate_test_message("main", capabilities.switchLevel.level(0)))

end)

test.register_coroutine_test("Test: 1G Dimmer - Initialization and Profile Update to light-level", function()
    test.socket.matter:__set_channel_ordering("relaxed")

    local dimmer_host = create_hager_dimmer_device_1g("matter-bridge", subhub_1g)
    add_host_device(dimmer_host, subhub_1g)
    configure_subhub(subhub_1g)
    test.socket.matter:__expect_send({
        dimmer_host.id,
        clusters.LevelControl.attributes.Options:write(dimmer_host, 4, 1)
    })
    configure_host(dimmer_host, "light-level")
    test.wait_for_events()

end)

test.register_coroutine_test("Test: 1G Dimmer - Host Commands and Level Control Capabilities", function()
    test.socket.matter:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(6, "oneshot")

    local dimmer_host = create_hager_dimmer_device_1g("light-level", subhub_1g)
    add_host_device(dimmer_host, subhub_1g)
    configure_subhub(subhub_1g)
    test.socket.matter:__expect_send({
        dimmer_host.id,
        clusters.LevelControl.attributes.Options:write(dimmer_host, 4, 1)
    })
    subscribe_dimmer_attr(dimmer_host)

    configure_host(dimmer_host, "light-level")
    test.wait_for_events()

    -- Send dimmable endpoint 4 detection (device type 257) to trigger profile change and subscriptions
    test.socket.matter:__queue_receive({
        subhub_1g.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub_1g, 2, data_types.Array({
            data_types.Uint16(4),
        }))
    })

    test.socket.matter:__expect_send({
        subhub_1g.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub_1g, 4)
    })

    test.wait_for_events()

    test.socket.matter:__queue_receive({
        subhub_1g.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub_1g, 4, data_types.Array {
            {
                device_type = data_types.Uint32(257),
                revision = data_types.Uint16(1)
            }
        })
    })

    --subscriptions from device_type_handler
    test.socket.matter:__expect_send({
        subhub_1g.id,
        cluster_base.subscribe(subhub_1g, 4, clusters.OnOff.ID, clusters.OnOff.attributes.OnOff.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub_1g.id,
        cluster_base.subscribe(subhub_1g, 4, clusters.LevelControl.ID, clusters.LevelControl.attributes.CurrentLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub_1g.id,
        cluster_base.subscribe(subhub_1g, 4, clusters.LevelControl.ID, clusters.LevelControl.attributes.MaxLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub_1g.id,
        cluster_base.subscribe(subhub_1g, 4, clusters.LevelControl.ID, clusters.LevelControl.attributes.MinLevel.ID, nil)
    })

    -- Trigger 6-second delay in device_init to change FIELD_MAIN_ONOFF_EP from 3 to 4
    test.wait_for_events()
    test.mock_time.advance_time(6)
    test.wait_for_events()

    assert(dimmer_host:get_field("FIELD_MAIN_ONOFF_EP") == 4, "Expected FIELD_MAIN_ONOFF_EP to be 4 after 6-second delay")

    -- Test 1: Turn on the dimmer (OnOff command on HOST device)
    test.socket.capability:__queue_receive({ dimmer_host.id, { capability = "switch", component = "main", command = "on", args = {} } })
    test.socket.matter:__expect_send({ subhub_1g.id, clusters.OnOff.commands.On(subhub_1g, 4) })

    -- Verify on state via attribute report
    test.socket.matter:__queue_receive({
        subhub_1g.id,
        clusters.OnOff.server.attributes.OnOff:build_test_report_data(subhub_1g, 4, true)
    })
    test.socket.capability:__expect_send(dimmer_host:generate_test_message("main", capabilities.switch.switch.on()))

    -- Test 2: Turn off the dimmer (OnOff command on HOST device)
    test.socket.capability:__queue_receive({ dimmer_host.id, { capability = "switch", component = "main", command = "off", args = {} } })
    test.socket.matter:__expect_send({ subhub_1g.id, clusters.OnOff.commands.Off(subhub_1g, 4) })

    ---- Verify off state via attribute report
    test.socket.matter:__queue_receive({
        subhub_1g.id,
        clusters.OnOff.server.attributes.OnOff:build_test_report_data(subhub_1g, 4, false)
    })
    test.socket.capability:__expect_send(dimmer_host:generate_test_message("main", capabilities.switch.switch.off()))

    -- Test 3: Set dimmer level to 50% (LevelControl command on HOST device)
    test.socket.capability:__queue_receive({ dimmer_host.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 50 } } })
    test.socket.matter:__expect_send({ subhub_1g.id, clusters.LevelControl.commands.MoveToLevelWithOnOff(subhub_1g, 4, 127, nil, 0, 0) })

    test.wait_for_events()
    -- Verify level via attribute report
    test.socket.matter:__queue_receive({
        subhub_1g.id,
        clusters.LevelControl.server.attributes.CurrentLevel:build_test_report_data(subhub_1g, 4, 127)
    })
    test.socket.capability:__expect_send(dimmer_host:generate_test_message("main", capabilities.switchLevel.level(50)))

    -- Test 4: Set dimmer level to 100% (LevelControl command on HOST device)
    test.socket.capability:__queue_receive({ dimmer_host.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 100 } } })
    test.socket.matter:__expect_send({ subhub_1g.id, clusters.LevelControl.commands.MoveToLevelWithOnOff(subhub_1g, 4, 254, nil, 0, 0) })

    -- Verify level via attribute report
    test.socket.matter:__queue_receive({
        subhub_1g.id,
        clusters.LevelControl.server.attributes.CurrentLevel:build_test_report_data(subhub_1g, 4, 254)
    })
    test.socket.capability:__expect_send(dimmer_host:generate_test_message("main", capabilities.switchLevel.level(100)))

    test.wait_for_events()
end)

test.register_coroutine_test("Test: PIR Device - Initialization with Motion and Illuminance Capabilities", function()
    test.socket.matter:__set_channel_ordering("relaxed")

    local pir_device = create_hager_pir_device("matter-bridge", subhub_pir)

    add_host_device(pir_device, subhub_pir)
    pir_device:expect_metadata_update({ profile = "motion-illuminance" })
    configure_subhub(subhub_pir)

    test.socket.matter:__expect_send({
        pir_device.id,
        clusters.LevelControl.attributes.Options:write(pir_device, 3, 1)
    })
    configure_host(pir_device, nil)

end)

test.register_coroutine_test("Test: PIR Device - Complete Functionality with Motion, Illuminance, and Dimmer Support", function()
    test.socket.matter:__set_channel_ordering("relaxed")

    local pir_device = create_hager_pir_device("motion-illuminance", subhub_pir)

    add_host_device(pir_device, subhub_pir)
    pir_device:expect_metadata_update({ profile = "motion-illuminance" })
    configure_subhub(subhub_pir)

    test.socket.matter:__expect_send({
        pir_device.id,
        clusters.LevelControl.attributes.Options:write(pir_device, 3, 1)
    })
    configure_host(pir_device, nil)

    local OCC_ILUM_SUBSCRIBE_LIST = {
        cluster_base.subscribe(pir_device, nil, clusters.OccupancySensing.ID, clusters.OccupancySensing.attributes.Occupancy.ID, nil),
        cluster_base.subscribe(pir_device, nil, clusters.IlluminanceMeasurement.ID, clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID, nil)
    }
    local subscribe_request = OCC_ILUM_SUBSCRIBE_LIST[1]
    for i, clus in ipairs(OCC_ILUM_SUBSCRIBE_LIST) do
        if i > 1 then
            subscribe_request:merge(clus)
        end
    end
    test.socket.matter:__expect_send({
        pir_device.id,
        subscribe_request
    })
    test.wait_for_events()

    -- Test 1: Dimmer endpoint (3) detected with OnOff and LevelControl
    test.socket.matter:__queue_receive({
        subhub_pir.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub_pir, 0, data_types.Array({
            data_types.Uint16(3),
            data_types.Uint16(4),
            data_types.Uint16(5),
        }))
    })
    test.socket.matter:__expect_send({
        subhub_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub_pir, 3)
    })
    test.socket.matter:__expect_send({
        subhub_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub_pir, 4)
    })
    test.socket.matter:__expect_send({
        subhub_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub_pir, 5)
    })

    test.socket.matter:__queue_receive({
        subhub_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub_pir, 4, data_types.Array {
            {
                device_type = data_types.Uint32(263),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__queue_receive({
        subhub_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub_pir, 5, data_types.Array {
            {
                device_type = data_types.Uint32(262),
                revision = data_types.Uint16(1)
            }
        })
    })
    test.socket.matter:__queue_receive({
        subhub_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub_pir, 3, data_types.Array {
            {
                device_type = data_types.Uint32(0x0101),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__expect_send({
        subhub_pir.id,
        cluster_base.subscribe(subhub_pir, 3, clusters.OnOff.ID, clusters.OnOff.attributes.OnOff.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub_pir.id,
        cluster_base.subscribe(subhub_pir, 3, clusters.LevelControl.ID, clusters.LevelControl.attributes.CurrentLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub_pir.id,
        cluster_base.subscribe(subhub_pir, 3, clusters.LevelControl.ID, clusters.LevelControl.attributes.MaxLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub_pir.id,
        cluster_base.subscribe(subhub_pir, 3, clusters.LevelControl.ID, clusters.LevelControl.attributes.MinLevel.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub_pir.id,
        cluster_base.subscribe(subhub_pir, 4, clusters.OccupancySensing.ID, clusters.OccupancySensing.attributes.Occupancy.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub_pir.id,
        cluster_base.subscribe(subhub_pir, 5, clusters.IlluminanceMeasurement.ID, clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID, nil)
    })
    subhub_pir:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button Subhub 1",
        profile = "light-level",
        parent_device_id = subhub_pir.id,
        parent_assigned_child_key = "3"
    })

    test.wait_for_events()

    -- Create mock child device for EP3
    local child_dimmer = test.mock_device.build_test_child_device({
        profile = t_utils.get_profile_definition("light-level.yml"),
        device_network_id = string.format("%s:3", subhub_pir.id),
        parent_device_id = subhub_pir.id,
        parent_assigned_child_key = "3"
    })
    test.mock_device.add_test_device(child_dimmer)

    test.wait_for_events()

    test.socket.matter:__queue_receive({
        subhub_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub_pir, 4, data_types.Array {
            {
                device_type = data_types.Uint32(263),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__queue_receive({
        subhub_pir.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub_pir, 5, data_types.Array {
            {
                device_type = data_types.Uint32(262),
                revision = data_types.Uint16(1)
            }
        })
    })


    -- Test 5: Verify OccupancySensing subscription
    test.socket.matter:__expect_send({
        subhub_pir.id,
        cluster_base.subscribe(subhub_pir, 4, clusters.OccupancySensing.ID, clusters.OccupancySensing.attributes.Occupancy.ID, nil)
    })

    -- Test 6: Verify IlluminanceMeasurement subscription
    test.socket.matter:__expect_send({
        subhub_pir.id,
        cluster_base.subscribe(subhub_pir, 5, clusters.IlluminanceMeasurement.ID, clusters.IlluminanceMeasurement.attributes.MeasuredValue.ID, nil)
    })

    test.wait_for_events()

    ---- Test 7: Verify motion detected event
    test.socket.matter:__queue_receive({
        subhub_pir.id,
        clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(subhub_pir, 4, 1)
    })
    test.socket.capability:__expect_send(pir_device:generate_test_message("main", capabilities.motionSensor.motion.active()))
    test.wait_for_events()

    -- Test 8: Verify illuminance measurement event
    test.socket.matter:__queue_receive({
        subhub_pir.id,
        clusters.IlluminanceMeasurement.attributes.MeasuredValue:build_test_report_data(subhub_pir, 5, 21370)
    })
    test.socket.capability:__expect_send(pir_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance(137)))

    test.wait_for_events()

    -- Test 9: Send on command to OnOff endpoint (dimmer)
    test.socket.capability:__queue_receive({ child_dimmer.id, { capability = "switch", component = "main", command = "on", args = {} } })
    test.socket.matter:__expect_send({
        subhub_pir.id,
        clusters.OnOff.commands.On(subhub_pir, 3)
    })

    -- Test 10: Verify on state via attribute report
    test.socket.matter:__queue_receive({
        subhub_pir.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(subhub_pir, 3, true)
    })
    test.socket.capability:__expect_send(child_dimmer:generate_test_message("main", capabilities.switch.switch.on()))

    -- Test 11: Set dimmer level to 50%
    test.socket.capability:__queue_receive({ child_dimmer.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 50 } } })
    test.socket.matter:__expect_send({
        subhub_pir.id,
        clusters.LevelControl.commands.MoveToLevelWithOnOff(subhub_pir, 3, 127, nil, 0, 0)
    })

    -- Test 12: Verify level via attribute report
    test.socket.matter:__queue_receive({
        subhub_pir.id,
        clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(subhub_pir, 3, 127)
    })
    test.socket.capability:__expect_send(child_dimmer:generate_test_message("main", capabilities.switchLevel.level(50)))

end)

local function create_host_device_with_window(profile_name, parent_subhub)
    return test.mock_device.build_test_matter_device({
        label = "Hager G2 Host with Window Covering",
        profile = t_utils.get_profile_definition(profile_name .. ".yml"),
        manufacturer_info = {
            vendor_id = 0x1285,
            product_id = 0x0006,
        },
        parent_device_id = parent_subhub.id,
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

-- Button configuration helper for 2-button profile
local function button_2g_configuration(host)
    test.socket.capability:__expect_send(host:generate_test_message("main", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("main", capabilities.button.button.pushed({ state_change = false })))

    test.socket.capability:__expect_send(host:generate_test_message("button2", capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(host:generate_test_message("button2", capabilities.button.button.pushed({ state_change = false })))
end

test.register_coroutine_test("Test: Host with Window Covering - 2-Button Profile with Window Covering Child Device", function()
    test.socket.matter:__set_channel_ordering("relaxed")

    local host = create_host_device_with_window("2-button", subhub)
    add_host_device(host, subhub)
    subscribe_switch_events(host)

    host:expect_metadata_update({ profile = "2-button" })
    configure_subhub(subhub)

    configure_host(host, nil)
    test.wait_for_events()

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 0, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
            data_types.Uint16(12),
        }))
    })
    --
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 8)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 9)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 12)
    })
    test.wait_for_events()

    -- DeviceTypeList reports for button endpoints (type 15 = Generic Switch)
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 8, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 9, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })

    -- DeviceTypeList report for window covering endpoint (type 514 = Window Covering Device)
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 12, data_types.Array {
            {
                device_type = data_types.Uint32(514),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 12, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.OperationalStatus.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 12, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID, nil)
    })

    subhub:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button Subhub 1",
        profile = "window-covering",
        parent_device_id = subhub.id,
        parent_assigned_child_key = "12"
    })

    local child_wc = test.mock_device.build_test_child_device({
        profile = t_utils.get_profile_definition("window-covering.yml"),
        device_network_id = string.format("%s:12", subhub.id),
        parent_device_id = subhub.id,
        parent_assigned_child_key = "12"
    })
    test.mock_device.add_test_device(child_wc)
    test.wait_for_events()

    ---- Test 1: Open command
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShade", component = "main", command = "open", args = {} } })
    test.socket.matter:__expect_send({ subhub.id, clusters.WindowCovering.commands.UpOrOpen(subhub, 12) })
    test.wait_for_events()

    -- Verify open state via attribute report
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.WindowCovering.attributes.OperationalStatus:build_test_report_data(subhub, 12, 0x01)
    })
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShade.windowShade.opening()))

    test.wait_for_events()

    ---- Test 2: Close command
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShade", component = "main", command = "close", args = {} } })
    test.socket.matter:__expect_send({ subhub.id, clusters.WindowCovering.commands.DownOrClose(subhub, 12) })

    -- Verify close state via attribute report
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.WindowCovering.attributes.OperationalStatus:build_test_report_data(subhub, 12, 0x02)
    })
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShade.windowShade.closing()))

    -- Test 3: Pause command
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShade", component = "main", command = "pause", args = {} } })
    test.socket.matter:__expect_send({ subhub.id, clusters.WindowCovering.commands.StopMotion(subhub, 12) })
    test.wait_for_events()

    -- Test 4: Set shade level to 50%
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 50 } } })
    test.socket.matter:__expect_send({ subhub.id, clusters.WindowCovering.commands.GoToLiftPercentage(subhub, 12, 5000, nil, 0, 0) })
    test.wait_for_events()

    -- Verify shade level via attribute report
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(subhub, 12, 5000)
    })
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(50)))
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShade.windowShade.partially_open()))


    -- Test 5: Set shade level to 100%
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 100 } } })
    test.socket.matter:__expect_send({ subhub.id, clusters.WindowCovering.commands.GoToLiftPercentage(subhub, 12, 0, nil, 0, 0) })
    test.wait_for_events()

    -- Verify shade level via attribute report
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(subhub, 12, 0)
    })
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100)))
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShade.windowShade.open()))

    -- Test 6: Set shade level to 0%
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 0 } } })
    test.socket.matter:__expect_send({ subhub.id, clusters.WindowCovering.commands.GoToLiftPercentage(subhub, 12, 10000, nil, 0, 0) })

    -- Verify shade level via attribute report
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(subhub, 12, 10000)
    })
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0)))
    test.socket.capability:__expect_send(child_wc:generate_test_message("main", capabilities.windowShade.windowShade.closed()))

end)

test.register_coroutine_test("Test: Window Covering - Preference Changes for Reverse Polarity and Preset Position", function()
    test.socket.matter:__set_channel_ordering("relaxed")

    local host = create_host_device_with_window("2-button", subhub)
    add_host_device(host, subhub)
    subscribe_switch_events(host)

    host:expect_metadata_update({ profile = "2-button" })
    configure_subhub(subhub)

    configure_host(host, nil)
    test.wait_for_events()

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 0, data_types.Array({
            data_types.Uint16(8),
            data_types.Uint16(9),
            data_types.Uint16(12),
        }))
    })
    --
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 8)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 9)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 12)
    })
    test.wait_for_events()

    -- DeviceTypeList reports for button endpoints (type 15 = Generic Switch)
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 8, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 9, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })

    -- DeviceTypeList report for window covering endpoint (type 514 = Window Covering Device)
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 12, data_types.Array {
            {
                device_type = data_types.Uint32(514),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 12, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.OperationalStatus.ID, nil)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 12, clusters.WindowCovering.ID, clusters.WindowCovering.attributes.CurrentPositionLiftPercent100ths.ID, nil)
    })

    subhub:expect_device_create({
        type = "EDGE_CHILD",
        label = "Hager G2 4x Button Subhub 1",
        profile = "window-covering",
        parent_device_id = subhub.id,
        parent_assigned_child_key = "12"
    })

    local child_wc = test.mock_device.build_test_child_device({
        profile = t_utils.get_profile_definition("window-covering.yml"),
        device_network_id = string.format("%s:12", subhub.id),
        parent_device_id = subhub.id,
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
    test.socket.matter:__expect_send({ subhub.id, clusters.WindowCovering.commands.DownOrClose(subhub, 12) })

    -- Send close command - with reverse_polarity true, this should send UpOrOpen
    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShade", component = "main", command = "close", args = {} } })
    test.socket.matter:__expect_send({ subhub.id, clusters.WindowCovering.commands.UpOrOpen(subhub, 12) })

    -- Position preset testing
    test.socket.device_lifecycle():__queue_receive(child_wc:generate_info_changed({ preferences = { presetPosition = "50" } }))
    test.socket.device_lifecycle():__queue_receive(child_wc:generate_info_changed({ preferences = { presetPosition = "20" } }))

    test.wait_for_events()

    local PRESET_LEVEL_KEY = child_wc:get_field("__preset_level_key")
    assert(PRESET_LEVEL_KEY == "20", " __preset_level_key is set to 20")

    test.socket.capability:__queue_receive({ child_wc.id, { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} } })
    test.socket.matter:__expect_send(
            { subhub.id, clusters.WindowCovering.server.commands.GoToLiftPercentage(subhub, 12, 8000) }
    )
end)

test.register_coroutine_test("Test: info_changed - Profile Change from 4-button to 2-button Triggers Button Reconfiguration", function()
    test.socket.matter:__set_channel_ordering("relaxed")

    local host = create_host_device("4-button", subhub)
    add_host_device(host, subhub)
    configure_subhub(subhub)
    configure_host(host, "4-button")
    subscribe_switch_events(host)
    button_supported_values(host)
    test.wait_for_events()

    local device_info_copy = st_utils.deep_copy(host.raw_st_data)
    device_info_copy.profile.id = "4-button"
    local device_info_json = dkjson.encode(device_info_copy)
    test.socket.device_lifecycle:__queue_receive({ host.id, "infoChanged", device_info_json })

    -- Scenario 1: EP3 (onoff) + EP8, EP9 (buttons) present → 2-button profile
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.PartsList:build_test_report_data(subhub, 0, data_types.Array({
            data_types.Uint16(3),
            data_types.Uint16(8),
            data_types.Uint16(9),
        }))
    })

    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 3)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 8)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:read(subhub, 9)
    })
    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 3, data_types.Array {
            {
                device_type = data_types.Uint32(256),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 8, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })

    test.socket.matter:__queue_receive({
        subhub.id,
        clusters.Descriptor.attributes.DeviceTypeList:build_test_report_data(subhub, 9, data_types.Array {
            {
                device_type = data_types.Uint32(15),
                revision = data_types.Uint16(1)
            }
        })
    })
    host:expect_metadata_update({ profile = "2-button" })
    subhub:set_field(BUTTON_EPS, { 8, 9 }, { persist = true })

    test.wait_for_events()
    device_info_copy.profile.id = "2-button"
    device_info_json = dkjson.encode(device_info_copy)
    test.socket.device_lifecycle:__queue_receive({ host.id, "infoChanged", device_info_json })

    test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
    test.mock_time.advance_time(5)
    test.socket.capability:__expect_send(host:generate_test_message("main", capabilities.button.supportedButtonValues({ "pushed", "double", "held" })))
    test.socket.capability:__expect_send(host:generate_test_message("button2", capabilities.button.supportedButtonValues({ "pushed", "double", "held" })))

    -- Expect Switch event subscriptions for button endpoints (8, 9)
    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 8, clusters.Switch.ID, nil, clusters.Switch.events.MultiPressComplete.ID)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 8, clusters.Switch.ID, nil, clusters.Switch.events.ShortRelease.ID)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 8, clusters.Switch.ID, nil, clusters.Switch.events.LongPress.ID)
    })

    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 9, clusters.Switch.ID, nil, clusters.Switch.events.MultiPressComplete.ID)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 9, clusters.Switch.ID, nil, clusters.Switch.events.ShortRelease.ID)
    })
    test.socket.matter:__expect_send({
        subhub.id,
        cluster_base.subscribe(subhub, 9, clusters.Switch.ID, nil, clusters.Switch.events.LongPress.ID)
    })

end)

test.run_registered_tests()
