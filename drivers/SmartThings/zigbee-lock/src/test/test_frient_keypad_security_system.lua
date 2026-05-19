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
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

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
			capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })
		)
	)
	test.socket.capability:__expect_send(
		mock_device:generate_test_message(
			"main",
			capabilities.mode.mode("Unlocked", { state_change = true })
		)
	)
	test.socket.capability:__expect_send(
		mock_device:generate_test_message(
			"main",
			capabilities.lockCodes.codeChanged("Lock Unlocked by App", { state_change = true, data = { codeName = "App" } })
		)
	)
	test.socket.capability:__expect_send(
		mock_device:generate_test_message(
			"main",
			capabilities.securitySystem.securitySystemStatus.disarmed({ state_change = true })
		)
	)
	test.socket.capability:__expect_send(
		mock_device:generate_test_message(
			"main",
			capabilities.lockCodes.codeChanged("Security System disarmed by App", { state_change = true, data = { codeName = "App" } })
		)
	)
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main",
      capabilities.panicAlarm.panicAlarm.clear({ state_change = true })
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
	"Added lifecycle emits supported events",
	function()
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.mode.supportedModes({ "Locked", "Unlocked" }, { visibility = { displayed = false } })
			)
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.mode.supportedArguments({ "Locked", "Unlocked" }, { visibility = { displayed = false } })
			)
		)
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
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IASZone.ID)
    })
		test.socket.zigbee:__expect_send({
			mock_device.id,
			zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
		})
		test.socket.zigbee:__expect_send({
			mock_device.id,
			PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1)
		})
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.attributes.ZoneStatus:configure_reporting(mock_device, 0, 300, 1)
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
	"IAS Zone tamper attribute report emits tamper clear",
	{
		{
			channel = "zigbee",
			direction = "receive",
			message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0000) }
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
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

test.register_message_test(
	"IAS Zone status change notification emits tamper detected",
	{
		{
			channel = "zigbee",
			direction = "receive",
			message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0004, 0x00) }
		},
		{
			channel = "capability",
			direction = "send",
			message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
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
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("Security System armed away by App", { state_change = true, data = { codeName = "App" } }))
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
	"infoChanged pinMap add updates lockCodes",
	function()
		local add_data = info_changed_device_data({ pinMap = "1234:Alice", showPinSnapshot = true })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", add_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes(json.encode({ ["1"] = "Alice: 1234" }), { state_change = true }, { visibility = { displayed = true } })
			)
		)
	end
)

test.register_coroutine_test(
	"infoChanged pinMap add updates lockCodes rejecting invalid pins",
	function()
		local add_data = info_changed_device_data({ pinMap = "1234:Alice,asded:Bob,23ad23:Charlie,4321:David", showPinSnapshot = true })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", add_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes("{\"1\":\"Alice: 1234\",\"2\":\"David: 4321\"}", { state_change = true }, { visibility = { displayed = true } })
			)
		)
	end
)

test.register_coroutine_test(
	"infoChanged pinMap and rfidMap filters invalid pins and keeps RFID prefix",
	function()
		local update_data = info_changed_device_data({
			pinMap = "123:Short,1234:Good,12AB:Bad,123456789012345678901234567890123:TooLong",
			rfidMap = "+AB:Tag",
			showPinSnapshot = true
		})
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes(
					"{\"1\":\"Good: 1234\",\"2\":\"Tag: +AB\"}",
					{ state_change = true },
					{ visibility = { displayed = true } }
				)
			)
		)
	end
)

test.register_coroutine_test(
	"infoChanged pinMap and rfidMap are sorted deterministically",
	function()
		local update_data = info_changed_device_data({
			pinMap = "9999:Zed,1111:Ann",
			rfidMap = "+BBBB:Bee,+AAAA:Ace",
			showPinSnapshot = true
		})
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes(
					"{\"1\":\"Ann: 1111\",\"2\":\"Zed: 9999\",\"3\":\"Ace: +AAAA\",\"4\":\"Bee: +BBBB\"}",
					{ state_change = true },
					{ visibility = { displayed = true } }
				)
			)
		)
	end
)

test.register_coroutine_test(
	"infoChanged updates IAS ACE preference writes",
	function()
		local update_data = info_changed_device_data({
			autoArmDisarmMode = 2,
			autoDisarmModeSetting = true,
			autoArmModeSetting = 3,
			autoArmModeSettingBool = false,
			pinLengthSetting = 6,
		})
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		test.socket.zigbee:__set_channel_ordering("relaxed")
		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))

		local auto_arm_disarm_msg = cluster_base.write_manufacturer_specific_attribute(mock_device, IASACE.ID, 0x8003, 0x1015, data_types.Enum8, 2)
		auto_arm_disarm_msg.body.zcl_header.frame_ctrl:set_direction_client()
		local auto_disarm_mode_msg = cluster_base.write_manufacturer_specific_attribute(mock_device, IASACE.ID, 0x8004, 0x1015, data_types.Boolean, true)
		auto_disarm_mode_msg.body.zcl_header.frame_ctrl:set_direction_client()
		local auto_arm_mode_msg = cluster_base.write_manufacturer_specific_attribute(mock_device, IASACE.ID, 0x8005, 0x1015, data_types.Enum8, 3)
		auto_arm_mode_msg.body.zcl_header.frame_ctrl:set_direction_client()
		local auto_arm_mode_bool_msg = cluster_base.write_manufacturer_specific_attribute(mock_device, IASACE.ID, 0x8005, 0x1015, data_types.Enum8, 0)
		auto_arm_mode_bool_msg.body.zcl_header.frame_ctrl:set_direction_client()
		local pin_length_msg = cluster_base.write_manufacturer_specific_attribute(mock_device, IASACE.ID, 0x8006, 0x1015, data_types.Uint8, 6)
		pin_length_msg.body.zcl_header.frame_ctrl:set_direction_client()

		test.socket.zigbee:__expect_send({ mock_device.id, auto_arm_disarm_msg })
		test.socket.zigbee:__expect_send({ mock_device.id, auto_disarm_mode_msg })
		test.socket.zigbee:__expect_send({ mock_device.id, auto_arm_mode_msg })
		test.socket.zigbee:__expect_send({ mock_device.id, auto_arm_mode_bool_msg })
		test.socket.zigbee:__expect_send({ mock_device.id, pin_length_msg })
	end
)

test.register_coroutine_test(
	"infoChanged mode to 1 emits mode activity and refresh",
	function()
		local update_data = info_changed_device_data({ mode = 1 })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.mode.mode("Unlocked", { state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.codeChanged("Lock Unlocked by App", { state_change = true, data = { codeName = "App" } })
			)
		)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
      }
    )
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

test.register_coroutine_test(
	"Mode setMode locked emits mode and panel status",
	function()
		local update_data = info_changed_device_data({ mode = 1 })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.mode.mode("Unlocked", { state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.codeChanged("Lock Unlocked by App", { state_change = true, data = { codeName = "App" } })
			)
		)
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
      }
    )
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
		test.wait_for_events()

		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = capabilities.mode.ID, component = "main", command = capabilities.mode.commands.setMode.NAME, args = { "Locked" }, named_args = { mode = "Locked" } }
		})

		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.mode.mode("Locked", { state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.codeChanged("Lock Locked by App", { state_change = true, data = { codeName = "App" } })
			)
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
	"Mode setMode unlocked emits mode and panel status",
	function()
		local update_data = info_changed_device_data({ mode = 1 })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.mode.mode("Unlocked", { state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.codeChanged("Lock Unlocked by App", { state_change = true, data = { codeName = "App" } })
			)
		)
		test.socket.zigbee:__expect_send(
			{
				mock_device.id,
				PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
			}
		)
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
		test.wait_for_events()

		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = capabilities.mode.ID, component = "main", command = capabilities.mode.commands.setMode.NAME, args = { "Locked" }, named_args = { mode = "Locked" } }
		})

		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.mode.mode("Locked", { state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.codeChanged("Lock Locked by App", { state_change = true, data = { codeName = "App" } })
			)
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
		test.wait_for_events()

		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = capabilities.mode.ID, component = "main", command = capabilities.mode.commands.setMode.NAME, args = { "Unlocked" }, named_args = { mode = "Unlocked" } }
		})

		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.mode.mode("Unlocked", { state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.codeChanged("Lock Unlocked by App", { state_change = true, data = { codeName = "App" } })
			)
		)
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

test.register_coroutine_test(
	"IAS ACE Arm with known PIN arms system and responds",
	function()
		local add_data = info_changed_device_data({ pinMap = "5678:Bob", showPinSnapshot = true })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", add_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
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
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("Security System armed away by Bob", { state_change = true, data = { codeName = "Bob" } }))
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
	"Overflow lockCodes payload emits lockCodes event",
	function()
		local very_long_name = string.rep("A", 280)
		local add_data = info_changed_device_data({ pinMap = "1234:" .. very_long_name, showPinSnapshot = true })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", add_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))

		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes(
					json.encode({ ["1"] = very_long_name .. ": 1234" }),
					{ state_change = true },
					{ visibility = { displayed = true } }
				)
			)
		)
	end
)

test.register_coroutine_test(
	"Emergency command triggers panicAlarm, which clears after 10s",
	function()
		test.socket.zigbee:__queue_receive({ mock_device.id, IASACE.server.commands.Emergency.build_test_rx(mock_device) })

		test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.panicAlarm.panicAlarm.panic({ state_change = true })
      )
    )
    test.timer.__create_and_queue_test_time_advance_timer(10, "oneshot")
    test.mock_time.advance_time(10)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.panicAlarm.panicAlarm.clear({ state_change = true })
      )
    )
	end
)

test.register_coroutine_test(
  "Emergency command does not trigger panicAlarm if panicAlarmActive preference is set to false and sends correct response (AlarmStatus.NO_ALARM) to prevent keypad from blinking the yellow LED",
  function()
    local update_data = info_changed_device_data({ panicAlarmActive = false })
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

    test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({ mock_device.id, IASACE.server.commands.Emergency.build_test_rx(mock_device) })

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

test.register_coroutine_test(
	"Emergency command with panicAlarmActive false uses current panel status",
	function()
		local update_data = info_changed_device_data({ panicAlarmActive = false })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.wait_for_events()

		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = capabilities.securitySystem.ID, component = "main", command = capabilities.securitySystem.commands.armAway.NAME, args = {} }
		})

		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.securitySystem.securitySystemStatus.armedAway({ state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("Security System armed away by App", { state_change = true, data = { codeName = "App" } }))
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
		test.wait_for_events()

		test.socket.zigbee:__queue_receive({ mock_device.id, IASACE.server.commands.Emergency.build_test_rx(mock_device) })
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
	"PINs and rfids are not displayed when showPinSnapshot is set to false",
	function()
		local update_data = info_changed_device_data({ rfidMap = "+ABCD1234:Alice", pinMap = "1111:Bob,2222:Charlie", showPinSnapshot = false })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes("{\"1\":\"Bob\",\"2\":\"Charlie\",\"3\":\"Alice\"}", { state_change = true }, { visibility = { displayed = true } })
			)
		)
		test.wait_for_events()
	end
)

test.register_coroutine_test(
	"App armAway with exit delay sends panel status and clears after delay",
	function()
		local update_data = info_changed_device_data({ exitDelay = true, duration = 10 })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		-- Ensure both channels use relaxed ordering so interleaved zigbee/capability
		-- messages from the exit-delay flow are matched reliably by the harness.
		test.socket.zigbee:__set_channel_ordering("relaxed")
		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.wait_for_events()

		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = capabilities.securitySystem.ID, component = "main", command = capabilities.securitySystem.commands.armAway.NAME, args = {} }
		})

		test.socket.zigbee:__set_channel_ordering("relaxed")
		test.socket.zigbee:__expect_send({
			mock_device.id,
			IASACE.client.commands.PanelStatusChanged(
				mock_device,
				PanelStatus.EXIT_DELAY,
				10,
				AudibleNotification.DEFAULT_SOUND,
				AlarmStatus.NO_ALARM
			)
		})

		test.socket.capability:__set_channel_ordering("relaxed")
		--[[ test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.securitySystem.securitySystemStatus.armedAway({ state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("Security System armed away by App", { state_change = true, data = { codeName = "App" } }))
		)
		test.socket.zigbee:__expect_send(
			{
				mock_device.id,
				IASACE.client.commands.PanelStatusChanged(
					mock_device,
					PanelStatus.ARMED_AWAY,
					10,
					AudibleNotification.DEFAULT_SOUND,
					AlarmStatus.NO_ALARM
				)
			}
		) ]]

		-- allow the command processing to run and any immediate emissions to be delivered
		test.wait_for_events()
	end
)

test.register_coroutine_test(
	"GetPanelStatus returns EXIT_DELAY during active exit delay",
	function()
		local update_data = info_changed_device_data({ exitDelay = true, duration = 10 })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.wait_for_events()

		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = capabilities.securitySystem.ID, component = "main", command = capabilities.securitySystem.commands.armAway.NAME, args = {} }
		})

		test.socket.zigbee:__set_channel_ordering("relaxed")
		test.socket.zigbee:__expect_send({
			mock_device.id,
			IASACE.client.commands.PanelStatusChanged(
				mock_device,
				PanelStatus.EXIT_DELAY,
				10,
				AudibleNotification.DEFAULT_SOUND,
				AlarmStatus.NO_ALARM
			)
		})
		test.wait_for_events()

		test.socket.zigbee:__queue_receive({ mock_device.id, IASACE.server.commands.GetPanelStatus.build_test_rx(mock_device) })
		test.socket.zigbee:__expect_send(
			{
				mock_device.id,
				IASACE.client.commands.GetPanelStatusResponse(
					mock_device,
					PanelStatus.EXIT_DELAY,
					10,
					AudibleNotification.DEFAULT_SOUND,
					AlarmStatus.NO_ALARM
				)
			}
		)
	end
)

--[[ test.register_coroutine_test(
	"RFID disarm command in auto-disarm mode works when armedAway",
	function()
		local update_data = info_changed_device_data({ rfidMap = "+ABCD1234:Alice", autoArmDisarmMode = 0, autoDisarmModeSetting = true })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes(json.encode({ ["1"] = "Alice" }), { state_change = true }, { visibility = { displayed = true } })
			)
		)

		-- allow the command processing to run and any immediate emissions to be delivered
		test.wait_for_events()
		local auto_disarm_msg = cluster_base.write_manufacturer_specific_attribute(mock_device, IASACE.ID, 0x8004, 0x1015, data_types.Boolean, true)
		auto_disarm_msg.body.zcl_header.frame_ctrl:set_direction_client()
		test.socket.zigbee:__set_channel_ordering("relaxed")
		test.socket.zigbee:__expect_send({ mock_device.id, auto_disarm_msg })
		test.wait_for_events()

		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = capabilities.securitySystem.ID, component = "main", command = capabilities.securitySystem.commands.armAway.NAME, args = {} }
		})

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.securitySystem.securitySystemStatus.armedAway({ state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("Security System armed away by App", { state_change = true, data = { codeName = "App" } }))
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
		test.wait_for_events()

		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASACE.server.commands.Arm.build_test_rx(mock_device, ArmMode.DISARM, "+ABCD1234", 0)
		})

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.securitySystem.securitySystemStatus.disarmed({ state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("Security System disarmed by Alice", { state_change = true, data = { codeName = "Alice" } }))
		)
		test.socket.zigbee:__expect_send(
			{ mock_device.id, IASACE.client.commands.ArmResponse(mock_device, ArmNotification.ALL_ZONES_DISARMED) }
		)
	end
)

test.register_coroutine_test(
	"PIN disarm command in auto-disarm mode works when armedAway",
	function()
		local update_data = info_changed_device_data({ rfidMap = "1234:Alice", autoArmDisarmMode = 2, autoDisarmModeSetting = true})
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes(json.encode({ ["1"] = "Alice" }), { state_change = true }, { visibility = { displayed = true } })
			)
		)
		local auto_arm_msg = cluster_base.write_manufacturer_specific_attribute(mock_device, IASACE.ID, 0x8003, 0x1015, data_types.Enum8, 2)
		auto_arm_msg.body.zcl_header.frame_ctrl:set_direction_client()
		local auto_disarm_msg = cluster_base.write_manufacturer_specific_attribute(mock_device, IASACE.ID, 0x8004, 0x1015, data_types.Boolean, true)
		auto_disarm_msg.body.zcl_header.frame_ctrl:set_direction_client()
		test.socket.zigbee:__set_channel_ordering("relaxed")
		test.socket.zigbee:__expect_send({ mock_device.id, auto_arm_msg })
		test.socket.zigbee:__expect_send({ mock_device.id, auto_disarm_msg })
		test.wait_for_events()

		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = capabilities.securitySystem.ID, component = "main", command = capabilities.securitySystem.commands.armAway.NAME, args = {} }
		})

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.securitySystem.securitySystemStatus.armedAway({ state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("Security System armed away by App", { state_change = true, data = { codeName = "App" } }))
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
		test.wait_for_events()

		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASACE.server.commands.Arm.build_test_rx(mock_device, ArmMode.DISARM, "1234", 0)
		})

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.securitySystem.securitySystemStatus.disarmed({ state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("Security System disarmed by Alice", { state_change = true, data = { codeName = "Alice" } }))
		)
		test.socket.zigbee:__expect_send(
			{ mock_device.id, IASACE.client.commands.ArmResponse(mock_device, ArmNotification.ALL_ZONES_DISARMED) }
		)
	end
) ]]

--[[ test.register_coroutine_test(
	"PIN disarm command in auto-disarm mode works when armedAway and pin length for auto arming/disarming is changed",
	function()
		local update_data = info_changed_device_data({ rfidMap = "123456:Alice", autoArmDisarmMode = 2, autoDisarmModeSetting = true, pinLengthSetting = 6 })
		test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", update_data })

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(32, { visibility = { displayed = true } })))
		test.socket.capability:__expect_send(
			mock_device:generate_test_message(
				"main",
				capabilities.lockCodes.lockCodes(json.encode({ ["1"] = "Alice" }), { state_change = true }, { visibility = { displayed = true } })
			)
		)
		local auto_arm_msg = cluster_base.write_manufacturer_specific_attribute(mock_device, IASACE.ID, 0x8003, 0x1015, data_types.Enum8, 2)
		auto_arm_msg.body.zcl_header.frame_ctrl:set_direction_client()
		local auto_disarm_msg = cluster_base.write_manufacturer_specific_attribute(mock_device, IASACE.ID, 0x8004, 0x1015, data_types.Boolean, true)
		auto_disarm_msg.body.zcl_header.frame_ctrl:set_direction_client()
		test.socket.zigbee:__set_channel_ordering("relaxed")
		test.socket.zigbee:__expect_send({ mock_device.id, auto_arm_msg })
		test.socket.zigbee:__expect_send({ mock_device.id, auto_disarm_msg })
		test.wait_for_events()

		test.socket.capability:__queue_receive({
			mock_device.id,
			{ capability = capabilities.securitySystem.ID, component = "main", command = capabilities.securitySystem.commands.armAway.NAME, args = {} }
		})

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.securitySystem.securitySystemStatus.armedAway({ state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("Security System armed away by App", { state_change = true, data = { codeName = "App" } }))
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
		test.wait_for_events()

		test.socket.zigbee:__queue_receive({
			mock_device.id,
			IASACE.server.commands.Arm.build_test_rx(mock_device, ArmMode.DISARM, "1234", 0)
		})

		test.socket.capability:__set_channel_ordering("relaxed")
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.securitySystem.securitySystemStatus.disarmed({ state_change = true }))
		)
		test.socket.capability:__expect_send(
			mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("Security System disarmed by Alice", { state_change = true, data = { codeName = "Alice" } }))
		)
		test.socket.zigbee:__expect_send(
			{ mock_device.id, IASACE.client.commands.ArmResponse(mock_device, ArmNotification.ALL_ZONES_DISARMED) }
		)
	end
)
 ]]

test.run_registered_tests()

