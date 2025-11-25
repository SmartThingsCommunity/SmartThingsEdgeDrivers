-- Copyright 2025 SmartThings
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

local log   = require "log"
local utils = require "st.utils"

-- Zigbee Spec Utils
local constants = require "st.zigbee.constants"
local messages = require "st.zigbee.messages"
local zdo_messages = require "st.zigbee.zdo"
local bind_request = require "st.zigbee.zdo.bind_request"
local unbind_request = require "frient-IO.unbind_request"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local switch_defaults = require "st.zigbee.defaults.switch_defaults"
local Status = require "st.zigbee.generated.types.ZclStatus"

local clusters = require "st.zigbee.zcl.clusters"
local BasicInput = clusters.BasicInput
local OnOff = clusters.OnOff
local OnOffControl = OnOff.types.OnOffControl
-- Capabilities
local capabilities = require "st.capabilities"
local Switch = capabilities.switch
local CHILD_OUTPUT_PROFILE = "frient-io-output-switch"

local configurationMap = require "configurations"

local COMPONENTS = {
    INPUT_1 = "input1",
    INPUT_2 = "input2",
    INPUT_3 = "input3",
    INPUT_4 = "input4",
    OUTPUT_1 = "output1",
    OUTPUT_2 = "output2"
}

local ZIGBEE_BRIDGE_FINGERPRINTS = {
    { manufacturer = "frient A/S", model = "IOMZB-110" }
}

local ZIGBEE_ENDPOINTS = {
    INPUT_1 = 0x70,
    INPUT_2 = 0x71,
    INPUT_3 = 0x72,
    INPUT_4 = 0x73,
    OUTPUT_1 = 0x74,
    OUTPUT_2 = 0x75
}

local OUTPUT_INFO = {
    ["1"] = { endpoint = ZIGBEE_ENDPOINTS.OUTPUT_1, key = "frient-io-output-1", label_suffix = "Output 1" },
    ["2"] = { endpoint = ZIGBEE_ENDPOINTS.OUTPUT_2, key = "frient-io-output-2", label_suffix = "Output 2" }
}

local OUTPUT_BY_ENDPOINT, OUTPUT_BY_KEY = {}, {}
for suffix, info in pairs(OUTPUT_INFO) do
    info.suffix = suffix
    OUTPUT_BY_ENDPOINT[info.endpoint] = info
    OUTPUT_BY_KEY[info.key] = info
end

local ZIGBEE_MFG_CODES = {
    Develco = 0x1015
}

local ZIGBEE_MFG_ATTRIBUTES = {
    client = {
        OnWithTimeOff_OnTime = {
            ID = 0x8000,
            data_type = data_types.Uint16
        },
        OnWithTimeOff_OffWaitTime = {
            ID = 0x8001,
            data_type = data_types.Uint16
        }
    },
    server = { IASActivation = {
        ID = 0x8000,
        data_type = data_types.Uint16
    } }
}

local function write_client_manufacturer_specific_attribute(device, cluster_id, attr_id, mfg_specific_code, data_type,
                                                            payload)
    local message = cluster_base.write_manufacturer_specific_attribute(device, cluster_id, attr_id, mfg_specific_code,
        data_type, payload)

    message.body.zcl_header.frame_ctrl:set_direction_client()
    return message
end

local function write_basic_input_polarity_attr(device, ep_id, payload)
    local value = data_types.validate_or_build_type(payload and 1 or 0,
        BasicInput.attributes.Polarity.base_type,
        "payload")
    device:send(cluster_base.write_attribute(device, data_types.ClusterId(BasicInput.ID),
        data_types.AttributeId(BasicInput.attributes.Polarity.ID),
        value):to_endpoint(ep_id))
end

local function ensure_child_devices(device)
    if device.parent_assigned_child_key ~= nil then
        return
    end

    for _, info in pairs(OUTPUT_INFO) do
        local child = device:get_child_by_parent_assigned_key(info.key)
        if child == nil then
            child = device.driver:try_create_device({
                type = "EDGE_CHILD",
                parent_device_id = device.id,
                parent_assigned_child_key = info.key,
                profile = CHILD_OUTPUT_PROFILE,
                label = string.format("%s %s", device.label, info.label_suffix),
                vendor_provided_label = info.label_suffix
            })
            child = child and device:get_child_by_parent_assigned_key(info.key)
        end
        if child then
            child:set_field("endpoint", info.endpoint, { persist = true })
        end
    end
end

local function to_integer(value)
    if value == nil then return nil end
    if type(value) == "number" then return math.tointeger(value) end
    local num = tonumber(value)
    return num and math.tointeger(num) or nil
end

local function sanitize_timing(value)
    local int = to_integer(value) or 0
    if int < 0 then
        int = 0
    elseif int > 0xFFFF then
        int = 0xFFFF
    end
    return int
end

local function get_output_timing(device, suffix)
    local info = OUTPUT_INFO[suffix]
    if not info then return 0, 0 end
    local child = device:get_child_by_parent_assigned_key(info.key)
    if child then
        local on_time = math.floor((sanitize_timing(child.preferences.configOnTime)) * 10)
        local off_wait = math.floor((sanitize_timing(child.preferences.configOffWaitTime)) * 10)
        return on_time, off_wait
    end
    local on_time = math.floor((sanitize_timing(device.preferences["configOnTime" .. suffix]))*10)
    local off_wait = math.floor((sanitize_timing(device.preferences["configOffWaitTime" .. suffix]))*10)
    return on_time, off_wait
end

local function handle_output_command(device, suffix, command_name)
    local info = OUTPUT_INFO[suffix]
    if info == nil then return end
    local config_on_time, config_off_wait_time = get_output_timing(device, suffix)
    local endpoint = info.endpoint

    if command_name == "on" then
        if config_on_time == 0 then
            device:send(OnOff.server.commands.On(device):to_endpoint(endpoint))
        else
            device:send(OnOff.server.commands.OnWithTimedOff(device, data_types.Uint8(0),
                data_types.Uint16(config_on_time), data_types.Uint16(config_off_wait_time)):to_endpoint(endpoint))
        end
    else
        if config_on_time == 0 then
            device:send(OnOff.server.commands.Off(device):to_endpoint(endpoint))
        else
            device:send(OnOff.server.commands.OnWithTimedOff(device, data_types.Uint8(0),
                data_types.Uint16(config_on_time), data_types.Uint16(config_off_wait_time)):to_endpoint(endpoint))
        end
    end
end

local function emit_switch_event_for_endpoint(device, endpoint, event)
    local info = OUTPUT_BY_ENDPOINT[endpoint]
    if info ~= nil then
        local child = device:get_child_by_parent_assigned_key(info.key)
        if child then
            child:emit_event(event)
            return
        end
    end
    device:emit_event_for_endpoint(endpoint, event)
end

local function on_off_attr_handler(driver, device, value, zb_message)
    local endpoint = zb_message.address_header.src_endpoint.value
    emit_switch_event_for_endpoint(device, endpoint, value.value and Switch.switch.on() or Switch.switch.off())
end

local function build_bind_request(device, src_cluster, src_ep_id, dest_ep_id)
    local addr_header = messages.AddressHeader(constants.HUB.ADDR, constants.HUB.ENDPOINT, device:get_short_address(),
        device.fingerprinted_endpoint_id, constants.ZDO_PROFILE_ID, bind_request.BindRequest.ID)

    local bind_req = bind_request.BindRequest(device.zigbee_eui, src_ep_id,
        src_cluster,
        bind_request.ADDRESS_MODE_64_BIT, device.zigbee_eui, dest_ep_id)
    local message_body = zdo_messages.ZdoMessageBody({
        zdo_body = bind_req
    })
    local bind_cmd = messages.ZigbeeMessageTx({
        address_header = addr_header,
        body = message_body
    })
    return bind_cmd
end

local function build_unbind_request(device, src_cluster, src_ep_id, dest_ep_id)
    local addr_header = messages.AddressHeader(constants.HUB.ADDR, constants.HUB.ENDPOINT, device:get_short_address(),
        device.fingerprinted_endpoint_id, constants.ZDO_PROFILE_ID, unbind_request.UNBIND_REQUEST_CLUSTER_ID)

    local unbind_req = unbind_request.UnbindRequest(device.zigbee_eui, src_ep_id,
        src_cluster,
        unbind_request.ADDRESS_MODE_64_BIT, device.zigbee_eui, dest_ep_id)
    local message_body = zdo_messages.ZdoMessageBody({
        zdo_body = unbind_req
    })
    local bind_cmd = messages.ZigbeeMessageTx({
        address_header = addr_header,
        body = message_body
    })
    return bind_cmd
end

local function component_to_endpoint(device, component_id)
    if component_id == COMPONENTS.INPUT_1 then
        return ZIGBEE_ENDPOINTS.INPUT_1
    elseif component_id == COMPONENTS.INPUT_2 then
        return ZIGBEE_ENDPOINTS.INPUT_2
    elseif component_id == COMPONENTS.INPUT_3 then
        return ZIGBEE_ENDPOINTS.INPUT_3
    elseif component_id == COMPONENTS.INPUT_4 then
        return ZIGBEE_ENDPOINTS.INPUT_4
    elseif component_id == COMPONENTS.OUTPUT_1 then
        return ZIGBEE_ENDPOINTS.OUTPUT_1
    elseif component_id == COMPONENTS.OUTPUT_2 then
        return ZIGBEE_ENDPOINTS.OUTPUT_2
    else
        return device.fingerprinted_endpoint_id
    end
end

local function endpoint_to_component(device, ep)
    local ep_id = type(ep) == "table" and ep.value or ep
    if ep_id == ZIGBEE_ENDPOINTS.INPUT_1 then
        return COMPONENTS.INPUT_1
    elseif ep_id == ZIGBEE_ENDPOINTS.INPUT_2 then
        return COMPONENTS.INPUT_2
    elseif ep_id == ZIGBEE_ENDPOINTS.INPUT_3 then
        return COMPONENTS.INPUT_3
    elseif ep_id == ZIGBEE_ENDPOINTS.INPUT_4 then
        return COMPONENTS.INPUT_4
    elseif ep_id == ZIGBEE_ENDPOINTS.OUTPUT_1 then
        return COMPONENTS.OUTPUT_1
    elseif ep_id == ZIGBEE_ENDPOINTS.OUTPUT_2 then
        return COMPONENTS.OUTPUT_2
    else
        return "main"
    end
end

local function init_handler(self, device)
    device:set_component_to_endpoint_fn(component_to_endpoint)
    device:set_endpoint_to_component_fn(endpoint_to_component)

    if device.parent_assigned_child_key ~= nil then
        return
    end

    ensure_child_devices(device)

    local on1, off1 = get_output_timing(device, "1")
    device:send(write_client_manufacturer_specific_attribute(device, BasicInput.ID,
        ZIGBEE_MFG_ATTRIBUTES.client.OnWithTimeOff_OnTime.ID, ZIGBEE_MFG_CODES.Develco,
        ZIGBEE_MFG_ATTRIBUTES.client.OnWithTimeOff_OnTime.data_type,
        on1):to_endpoint(ZIGBEE_ENDPOINTS.OUTPUT_1))
    device:send(write_client_manufacturer_specific_attribute(device, BasicInput.ID,
        ZIGBEE_MFG_ATTRIBUTES.client.OnWithTimeOff_OffWaitTime.ID, ZIGBEE_MFG_CODES.Develco,
        ZIGBEE_MFG_ATTRIBUTES.client.OnWithTimeOff_OffWaitTime.data_type,
        off1):to_endpoint(ZIGBEE_ENDPOINTS.OUTPUT_1))

    local on2, off2 = get_output_timing(device, "2")
    device:send(write_client_manufacturer_specific_attribute(device, BasicInput.ID,
        ZIGBEE_MFG_ATTRIBUTES.client.OnWithTimeOff_OnTime.ID, ZIGBEE_MFG_CODES.Develco,
        ZIGBEE_MFG_ATTRIBUTES.client.OnWithTimeOff_OnTime.data_type,
        on2):to_endpoint(ZIGBEE_ENDPOINTS.OUTPUT_2))
    device:send(write_client_manufacturer_specific_attribute(device, BasicInput.ID,
        ZIGBEE_MFG_ATTRIBUTES.client.OnWithTimeOff_OffWaitTime.ID, ZIGBEE_MFG_CODES.Develco,
        ZIGBEE_MFG_ATTRIBUTES.client.OnWithTimeOff_OffWaitTime.data_type,
        off2):to_endpoint(ZIGBEE_ENDPOINTS.OUTPUT_2))

    -- Input 1
    write_basic_input_polarity_attr(device, ZIGBEE_ENDPOINTS.INPUT_1, device.preferences.reversePolarity1)

    device:send(device.preferences.controlOutput11
        and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_1, ZIGBEE_ENDPOINTS.OUTPUT_1)
        or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_1, ZIGBEE_ENDPOINTS.OUTPUT_1))

    device:send(device.preferences.controlOutput21
        and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_1, ZIGBEE_ENDPOINTS.OUTPUT_2)
        or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_1, ZIGBEE_ENDPOINTS.OUTPUT_2))

    -- Input 2
    write_basic_input_polarity_attr(device, ZIGBEE_ENDPOINTS.INPUT_2, device.preferences.reversePolarity2)

    device:send(device.preferences.controlOutput12
        and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_2, ZIGBEE_ENDPOINTS.OUTPUT_1)
        or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_2, ZIGBEE_ENDPOINTS.OUTPUT_1))

    device:send(device.preferences.controlOutput22
        and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_2, ZIGBEE_ENDPOINTS.OUTPUT_2)
        or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_2, ZIGBEE_ENDPOINTS.OUTPUT_2))

    -- Input 3
    write_basic_input_polarity_attr(device, ZIGBEE_ENDPOINTS.INPUT_3, device.preferences.reversePolarity3)

    device:send(device.preferences.controlOutput13
        and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_3, ZIGBEE_ENDPOINTS.OUTPUT_1)
        or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_3, ZIGBEE_ENDPOINTS.OUTPUT_1))

    device:send(device.preferences.controlOutput23
        and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_3, ZIGBEE_ENDPOINTS.OUTPUT_2)
        or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_3, ZIGBEE_ENDPOINTS.OUTPUT_2))

    -- Input 4
    write_basic_input_polarity_attr(device, ZIGBEE_ENDPOINTS.INPUT_4, device.preferences.reversePolarity4)

    device:send(device.preferences.controlOutput14
        and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_4, ZIGBEE_ENDPOINTS.OUTPUT_1)
        or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_4, ZIGBEE_ENDPOINTS.OUTPUT_1))

    device:send(device.preferences.controlOutput24
        and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_4, ZIGBEE_ENDPOINTS.OUTPUT_2)
        or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_4, ZIGBEE_ENDPOINTS.OUTPUT_2))
end

local function configure_handler(self, device)
    local configuration = configurationMap.get_device_configuration(device)
    if configuration ~= nil then
        for _, attribute in ipairs(configuration) do
            if attribute.configurable ~= false then
                device:add_configured_attribute(attribute)
            end
        end
    end
    device:configure()
end

local function info_changed_handler(self, device, event, args)
    if device.parent_assigned_child_key ~= nil then
        -- This is a child device
        local parent = device:get_parent_device()
        if not parent then return end

        local info = OUTPUT_BY_KEY[device.parent_assigned_child_key]
        if not info then return end

        -- Child devices have simple preference names without suffix
        local on_time = math.floor(sanitize_timing(device.preferences.configOnTime) * 10)
        local off_wait = math.floor(sanitize_timing(device.preferences.configOffWaitTime) * 10)

        parent:send(write_client_manufacturer_specific_attribute(parent, BasicInput.ID,
            ZIGBEE_MFG_ATTRIBUTES.client.OnWithTimeOff_OnTime.ID, ZIGBEE_MFG_CODES.Develco,
            ZIGBEE_MFG_ATTRIBUTES.client.OnWithTimeOff_OnTime.data_type,
            on_time):to_endpoint(info.endpoint))

        parent:send(write_client_manufacturer_specific_attribute(parent, BasicInput.ID,
            ZIGBEE_MFG_ATTRIBUTES.client.OnWithTimeOff_OffWaitTime.ID, ZIGBEE_MFG_CODES.Develco,
            ZIGBEE_MFG_ATTRIBUTES.client.OnWithTimeOff_OffWaitTime.data_type,
            off_wait):to_endpoint(info.endpoint))
        return
    else
        -- Input 1
        if args.old_st_store.preferences.reversePolarity1 ~= device.preferences.reversePolarity1 then
            write_basic_input_polarity_attr(device, ZIGBEE_ENDPOINTS.INPUT_1, device.preferences.reversePolarity1)
        end

        if args.old_st_store.preferences.controlOutput11 ~= device.preferences.controlOutput11 then
            device:send(device.preferences.controlOutput11
                and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_1, ZIGBEE_ENDPOINTS.OUTPUT_1)
                or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_1, ZIGBEE_ENDPOINTS.OUTPUT_1))
        end

        if args.old_st_store.preferences.controlOutput21 ~= device.preferences.controlOutput21 then
            device:send(device.preferences.controlOutput21
                and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_1, ZIGBEE_ENDPOINTS.OUTPUT_2)
                or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_1, ZIGBEE_ENDPOINTS.OUTPUT_2))
        end

        -- Input 2
        if args.old_st_store.preferences.reversePolarity2 ~= device.preferences.reversePolarity2 then
            write_basic_input_polarity_attr(device, ZIGBEE_ENDPOINTS.INPUT_2, device.preferences.reversePolarity2)
        end

        if args.old_st_store.preferences.controlOutput12 ~= device.preferences.controlOutput12 then
            device:send(device.preferences.controlOutput12
                and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_2, ZIGBEE_ENDPOINTS.OUTPUT_1)
                or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_2, ZIGBEE_ENDPOINTS.OUTPUT_1))
        end

        if args.old_st_store.preferences.controlOutput22 ~= device.preferences.controlOutput22 then
            device:send(device.preferences.controlOutput22
                and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_2, ZIGBEE_ENDPOINTS.OUTPUT_2)
                or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_2, ZIGBEE_ENDPOINTS.OUTPUT_2))
        end

        -- Input 3
        if args.old_st_store.preferences.reversePolarity3 ~= device.preferences.reversePolarity3 then
            write_basic_input_polarity_attr(device, ZIGBEE_ENDPOINTS.INPUT_3, device.preferences.reversePolarity3)
        end

        if args.old_st_store.preferences.controlOutput13 ~= device.preferences.controlOutput13 then
            device:send(device.preferences.controlOutput13
                and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_3, ZIGBEE_ENDPOINTS.OUTPUT_1)
                or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_3, ZIGBEE_ENDPOINTS.OUTPUT_1))
        end

        if args.old_st_store.preferences.controlOutput23 ~= device.preferences.controlOutput23 then
            device:send(device.preferences.controlOutput23
                and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_3, ZIGBEE_ENDPOINTS.OUTPUT_2)
                or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_3, ZIGBEE_ENDPOINTS.OUTPUT_2))
        end

        -- Input 4
        if args.old_st_store.preferences.reversePolarity4 ~= device.preferences.reversePolarity4 then
            write_basic_input_polarity_attr(device, ZIGBEE_ENDPOINTS.INPUT_4, device.preferences.reversePolarity4)
        end

        if args.old_st_store.preferences.controlOutput14 ~= device.preferences.controlOutput14 then
            device:send(device.preferences.controlOutput14
                and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_4, ZIGBEE_ENDPOINTS.OUTPUT_1)
                or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_4, ZIGBEE_ENDPOINTS.OUTPUT_1))
        end

        if args.old_st_store.preferences.controlOutput24 ~= device.preferences.controlOutput24 then
            device:send(device.preferences.controlOutput24
                and build_bind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_4, ZIGBEE_ENDPOINTS.OUTPUT_2)
                or build_unbind_request(device, BasicInput.ID, ZIGBEE_ENDPOINTS.INPUT_4, ZIGBEE_ENDPOINTS.OUTPUT_2))
        end
    end
end

local function present_value_attr_handler(driver, device, value, zb_message)
    local ep_id = zb_message.address_header.src_endpoint
    device:emit_event_for_endpoint(ep_id, value.value and Switch.switch.on() or Switch.switch.off())
end

local function on_off_default_response_handler(driver, device, zb_rx)
    local status = zb_rx.body.zcl_body.status.value
    local endpoint = zb_rx.address_header.src_endpoint.value

    if status == Status.SUCCESS then
        local cmd = zb_rx.body.zcl_body.cmd.value
        local event = nil

        if cmd == OnOff.server.commands.On.ID then
            event = Switch.switch.on()
        elseif cmd == OnOff.server.commands.OnWithTimedOff.ID then
            device:send(cluster_base.read_attribute(device, data_types.ClusterId(OnOff.ID),
                data_types.AttributeId(OnOff.attributes.OnOff.ID)):to_endpoint(endpoint))
        elseif cmd == OnOff.server.commands.Off.ID then
            event = Switch.switch.off()
        end

        if event ~= nil then
            emit_switch_event_for_endpoint(device, endpoint, event)
        end
    end
end

local function switch_on_handler(driver, device, command)
    local parent = device:get_parent_device()
    if parent then
        local info = OUTPUT_BY_KEY[device.parent_assigned_child_key]
        if info then
            handle_output_command(parent, info.suffix, "on")
            return
        end
    end

    local num = command.component and command.component:match("output(%d)")
    if num then
        handle_output_command(device, num, "on")
        return
    end
    num = command.component:match("input(%d)")
    if num then
        log.debug("switch_on_handler", utils.stringify_table(command, "command", false))
        local component = device.profile.components[command.component]
        local value = device:get_latest_state(command.component, Switch.ID, Switch.switch.NAME)
        if value == "on" then
            device:emit_component_event(component,
                Switch.switch.on({ state_change = true, visibility = { displayed = false } }))
        elseif value == "off" then
            device:emit_component_event(component,
                Switch.switch.off({ state_change = true, visibility = { displayed = false } }))
        end
    end
end

local function switch_off_handler(driver, device, command)
    local parent = device:get_parent_device()
    if parent then
        local info = OUTPUT_BY_KEY[device.parent_assigned_child_key]
        if info then
            handle_output_command(parent, info.suffix, "off")
            return
        end
    end

    local num = command.component and command.component:match("output(%d)")
    if num then
        handle_output_command(device, num, "off")
        return
    end
    num = command.component:match("input(%d)")
    if num then
        log.debug("switch_on_handler", utils.stringify_table(command, "command", false))
        local component = device.profile.components[command.component]
        local value = device:get_latest_state(command.component, Switch.ID, Switch.switch.NAME)
        if value == "on" then
            device:emit_component_event(component,
                Switch.switch.on({ state_change = true, visibility = { displayed = false } }))
        elseif value == "off" then
            device:emit_component_event(component,
                Switch.switch.off({ state_change = true, visibility = { displayed = false } }))
        end
    end
end

local frient_bridge_handler = {
    NAME = "frient bridge handler",
    zigbee_handlers = {
        global = {
            [OnOff.ID] = {
                [zcl_global_commands.DEFAULT_RESPONSE_ID] = on_off_default_response_handler
            }
        },
        cluster = {},
        attr = {
            [BasicInput.ID] = {
                [BasicInput.attributes.PresentValue.ID] = present_value_attr_handler
            },
            [OnOff.ID] = {
                [OnOff.attributes.OnOff.ID] = on_off_attr_handler
            }
        },
        zdo = {}
    },
    capability_handlers = {
        [Switch.ID] = {
            [Switch.commands.on.NAME] = switch_on_handler,
            [Switch.commands.off.NAME] = switch_off_handler
        }
    },
    lifecycle_handlers = {
        init = init_handler,
        doConfigure = configure_handler,
        infoChanged = info_changed_handler
    },
    can_handle = function(opts, driver, device, ...)
        for _, fingerprint in ipairs(ZIGBEE_BRIDGE_FINGERPRINTS) do
            if device:get_manufacturer() == fingerprint.manufacturer and device:get_model() == fingerprint.model then
                local subdriver = require("frient-IO")
                return true, subdriver
            end
        end
    end
}

return frient_bridge_handler
