-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local json = require "st.json"
local utils = require "st.utils"
local dkjson = require "dkjson"

local IASACE = clusters.IASACE
local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration

local ArmMode = IASACE.types.ArmMode
local ArmNotification = IASACE.types.ArmNotification
local PanelStatus = IASACE.types.IasacePanelStatus
local AudibleNotification = IASACE.types.IasaceAudibleNotification
local AlarmStatus = IASACE.types.IasaceAlarmStatus

local mock_device = test.mock_device.build_test_zigbee_device(
	{
		profile = t_utils.get_profile_definition("frient-keypad-security-system.yml"),
		fingerprinted_endpoint_id = 0x2C,
		zigbee_endpoints = {
			[0x2C] = {
				id = 0x2C,
				manufacturer = "frient A/S",
				model = "KEPZB-110",
				server_clusters = { 0x0001, 0x0500, 0x0501 }
			}
		}
	}
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
	test.mock_device.add_test_device(mock_device)
	test.socket.capability:__set_channel_ordering("relaxed")
	test.socket.capability:__expect_send(
		mock_device:generate_test_message(
			"main",
			capabilities.securitySystem.supportedSecuritySystemStatuses({ "armedAway", "armedStay", "disarmed" }, { visibility = { displayed = false } })
		)
	)
	test.socket.capability:__expect_send(
		mock_device:generate_test_message(
			"main",
			capabilities.securitySystem.supportedSecuritySystemCommands({ "armAway", "armStay", "disarm" }, { visibility = { displayed = false } })
		)
	)
	test.socket.capability:__expect_send(
		mock_device:generate_test_message(
			"main",
			capabilities.lockCodes.lockCodes(json.encode({}), { state_change = true }, { visibility = { displayed = true } })
		)
	)
	test.socket.capability:__expect_send(
		mock_device:generate_test_message(
			"main",
			capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })
		)
	)
	test.socket.capability:__expect_send(
		mock_device:generate_test_message(
			"main",
			capabilities.lockCodes.maxCodeLength(10, { visibility = { displayed = true } })
		)
	)
end

test.set_test_init_function(test_init)

local function info_changed_device_data(preference_updates)
	local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
	for key, value in pairs(preference_updates or {}) do
		device_info_copy.preferences[key] = value
	end
	return dkjson.encode(device_info_copy)
end

test.register_coroutine_test(
	"Added lifecycle emits supported statuses and default disarmed state",
	function()
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.securitySystem.supportedSecuritySystemStatuses({ "armedAway", "armedStay", "disarmed" }, { visibility = { displayed = false } })
			)
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.securitySystem.supportedSecuritySystemCommands({ "armAway", "armStay", "disarm" }, { visibility = { displayed = false } })
			)
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.securitySystem.securitySystemStatus.disarmed({ state_change = true }))
		)
	end
)

test.register_coroutine_test(
	"doConfigure binds clusters and configures battery reporting",
	function()
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })

		test.socket.zigbee:__set_channel_ordering("relaxed")
		test.socket.zigbee:__expect_send({
			mock_device.id,
			zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IASACE.ID)
		})
		test.socket.zigbee:__expect_send({
			mock_device.id,
			zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
		})
		test.socket.zigbee:__expect_send({
			mock_device.id,
			PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1)
		})

		mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
	end
)

test.register_coroutine_test(
	"Refresh command reads battery and sends panel status",
	function()
		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = capabilities.refresh.ID, component = "main", command = capabilities.refresh.commands.refresh.NAME, args = {} }
		})

		test.socket.zigbee:__set_channel_ordering("relaxed")
		test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:read(mock_device) })
		test.socket.zigbee:__expect_send(
			{
				mock_device.id,
				IASACE.client.commands.PanelStatusChanged(
					mock_device,
					PanelStatus.PANEL_DISARMED_READY_TO_ARM,
					5,
					AudibleNotification.DEFAULT_SOUND,
					AlarmStatus.NO_ALARM
				)
			}
		)
	end
)

test.register_message_test(
	"Battery voltage report is handled",
	{
		{
			channel = "zigbee",
			direction = "receive",
			message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 0x3C) }
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
		}
	}
)

test.register_message_test(
	"IAS Zone tamper attribute report emits tamper detected",
	{
		{
			channel = "zigbee",
			direction = "receive",
			message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0004) }
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
		}
	}
)

test.register_message_test(
	"IAS Zone status change notification emits tamper clear",
	{
		{
			channel = "zigbee",
			direction = "receive",
			message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0000, 0x00) }
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
		}
	}
)

test.register_coroutine_test(
	"App armAway emits security status, activity, and panel status",
	function()
		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = capabilities.securitySystem.ID, component = "main", command = capabilities.securitySystem.commands.armAway.NAME, args = {} }
		})

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.securitySystem.securitySystemStatus.armedAway({ state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("armed away by App", { state_change = true, data = { codeName = "App" } }))
		)
		test.socket.zigbee:__expect_send(
			{
				mock_device.id,
				IASACE.client.commands.PanelStatusChanged(
					mock_device,
					PanelStatus.ARMED_AWAY,
					5,
					AudibleNotification.DEFAULT_SOUND,
					AlarmStatus.NO_ALARM
				)
			}
		)
	end
)

test.register_coroutine_test(
	"GetPanelStatus command returns current panel state",
	function()
		test.socket.zigbee:__queue_receive({ mock_device.id, IASACE.server.commands.GetPanelStatus.build_test_rx(mock_device) })

		test.socket.zigbee:__expect_send(
			{
				mock_device.id,
				IASACE.client.commands.GetPanelStatusResponse(
					mock_device,
					PanelStatus.PANEL_DISARMED_READY_TO_ARM,
					5,
					AudibleNotification.DEFAULT_SOUND,
					AlarmStatus.NO_ALARM
				)
			}
		)
	end
)

test.register_coroutine_test(
	"infoChanged pinMap add then delete updates lockCodes and deletion event",
	function()
		local add_data = info_changed_device_data({ pinMap = "1234:Alice" })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", add_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(10, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes(json.encode({ ["1"] = "Alice: 1234" }), { state_change = true }, { visibility = { displayed = true } })
			)
		)

		local delete_data = info_changed_device_data({ deletePinMap = "1234", pinMap = "1234:Alice" })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", delete_data })

		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(10, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("1 deleted", { state_change = true })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes(json.encode({}), { state_change = true }, { visibility = { displayed = true } })
			)
		)
	end
)

test.register_coroutine_test(
	"IAS ACE Arm with known PIN arms system and responds",
	function()
		local add_data = info_changed_device_data({ pinMap = "5678:Bob" })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", add_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(10, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes(json.encode({ ["1"] = "Bob: 5678" }), { state_change = true }, { visibility = { displayed = true } })
			)
		)
		test.wait_for_events()

		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASACE.server.commands.Arm.build_test_rx(mock_device, ArmMode.ARM_ALL_ZONES, "5678", 0)
		})

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.securitySystem.securitySystemStatus.armedAway({ state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("armed away by Bob", { state_change = true, data = { codeName = "Bob" } }))
		)
		test.socket.zigbee:__expect_send(
			{ mock_device.id, IASACE.client.commands.ArmResponse(mock_device, ArmNotification.ALL_ZONES_ARMED) }
		)
	end
)

test.register_coroutine_test(
	"IAS ACE Arm with unknown PIN emits guidance event",
	function()
		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASACE.server.commands.Arm.build_test_rx(mock_device, ArmMode.ARM_ALL_ZONES, "9999", 0)
		})

		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.codeChanged(
					"9999 is not assigned to any user on this keypad. You can create a new user with this code in settings.",
					{ state_change = true }
				)
			)
		)
	end
)

test.register_coroutine_test(
	"Overflow lockCodes payload falls back to chunked codeChanged events with user and pin",
	function()
		local very_long_name = string.rep("A", 280)
		local add_data = info_changed_device_data({ pinMap = "1234:" .. very_long_name })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", add_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(10, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes(json.encode({}), { state_change = true }, { visibility = { displayed = true } })
			)
		)

		local chunk_message = json.encode({ ["1"] = very_long_name .. ": 1234" })
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged(chunk_message, { state_change = true }))
		)
	end
)

test.run_registered_tests()

