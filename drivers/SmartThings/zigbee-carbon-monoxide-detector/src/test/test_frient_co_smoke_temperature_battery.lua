-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local IASZone = clusters.IASZone
local IASWD = clusters.IASWD
local CarbonMonoxideCluster = clusters.CarbonMonoxide
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local capabilities = require "st.capabilities"
local alarm = capabilities.alarm
local smokeDetector = capabilities.smokeDetector
local carbonMonoxideDetector = capabilities.carbonMonoxideDetector
local carbonMonoxideMeasurement = capabilities.carbonMonoxideMeasurement
local tamperAlert = capabilities.tamperAlert
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local data_types = require "st.zigbee.data_types"
local SinglePrecisionFloat = require "st.zigbee.data_types.SinglePrecisionFloat"
local device_management = require "st.zigbee.device_management"
local default_response = require "st.zigbee.zcl.global_commands.default_response"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local zcl_messages = require "st.zigbee.zcl"
local Status = require "st.zigbee.generated.types.ZclStatus"

local SMOKE_ENDPOINT = 0x23
local CO_ENDPOINT = 0x2E
local TEMPERATURE_ENDPOINT = 0x26
local ALARM_COMMAND = "alarmCommand"

local mock_device = test.mock_device.build_test_zigbee_device(
	{
		profile = t_utils.get_profile_definition("frient-smoke-co-temperature-battery.yml"),
		fingerprinted_endpoint_id = SMOKE_ENDPOINT,
		zigbee_endpoints = {
			[SMOKE_ENDPOINT] = {
				id = SMOKE_ENDPOINT,
				manufacturer = "frient A/S",
				model = "SCAZB-143",
				server_clusters = { PowerConfiguration.ID, IASZone.ID, IASWD.ID }
			},
			[CO_ENDPOINT] = {
				id = CO_ENDPOINT,
				server_clusters = { IASZone.ID, CarbonMonoxideCluster.ID }
			},
			[TEMPERATURE_ENDPOINT] = {
				id = TEMPERATURE_ENDPOINT,
				server_clusters = { TemperatureMeasurement.ID }
			}
		}
	}
)

local function build_default_response_msg(cluster, command, status, endpoint)
	local addr_header = messages.AddressHeader(
		mock_device:get_short_address(),
		endpoint or SMOKE_ENDPOINT,
		zb_const.HUB.ADDR,
		zb_const.HUB.ENDPOINT,
		zb_const.HA_PROFILE_ID,
		cluster
	)
	local default_response_body = default_response.DefaultResponse(command, status)
	local zcl_header = zcl_messages.ZclHeader({
		cmd = data_types.ZCLCommandId(default_response_body.ID)
	})
	local message_body = zcl_messages.ZclMessageBody({
		zcl_header = zcl_header,
		zcl_body = default_response_body
	})
	return messages.ZigbeeMessageRx({
		address_header = addr_header,
		body = message_body
	})
end

local function expect_bind_and_config(config, endpoint)
	test.socket.zigbee:__expect_send({
		mock_device.id,
		device_management.build_bind_request(mock_device, config.cluster, zigbee_test_utils.mock_hub_eui, endpoint):to_endpoint(endpoint)
	})
	test.socket.zigbee:__expect_send({
		mock_device.id,
		device_management.attr_config(mock_device, config):to_endpoint(endpoint)
	})
end

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
	test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
	"added lifecycle should set default states",
	function()
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", alarm.alarm.off())
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", smokeDetector.smoke.clear())
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", carbonMonoxideDetector.carbonMonoxide.clear())
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", tamperAlert.tamper.clear())
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", carbonMonoxideMeasurement.carbonMonoxideLevel({ value = 0, unit = "ppm" }))
		)

		test.wait_for_events()
	end
)

test.register_coroutine_test(
	"init and doConfigure should bind, configure, and refresh",
	function()
		local battery_config = {
			cluster = PowerConfiguration.ID,
			attribute = PowerConfiguration.attributes.BatteryVoltage.ID,
			minimum_interval = 30,
			maximum_interval = 21600,
			data_type = data_types.Uint8,
			reportable_change = 1
		}
		local ias_zone_config = {
			cluster = IASZone.ID,
			attribute = IASZone.attributes.ZoneStatus.ID,
			minimum_interval = 0,
			maximum_interval = 300,
			data_type = IASZone.attributes.ZoneStatus.base_type,
			reportable_change = 1
		}
		local co_config = {
			cluster = CarbonMonoxideCluster.ID,
			attribute = CarbonMonoxideCluster.attributes.MeasuredValue.ID,
			minimum_interval = 30,
			maximum_interval = 600,
			data_type = data_types.SinglePrecisionFloat,
			reportable_change = SinglePrecisionFloat(0, -20, 0.048576)
		}
		local temp_config = {
			cluster = TemperatureMeasurement.ID,
			attribute = TemperatureMeasurement.attributes.MeasuredValue.ID,
			minimum_interval = 30,
			maximum_interval = 600,
			data_type = data_types.Int16,
			reportable_change = data_types.Int16(100)
		}

		test.socket.zigbee:__set_channel_ordering("relaxed")
		test.socket.capability:__set_channel_ordering("relaxed")

		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
		test.wait_for_events()

		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

		test.socket.zigbee:__expect_send({
			mock_device.id,
			device_management.attr_refresh(mock_device, PowerConfiguration.ID, PowerConfiguration.attributes.BatteryVoltage.ID):to_endpoint(SMOKE_ENDPOINT)
		})
		test.socket.zigbee:__expect_send({
			mock_device.id,
			device_management.attr_refresh(mock_device, IASZone.ID, IASZone.attributes.ZoneStatus.ID):to_endpoint(SMOKE_ENDPOINT)
		})
		test.socket.zigbee:__expect_send({
			mock_device.id,
			device_management.attr_refresh(mock_device, IASZone.ID, IASZone.attributes.ZoneStatus.ID):to_endpoint(CO_ENDPOINT)
		})
		test.socket.zigbee:__expect_send({
			mock_device.id,
			device_management.attr_refresh(mock_device, CarbonMonoxideCluster.ID, CarbonMonoxideCluster.attributes.MeasuredValue.ID):to_endpoint(CO_ENDPOINT)
		})
		test.socket.zigbee:__expect_send({
			mock_device.id,
			device_management.attr_refresh(mock_device, TemperatureMeasurement.ID, TemperatureMeasurement.attributes.MeasuredValue.ID):to_endpoint(TEMPERATURE_ENDPOINT)
		})

		expect_bind_and_config(battery_config, SMOKE_ENDPOINT)
		expect_bind_and_config(ias_zone_config, SMOKE_ENDPOINT)
		expect_bind_and_config(ias_zone_config, CO_ENDPOINT)
		expect_bind_and_config(co_config, CO_ENDPOINT)
		expect_bind_and_config(temp_config, TEMPERATURE_ENDPOINT)

		test.socket.zigbee:__expect_send({
			mock_device.id,
			IASZone.attributes.IASCIEAddress:write(mock_device, zigbee_test_utils.mock_hub_eui)
		})
		test.socket.zigbee:__expect_send({
			mock_device.id,
			IASZone.server.commands.ZoneEnrollResponse(mock_device, 0x00, 0x00)
		})

		mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })

		test.wait_for_events()
	end
)

test.register_coroutine_test(
	"IAS Zone smoke detected should be handled",
	function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0001):from_endpoint(SMOKE_ENDPOINT)
		})
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", smokeDetector.smoke.detected())
		)
    test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", tamperAlert.tamper.clear())
		)
	end
)

test.register_coroutine_test(
	"IAS Zone smoke tested should be handled",
	function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0100):from_endpoint(SMOKE_ENDPOINT)
		})
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", smokeDetector.smoke.tested())
		)
    test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", tamperAlert.tamper.clear())
		)
	end
)

test.register_coroutine_test(
	"IAS Zone smoke clear should be delayed",
	function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
		test.timer.__create_and_queue_test_time_advance_timer(6, "oneshot")
		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0000):from_endpoint(SMOKE_ENDPOINT)
		})

		test.mock_time.advance_time(6)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", smokeDetector.smoke.clear())
		)
    test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", tamperAlert.tamper.clear())
		)
		test.wait_for_events()
	end
)

test.register_coroutine_test(
	"IAS Zone carbon monoxide detected should be handled",
	function()
		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0001):from_endpoint(CO_ENDPOINT)
		})
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", carbonMonoxideDetector.carbonMonoxide.detected())
		)
    test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", tamperAlert.tamper.clear())
		)
	end
)

test.register_coroutine_test(
	"IAS Zone carbon monoxide tested should be handled",
	function()
		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0100):from_endpoint(CO_ENDPOINT)
		})
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", carbonMonoxideDetector.carbonMonoxide.tested())
		)
    test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", tamperAlert.tamper.clear())
		)
	end
)

test.register_coroutine_test(
	"IAS Zone carbon monoxide clear should be delayed",
	function()
		test.timer.__create_and_queue_test_time_advance_timer(6, "oneshot")
		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0000):from_endpoint(CO_ENDPOINT)
		})

		test.mock_time.advance_time(6)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", tamperAlert.tamper.clear())
    )
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", carbonMonoxideDetector.carbonMonoxide.clear())
		)
		test.wait_for_events()
	end
)

test.register_coroutine_test(
	"Tamper detected should be handled",
	function()
		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0004):from_endpoint(SMOKE_ENDPOINT)
		})
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", tamperAlert.tamper.detected())
		)
	end
)

test.register_coroutine_test(
	"Tamper clear should be handled",
	function()
		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0000):from_endpoint(SMOKE_ENDPOINT)
		})
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", tamperAlert.tamper.clear())
		)
	end
)

test.register_coroutine_test(
	"Carbon monoxide measurement should scale values <= 1",
	function()
		test.socket.zigbee:__queue_receive({
			mock_device.id,
			CarbonMonoxideCluster.attributes.MeasuredValue:build_test_attr_report(
				mock_device,
				SinglePrecisionFloat(0, -20, 0.048576)
			):from_endpoint(CO_ENDPOINT)
		})
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", carbonMonoxideMeasurement.carbonMonoxideLevel({ value = 0.99999999747524, unit = "ppm" }))
		)
	end
)

test.register_coroutine_test(
	"Carbon monoxide measurement should pass through values > 1",
	function()
		test.socket.zigbee:__queue_receive({
			mock_device.id,
			CarbonMonoxideCluster.attributes.MeasuredValue:build_test_attr_report(
				mock_device,
				SinglePrecisionFloat(0, -15, 0.572864)
			):from_endpoint(CO_ENDPOINT)
		})
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", carbonMonoxideMeasurement.carbonMonoxideLevel({ value = 47.999998059822, unit = "ppm" }))
		)
	end
)

test.register_coroutine_test(
	"infoChanged should update maxWarningDuration and temperatureSensitivity",
	function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
		local updates = {
			preferences = {
				maxWarningDuration = 120,
				temperatureSensitivity = 1.3
			}
		}

		test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))

		test.socket.zigbee:__expect_send({
			mock_device.id,
			IASWD.attributes.MaxDuration:write(mock_device, 120)
		})
		test.socket.zigbee:__expect_send({
			mock_device.id,
			TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
				mock_device,
				30,
				600,
				130
			):to_endpoint(TEMPERATURE_ENDPOINT)
		})
	end
)

test.register_coroutine_test(
	"Alarm siren command should send StartWarning and auto-off",
	function()
		mock_device.preferences.maxWarningDuration = 5
		test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")

		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = "alarm", component = "main", command = "siren", args = {} }
		})

		local expected_configuration = IASWD.types.SirenConfiguration(0x00)
		expected_configuration:set_warning_mode(0x01)
		expected_configuration:set_siren_level(0x01)

		test.socket.zigbee:__expect_send({
			mock_device.id,
			IASWD.server.commands.StartWarning(
				mock_device,
				expected_configuration,
				data_types.Uint16(5),
				data_types.Uint8(0x00),
				data_types.Enum8(0x00)
			)
		})

		test.wait_for_events()
		test.mock_time.advance_time(5)

		local expected_off_configuration = IASWD.types.SirenConfiguration(0x00)
		expected_off_configuration:set_warning_mode(0x00)
		expected_off_configuration:set_siren_level(0x00)

		test.socket.zigbee:__expect_send({
			mock_device.id,
			IASWD.server.commands.StartWarning(
				mock_device,
				expected_off_configuration,
				data_types.Uint16(5),
				data_types.Uint8(0x00),
				data_types.Enum8(0x00)
			)
		})
	end
)

test.register_coroutine_test(
	"Alarm off command should send StartWarning stop",
	function()
		mock_device.preferences.maxWarningDuration = 5

		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = "alarm", component = "main", command = "off", args = {} }
		})

		local expected_configuration = IASWD.types.SirenConfiguration(0x00)
		expected_configuration:set_warning_mode(0x00)
		expected_configuration:set_siren_level(0x00)

		test.socket.zigbee:__expect_send({
			mock_device.id,
			IASWD.server.commands.StartWarning(
				mock_device,
				expected_configuration,
				data_types.Uint16(5),
				data_types.Uint8(0x00),
				data_types.Enum8(0x00)
			)
		})
	end
)

test.register_coroutine_test(
	"Default response to StartWarning should emit alarm events",
	function()
		mock_device.preferences.maxWarningDuration = 2
		mock_device:set_field(ALARM_COMMAND, 1, { persist = true })

		test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
		test.socket.zigbee:__queue_receive({
			mock_device.id,
			build_default_response_msg(IASWD.ID, IASWD.server.commands.StartWarning.ID, Status.SUCCESS, SMOKE_ENDPOINT)
		})

		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", alarm.alarm.siren())
		)

		test.wait_for_events()
		test.mock_time.advance_time(2)

		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", alarm.alarm.off())
		)
		test.wait_for_events()
	end
)

test.run_registered_tests()

