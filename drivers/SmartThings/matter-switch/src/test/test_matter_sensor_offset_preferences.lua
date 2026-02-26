local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local dkjson = require "dkjson"
local clusters = require "st.matter.clusters"

local mock_device = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("3-button-battery-temperature-humidity.yml"),
    matter_version = {hardware = 1, software = 1},
    manufacturer_info = {
        vendor_id = 0x0000,
        product_id = 0x0000,
    },
    endpoints = {
        {
            endpoint_id = 1,
            clusters = {
                {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
            },
            device_types = {
                {device_type_id = 0x0302, device_type_revision = 1},
            }
        },
        {
            endpoint_id = 2,
            clusters = {
                {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "BOTH"},
            },
            device_types = {
                {device_type_id = 0x0307, device_type_revision = 1},
            }
        },
    }
})

local function test_init()
    test.disable_startup_messages()
    test.mock_device.add_test_device(mock_device)

    local cluster_subscribe_list = {
        clusters.Switch.events.InitialPress,
        clusters.Switch.events.LongPress,
        clusters.Switch.events.ShortRelease,
        clusters.Switch.events.MultiPressComplete,

        clusters.TemperatureMeasurement.attributes.MeasuredValue,
        clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
        clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,

        clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
        clusters.PowerSource.attributes.BatPercentRemaining
    }

    local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
    for i, cluster in ipairs(cluster_subscribe_list) do
        if i > 1 then
            subscribe_request:merge(cluster:subscribe(mock_device))
        end
    end

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.matter:__expect_send({mock_device.id, subscribe_request})

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
    test.socket.matter:__expect_send({mock_device.id, subscribe_request})

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.matter:__expect_send({mock_device.id, subscribe_request})

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })

    local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
    device_info_copy.profile.id = "3-button-battery-temperature-humidity"
    local device_info_json = dkjson.encode(device_info_copy)
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json})
    test.socket.matter:__expect_send({mock_device.id, subscribe_request})

end

test.register_coroutine_test("Read appropriate attribute values after tempOffset preference change", function()
    local report = clusters.TemperatureMeasurement.attributes.MeasuredValue:build_test_report_data(mock_device,1, 2000)
    mock_device.st_store.preferences = {tempOffset = "0"}

    test.socket.matter:__queue_receive({mock_device.id, report})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",capabilities.temperatureMeasurement.temperature({
        value = 20.0,
        unit = "C"
    })))
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({preferences = {tempOffset = "5"}}))
    test.socket.matter:__expect_send({mock_device.id, clusters.TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)})

    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, report})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",capabilities.temperatureMeasurement.temperature({
        value = 20.0,
        unit = "C"
    })))
end,
{
   min_api_version = 19
}
)

test.register_coroutine_test("Read appropriate attribute values after humidityOffset preference change", function()
    local report = clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:build_test_report_data(mock_device,2, 2000)
    mock_device.st_store.preferences = {humidityOffset = "0"}

    test.socket.matter:__queue_receive({mock_device.id, report})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",capabilities.relativeHumidityMeasurement.humidity({
        value = 20
    })))
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({preferences = {humidityOffset = "5"}}))
    test.socket.matter:__expect_send({mock_device.id, clusters.RelativeHumidityMeasurement.attributes.MeasuredValue:read(mock_device)})

    test.wait_for_events()

    test.socket.matter:__queue_receive({mock_device.id, report})
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",capabilities.relativeHumidityMeasurement.humidity({
        value = 20
    })))
end,
{
   min_api_version = 19
}
)

test.set_test_init_function(test_init)

test.run_registered_tests()
