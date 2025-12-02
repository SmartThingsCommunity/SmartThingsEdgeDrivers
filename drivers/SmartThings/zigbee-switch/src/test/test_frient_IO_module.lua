-- Copyright 2025 SmartThings
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"
local messages = require "st.zigbee.messages"
local constants = require "st.zigbee.constants"
local zdo_messages = require "st.zigbee.zdo"
local bind_request = require "st.zigbee.zdo.bind_request"
local unbind_request = require "frient-IO.unbind_request"
local default_response = require "st.zigbee.zcl.global_commands.default_response"
local zcl_messages = require "st.zigbee.zcl"
local Status = require "st.zigbee.generated.types.ZclStatus"

local BasicInput = clusters.BasicInput
local OnOff = clusters.OnOff
local Switch = capabilities.switch

local ZIGBEE_ENDPOINTS = {
	INPUT_1 = 0x70,
	INPUT_2 = 0x71,
	INPUT_3 = 0x72,
	INPUT_4 = 0x73,
	OUTPUT_1 = 0x74,
	OUTPUT_2 = 0x75,
}

local INPUT_ENDPOINTS = {
	ZIGBEE_ENDPOINTS.INPUT_1,
	ZIGBEE_ENDPOINTS.INPUT_2,
	ZIGBEE_ENDPOINTS.INPUT_3,
	ZIGBEE_ENDPOINTS.INPUT_4,
}
local OUTPUT_ENDPOINTS = {
	ZIGBEE_ENDPOINTS.OUTPUT_1,
	ZIGBEE_ENDPOINTS.OUTPUT_2,
}

local DEVELCO_MFG_CODE = 0x1015
local ON_TIME_ATTR = 0x8000
local OFF_WAIT_ATTR = 0x8001

local function sanitize_timing(value)
	local v = tonumber(value) or 0
	if v < 0 then
		v = 0
	elseif v > 0xFFFF then
		v = 0xFFFF
	end
	return math.tointeger(v) or 0
end

local function to_deciseconds(value)
	return math.floor(sanitize_timing(value) * 10)
end

local function build_client_mfg_write(device, endpoint, attr_id, value)
	local msg = cluster_base.write_manufacturer_specific_attribute(
		device,
		BasicInput.ID,
		attr_id,
		DEVELCO_MFG_CODE,
		data_types.Uint16,
		value
	)
	msg.body.zcl_header.frame_ctrl:set_direction_client()
	msg.tx_options = data_types.Uint16(0)
	return msg:to_endpoint(endpoint)
end

local function build_basic_input_polarity_write(device, endpoint, enabled)
	local polarity_value = data_types.validate_or_build_type(
		enabled and 1 or 0,
		BasicInput.attributes.Polarity.base_type,
		"payload"
	)
	local msg = cluster_base.write_attribute(
		device,
		data_types.ClusterId(BasicInput.ID),
		data_types.AttributeId(BasicInput.attributes.Polarity.ID),
		polarity_value
	)
	msg.tx_options = data_types.Uint16(0)
	return msg:to_endpoint(endpoint)
end

local function build_bind(device, src_ep, dest_ep)
	local addr_header = messages.AddressHeader(
		constants.HUB.ADDR,
		constants.HUB.ENDPOINT,
		device:get_short_address(),
		device.fingerprinted_endpoint_id,
		constants.ZDO_PROFILE_ID,
		bind_request.BindRequest.ID
	)
	local bind_body = bind_request.BindRequest(
		device.zigbee_eui,
		src_ep,
		BasicInput.ID,
		bind_request.ADDRESS_MODE_64_BIT,
		device.zigbee_eui,
		dest_ep
	)
	local message_body = zdo_messages.ZdoMessageBody({ zdo_body = bind_body })
	local msg = messages.ZigbeeMessageTx({ address_header = addr_header, body = message_body })
	msg.tx_options = data_types.Uint16(0)
	return msg
end

local function build_unbind(device, src_ep, dest_ep)
	local addr_header = messages.AddressHeader(
		constants.HUB.ADDR,
		constants.HUB.ENDPOINT,
		device:get_short_address(),
		device.fingerprinted_endpoint_id,
		constants.ZDO_PROFILE_ID,
		unbind_request.UNBIND_REQUEST_CLUSTER_ID
	)
	local unbind_body = unbind_request.UnbindRequest(
		device.zigbee_eui,
		src_ep,
		BasicInput.ID,
		unbind_request.ADDRESS_MODE_64_BIT,
		device.zigbee_eui,
		dest_ep
	)
	local message_body = zdo_messages.ZdoMessageBody({ zdo_body = unbind_body })
	local msg = messages.ZigbeeMessageTx({ address_header = addr_header, body = message_body })
	msg.tx_options = data_types.Uint16(0)
	return msg
end

local function build_default_response_msg(device, endpoint, command_id)
	local addr_header = messages.AddressHeader(
		device:get_short_address(),
		endpoint,
		constants.HUB.ADDR,
		constants.HUB.ENDPOINT,
		constants.HA_PROFILE_ID,
		OnOff.ID
	)
	local response_body = default_response.DefaultResponse(command_id, Status.SUCCESS)
	local zcl_header = zcl_messages.ZclHeader({
		cmd = data_types.ZCLCommandId(response_body.ID)
	})
	local message_body = zcl_messages.ZclMessageBody({
		zcl_header = zcl_header,
		zcl_body = response_body
	})
	return messages.ZigbeeMessageRx({ address_header = addr_header, body = message_body })
end

local function build_output_timing(device, child, suffix)
	local on_pref
	local off_pref
	if child.preferences.configOnTime ~= nil or child.preferences.configOffWaitTime ~= nil then
		on_pref = child.preferences.configOnTime or 0
		off_pref = child.preferences.configOffWaitTime or 0
	else
		on_pref = device.preferences["configOnTime" .. suffix] or 0
		off_pref = device.preferences["configOffWaitTime" .. suffix] or 0
	end
	return to_deciseconds(on_pref), to_deciseconds(off_pref)
end

local function copy_table(source)
	local result = {}
	for key, value in pairs(source) do
		result[key] = value
	end
	return result
end

local parent_preference_state = {}

local mock_parent_device = test.mock_device.build_test_zigbee_device({
	profile = t_utils.get_profile_definition("switch-4inputs-2outputs.yml"),
	fingerprinted_endpoint_id = ZIGBEE_ENDPOINTS.INPUT_1,
	label = "frient IO Module",
	zigbee_endpoints = {
		[ZIGBEE_ENDPOINTS.INPUT_1] = {
			id = ZIGBEE_ENDPOINTS.INPUT_1,
			manufacturer = "frient A/S",
			model = "IOMZB-110",
			server_clusters = { BasicInput.ID },
		},
		[ZIGBEE_ENDPOINTS.INPUT_2] = {
			id = ZIGBEE_ENDPOINTS.INPUT_2,
			manufacturer = "frient A/S",
			model = "IOMZB-110",
			server_clusters = { BasicInput.ID },
		},
		[ZIGBEE_ENDPOINTS.INPUT_3] = {
			id = ZIGBEE_ENDPOINTS.INPUT_3,
			manufacturer = "frient A/S",
			model = "IOMZB-110",
			server_clusters = { BasicInput.ID },
		},
		[ZIGBEE_ENDPOINTS.INPUT_4] = {
			id = ZIGBEE_ENDPOINTS.INPUT_4,
			manufacturer = "frient A/S",
			model = "IOMZB-110",
			server_clusters = { BasicInput.ID },
		},
		[ZIGBEE_ENDPOINTS.OUTPUT_1] = {
			id = ZIGBEE_ENDPOINTS.OUTPUT_1,
			manufacturer = "frient A/S",
			model = "IOMZB-110",
			server_clusters = { OnOff.ID, BasicInput.ID },
		},
		[ZIGBEE_ENDPOINTS.OUTPUT_2] = {
			id = ZIGBEE_ENDPOINTS.OUTPUT_2,
			manufacturer = "frient A/S",
			model = "IOMZB-110",
			server_clusters = { OnOff.ID, BasicInput.ID },
		},
	},
})

local mock_output_child_1 = test.mock_device.build_test_child_device({
	profile = t_utils.get_profile_definition("frient-io-output-switch.yml"),
	parent_device_id = mock_parent_device.id,
	parent_assigned_child_key = "frient-io-output-1",
	label = "frient IO Module Output 1",
	vendor_provided_label = "Output 1",
})

local mock_output_child_2 = test.mock_device.build_test_child_device({
	profile = t_utils.get_profile_definition("frient-io-output-switch.yml"),
	parent_device_id = mock_parent_device.id,
	parent_assigned_child_key = "frient-io-output-2",
	label = "frient IO Module Output 2",
	vendor_provided_label = "Output 2",
})

local function reset_preferences()
	mock_parent_device.preferences.reversePolarity1 = false
	mock_parent_device.preferences.reversePolarity2 = false
	mock_parent_device.preferences.reversePolarity3 = false
	mock_parent_device.preferences.reversePolarity4 = false

	mock_parent_device.preferences.controlOutput11 = false
	mock_parent_device.preferences.controlOutput21 = false
	mock_parent_device.preferences.controlOutput12 = false
	mock_parent_device.preferences.controlOutput22 = false
	mock_parent_device.preferences.controlOutput13 = false
	mock_parent_device.preferences.controlOutput23 = false
	mock_parent_device.preferences.controlOutput14 = false
	mock_parent_device.preferences.controlOutput24 = false

	mock_parent_device.preferences.configOnTime1 = 3
	mock_parent_device.preferences.configOffWaitTime1 = 4
	mock_parent_device.preferences.configOnTime2 = 7
	mock_parent_device.preferences.configOffWaitTime2 = 8

	mock_output_child_1.preferences.configOnTime = 5
	mock_output_child_1.preferences.configOffWaitTime = 6
	mock_output_child_2.preferences.configOnTime = 0
	mock_output_child_2.preferences.configOffWaitTime = 0

	parent_preference_state = copy_table(mock_parent_device.preferences)

	local field_keys = {
		"frient_io_native_70",
		"frient_io_native_71",
		"frient_io_native_72",
		"frient_io_native_73",
		"frient_io_native_74",
		"frient_io_native_75",
	}

	for _, key in ipairs(field_keys) do
		mock_parent_device:set_field(key, nil, { persist = true })
	end

	mock_output_child_1:set_field("frient_io_native_74", nil, { persist = true })
	mock_output_child_2:set_field("frient_io_native_75", nil, { persist = true })
end

local function queue_child_info_changed(child, preferences)
	local raw = rawget(child, "raw_st_data")
	if raw and raw.preferences then
		for key, value in pairs(preferences) do
			raw.preferences[key] = value
		end
	end
	test.socket.device_lifecycle:__queue_receive(child:generate_info_changed({ preferences = preferences }))
end

local function queue_parent_info_changed(preferences)
	local full_preferences = copy_table(parent_preference_state)
	for key, value in pairs(preferences) do
		full_preferences[key] = value
	end
	parent_preference_state = copy_table(full_preferences)

	local raw = rawget(mock_parent_device, "raw_st_data")
	if raw and raw.preferences then
		for key, value in pairs(full_preferences) do
			raw.preferences[key] = value
		end
	end

	test.socket.device_lifecycle:__queue_receive(
		mock_parent_device:generate_info_changed({ preferences = full_preferences })
	)
end

local function register_initial_config_expectations()
	if test.socket.zigbee and test.socket.zigbee.__set_channel_ordering then
		test.socket.zigbee:__set_channel_ordering("relaxed")
	end
	if test.socket.devices and test.socket.devices.__set_channel_ordering then
		test.socket.devices:__set_channel_ordering("relaxed")
	end

	local on1, off1 = build_output_timing(mock_parent_device, mock_output_child_1, "1")
	local on2, off2 = build_output_timing(mock_parent_device, mock_output_child_2, "2")

	local function enqueue_output_timing_writes()
		test.socket.zigbee:__expect_send({ mock_parent_device.id, build_client_mfg_write(mock_parent_device, ZIGBEE_ENDPOINTS.OUTPUT_1, ON_TIME_ATTR, on1) })
		test.socket.zigbee:__expect_send({ mock_parent_device.id, build_client_mfg_write(mock_parent_device, ZIGBEE_ENDPOINTS.OUTPUT_1, OFF_WAIT_ATTR, off1) })
		test.socket.zigbee:__expect_send({ mock_parent_device.id, build_client_mfg_write(mock_parent_device, ZIGBEE_ENDPOINTS.OUTPUT_2, ON_TIME_ATTR, on2) })
		test.socket.zigbee:__expect_send({ mock_parent_device.id, build_client_mfg_write(mock_parent_device, ZIGBEE_ENDPOINTS.OUTPUT_2, OFF_WAIT_ATTR, off2) })
	end

	-- Device init issues one set of manufacturer-specific writes per output during startup
	enqueue_output_timing_writes()

	for _, endpoint in ipairs(INPUT_ENDPOINTS) do
		test.socket.zigbee:__expect_send({ mock_parent_device.id, build_basic_input_polarity_write(mock_parent_device, endpoint, false) })
		for _, output_ep in ipairs(OUTPUT_ENDPOINTS) do
			test.socket.zigbee:__expect_send({ mock_parent_device.id, build_unbind(mock_parent_device, endpoint, output_ep) })
		end
	end
end

local function expect_init_sequence()
	-- Initialization expectations are registered during test setup; lifecycle events fire as part of driver startup.
end

local function expect_switch_registration(device)
	test.socket.devices:__expect_send({
		"register_native_capability_attr_handler",
		{ device_uuid = device.id, capability_id = "switch", capability_attr_id = "switch" },
	})
end

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
	reset_preferences()
	register_initial_config_expectations()
	test.mock_device.add_test_device(mock_parent_device)
	test.mock_device.add_test_device(mock_output_child_1)
	test.mock_device.add_test_device(mock_output_child_2)
	zigbee_test_utils.init_noop_health_check_timer()
	--register_initial_config_expectations()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
	"Init configures outputs and routes attribute reports",
	function()
		expect_init_sequence()
		test.wait_for_events()

		test.socket.capability:__set_channel_ordering("relaxed")

		test.socket.zigbee:__queue_receive({
			mock_parent_device.id,
			OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device, true):from_endpoint(ZIGBEE_ENDPOINTS.OUTPUT_1),
		})
		test.socket.capability:__expect_send(mock_output_child_1:generate_test_message("main", Switch.switch.on()))
		expect_switch_registration(mock_output_child_1)

		test.socket.zigbee:__queue_receive({
			mock_parent_device.id,
			OnOff.attributes.OnOff:build_test_attr_report(mock_parent_device, false):from_endpoint(ZIGBEE_ENDPOINTS.OUTPUT_2),
		})
		test.socket.capability:__expect_send(mock_output_child_2:generate_test_message("main", Switch.switch.off()))
		expect_switch_registration(mock_output_child_2)

		test.socket.zigbee:__queue_receive({
			mock_parent_device.id,
			BasicInput.attributes.PresentValue:build_test_attr_report(mock_parent_device, true):from_endpoint(ZIGBEE_ENDPOINTS.INPUT_3),
		})
		test.socket.capability:__expect_send(mock_parent_device:generate_test_message("input3", Switch.switch.on()))

		test.wait_for_events()

		local child1_native = mock_output_child_1:get_field("frient_io_native_74")
		assert(child1_native, "expected Output 1 child to register native switch handler")
		local child2_native = mock_output_child_2:get_field("frient_io_native_75")
		assert(child2_native, "expected Output 2 child to register native switch handler")
		local parent_native = mock_parent_device:get_field("frient_io_native_72")
		assert(parent_native, "expected parent device to register native switch handler for input 3")
	end
)

test.register_coroutine_test(
	"Default responses update state and trigger reads",
	function()
		expect_init_sequence()
		test.wait_for_events()
		test.socket.zigbee:__set_channel_ordering("relaxed")
		test.socket.capability:__set_channel_ordering("relaxed")

		local on_response = build_default_response_msg(mock_parent_device, ZIGBEE_ENDPOINTS.OUTPUT_1, OnOff.server.commands.On.ID)
		test.socket.zigbee:__queue_receive({ mock_parent_device.id, on_response })
		test.socket.capability:__expect_send(mock_output_child_1:generate_test_message("main", Switch.switch.on()))

		local timed_response = build_default_response_msg(mock_parent_device, ZIGBEE_ENDPOINTS.OUTPUT_1, OnOff.server.commands.OnWithTimedOff.ID)
		test.socket.zigbee:__queue_receive({ mock_parent_device.id, timed_response })
		local read_msg = cluster_base.read_attribute(
			mock_parent_device,
			data_types.ClusterId(OnOff.ID),
			data_types.AttributeId(OnOff.attributes.OnOff.ID)
		)
		read_msg.tx_options = data_types.Uint16(0)
		read_msg = read_msg:to_endpoint(ZIGBEE_ENDPOINTS.OUTPUT_1)
		test.socket.zigbee:__expect_send({ mock_parent_device.id, read_msg })

		local off_response = build_default_response_msg(mock_parent_device, ZIGBEE_ENDPOINTS.OUTPUT_1, OnOff.server.commands.Off.ID)
		test.socket.zigbee:__queue_receive({ mock_parent_device.id, off_response })
		test.socket.capability:__expect_send(mock_output_child_1:generate_test_message("main", Switch.switch.off()))

		test.wait_for_events()
	end
)

test.register_coroutine_test(
	"Switch commands drive the correct Zigbee commands",
	function()
		expect_init_sequence()
		test.wait_for_events()
		test.socket.zigbee:__set_channel_ordering("relaxed")

		test.socket.capability:__queue_receive({
			mock_output_child_1.id,
			{ capability = "switch", component = "main", command = "on", args = {} },
		})
		local on1, off1 = build_output_timing(mock_parent_device, mock_output_child_1, "1")
		local timed_on = OnOff.server.commands.OnWithTimedOff(
			mock_parent_device,
			data_types.Uint8(0),
			data_types.Uint16(on1),
			data_types.Uint16(off1)
		):to_endpoint(ZIGBEE_ENDPOINTS.OUTPUT_1)
		test.socket.zigbee:__expect_send({ mock_parent_device.id, timed_on })

		test.socket.capability:__queue_receive({
			mock_output_child_1.id,
			{ capability = "switch", component = "main", command = "off", args = {} },
		})
		local timed_off = OnOff.server.commands.OnWithTimedOff(
			mock_parent_device,
			data_types.Uint8(0),
			data_types.Uint16(on1),
			data_types.Uint16(off1)
		):to_endpoint(ZIGBEE_ENDPOINTS.OUTPUT_1)
		test.socket.zigbee:__expect_send({ mock_parent_device.id, timed_off })

		test.socket.capability:__queue_receive({
			mock_output_child_2.id,
			{ capability = "switch", component = "main", command = "on", args = {} },
		})
		local direct_on = OnOff.server.commands.On(mock_parent_device):to_endpoint(ZIGBEE_ENDPOINTS.OUTPUT_2)
		test.socket.zigbee:__expect_send({ mock_parent_device.id, direct_on })

		test.socket.capability:__queue_receive({
			mock_output_child_2.id,
			{ capability = "switch", component = "main", command = "off", args = {} },
		})
		local direct_off = OnOff.server.commands.Off(mock_parent_device):to_endpoint(ZIGBEE_ENDPOINTS.OUTPUT_2)
		test.socket.zigbee:__expect_send({ mock_parent_device.id, direct_off })

		test.socket.capability:__queue_receive({
			mock_parent_device.id,
			{ capability = "switch", component = "output1", command = "on", args = {} },
		})
		test.socket.zigbee:__expect_send({ mock_parent_device.id, timed_on })

		test.socket.capability:__queue_receive({
			mock_parent_device.id,
			{ capability = "switch", component = "output2", command = "off", args = {} },
		})
		test.socket.zigbee:__expect_send({ mock_parent_device.id, direct_off })

		test.wait_for_events()
	end
)

test.register_coroutine_test(
	"Child preference changes send manufacturer writes",
	function()
		expect_init_sequence()
		test.wait_for_events()
		test.socket.zigbee:__set_channel_ordering("relaxed")

		queue_child_info_changed(mock_output_child_1, { configOnTime = 12, configOffWaitTime = 13 })
		test.socket.zigbee:__expect_send({
			mock_parent_device.id,
			build_client_mfg_write(mock_parent_device, ZIGBEE_ENDPOINTS.OUTPUT_1, ON_TIME_ATTR, to_deciseconds(12)),
		})
		test.socket.zigbee:__expect_send({
			mock_parent_device.id,
			build_client_mfg_write(mock_parent_device, ZIGBEE_ENDPOINTS.OUTPUT_1, OFF_WAIT_ATTR, to_deciseconds(13)),
		})

		test.wait_for_events()
	end
)

test.register_coroutine_test(
	"Parent preference changes manage polarity and binds",
	function()
		expect_init_sequence()
		test.wait_for_events()
		test.socket.zigbee:__set_channel_ordering("relaxed")

		queue_parent_info_changed({
			reversePolarity1 = true,
			controlOutput11 = true,
			controlOutput21 = true,
		})
		test.socket.zigbee:__expect_send({
			mock_parent_device.id,
			build_basic_input_polarity_write(mock_parent_device, ZIGBEE_ENDPOINTS.INPUT_1, true),
		})
		test.socket.zigbee:__expect_send({ mock_parent_device.id, build_bind(mock_parent_device, ZIGBEE_ENDPOINTS.INPUT_1, ZIGBEE_ENDPOINTS.OUTPUT_1) })
		test.socket.zigbee:__expect_send({ mock_parent_device.id, build_bind(mock_parent_device, ZIGBEE_ENDPOINTS.INPUT_1, ZIGBEE_ENDPOINTS.OUTPUT_2) })
		test.wait_for_events()

		queue_parent_info_changed({
			reversePolarity1 = true,
			controlOutput11 = false,
			controlOutput21 = true,
		})
		test.socket.zigbee:__expect_send({ mock_parent_device.id, build_unbind(mock_parent_device, ZIGBEE_ENDPOINTS.INPUT_1, ZIGBEE_ENDPOINTS.OUTPUT_1) })
		test.wait_for_events()

		queue_parent_info_changed({
			reversePolarity3 = true,
			controlOutput23 = true,
		})
		test.socket.zigbee:__expect_send({
			mock_parent_device.id,
			build_basic_input_polarity_write(mock_parent_device, ZIGBEE_ENDPOINTS.INPUT_3, true),
		})
		test.socket.zigbee:__expect_send({ mock_parent_device.id, build_bind(mock_parent_device, ZIGBEE_ENDPOINTS.INPUT_3, ZIGBEE_ENDPOINTS.OUTPUT_2) })
		test.wait_for_events()

		queue_parent_info_changed({
			reversePolarity3 = true,
			controlOutput23 = false,
		})
		test.socket.zigbee:__expect_send({ mock_parent_device.id, build_unbind(mock_parent_device, ZIGBEE_ENDPOINTS.INPUT_3, ZIGBEE_ENDPOINTS.OUTPUT_2) })
		test.wait_for_events()
	end
)

test.run_registered_tests()
