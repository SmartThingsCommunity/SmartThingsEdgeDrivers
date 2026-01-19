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

-- Zigbee Spec Utils
local constants = require "st.zigbee.constants"
local messages = require "st.zigbee.messages"
local zdo_messages = require "st.zigbee.zdo"
local bind_request = require "st.zigbee.zdo.bind_request"
local unbind_request = require "frient-IO.unbind_request"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local Status = require "st.zigbee.generated.types.ZclStatus"

local clusters = require "st.zigbee.zcl.clusters"
local BasicInput = clusters.BasicInput
local OnOff = clusters.OnOff
-- Capabilities
local capabilities = require "st.capabilities"
local Switch = capabilities.switch
local CHILD_OUTPUT_PROFILE = "frient-io-output-switch"
local utils = require "st.utils"

local configurationMap = require "configurations"

local COMPONENTS = {
  INPUT_1 = "input1",
  INPUT_2 = "input2",
  INPUT_3 = "input3",
  INPUT_4 = "input4",
  OUTPUT_1 = "output1",
  OUTPUT_2 = "output2"
}

local ZIGBEE_ENDPOINTS = {
  INPUT_1 = 0x70,
  INPUT_2 = 0x71,
  INPUT_3 = 0x72,
  INPUT_4 = 0x73,
  OUTPUT_1 = 0x74,
  OUTPUT_2 = 0x75
}

local INPUT_CONFIGS = {
  {
    endpoint = ZIGBEE_ENDPOINTS.INPUT_1,
    reverse_pref = "reversePolarity1",
    binds = {
      { pref = "controlOutput11", endpoint = ZIGBEE_ENDPOINTS.OUTPUT_1 },
      { pref = "controlOutput21", endpoint = ZIGBEE_ENDPOINTS.OUTPUT_2 }
    }
  },
  {
    endpoint = ZIGBEE_ENDPOINTS.INPUT_2,
    reverse_pref = "reversePolarity2",
    binds = {
      { pref = "controlOutput12", endpoint = ZIGBEE_ENDPOINTS.OUTPUT_1 },
      { pref = "controlOutput22", endpoint = ZIGBEE_ENDPOINTS.OUTPUT_2 }
    }
  },
  {
    endpoint = ZIGBEE_ENDPOINTS.INPUT_3,
    reverse_pref = "reversePolarity3",
    binds = {
      { pref = "controlOutput13", endpoint = ZIGBEE_ENDPOINTS.OUTPUT_1 },
      { pref = "controlOutput23", endpoint = ZIGBEE_ENDPOINTS.OUTPUT_2 }
    }
  },
  {
    endpoint = ZIGBEE_ENDPOINTS.INPUT_4,
    reverse_pref = "reversePolarity4",
    binds = {
      { pref = "controlOutput14", endpoint = ZIGBEE_ENDPOINTS.OUTPUT_1 },
      { pref = "controlOutput24", endpoint = ZIGBEE_ENDPOINTS.OUTPUT_2 }
    }
  }
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

local function ensure_child_devices(driver, device)
  if device.parent_assigned_child_key ~= nil then
    return
  end

  for _, info in pairs(OUTPUT_INFO) do
    local child = device:get_child_by_parent_assigned_key(info.key)
    if child == nil then
      driver:try_create_device({
        type = "EDGE_CHILD",
        parent_device_id = device.id,
        parent_assigned_child_key = info.key,
        profile = CHILD_OUTPUT_PROFILE,
        label = string.format("%s %s", device.label, info.label_suffix),
        vendor_provided_label = info.label_suffix
      })
      child = device:get_child_by_parent_assigned_key(info.key)
    end
    if child then
      child:set_field("endpoint", info.endpoint, { persist = true })
    end
  end
end

local function sanitize_timing(value)
  local int = math.tointeger(value) or 0
  return utils.clamp_value(int, 0, 0xFFFF)
end

local function get_output_timing(device, suffix)
  local info = OUTPUT_INFO[suffix]
  if not info then return 0, 0 end
  local child = device:get_child_by_parent_assigned_key(info.key)
  local on_time = math.floor((sanitize_timing(device.preferences["configOnTime" .. suffix]))*10)
  local off_wait = math.floor((sanitize_timing(device.preferences["configOffWaitTime" .. suffix]))*10)
  if child then
    on_time = math.floor((sanitize_timing(child.preferences.configOnTime)) * 10)
    off_wait = math.floor((sanitize_timing(child.preferences.configOffWaitTime)) * 10)
  end
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
    device:send(OnOff.server.commands.Off(device):to_endpoint(endpoint))
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

local function register_native_switch_handler(device, endpoint)
  local field_key = string.format("frient_io_native_%02X", endpoint)
  local info = OUTPUT_BY_ENDPOINT[endpoint]
  if info ~= nil then
    local child = device:get_child_by_parent_assigned_key(info.key)
    if child and not child:get_field(field_key) then
      child:register_native_capability_attr_handler("switch", "switch")
      child:set_field(field_key, true)
    end
    return
  end

  if not device:get_field(field_key) then
    device:register_native_capability_attr_handler("switch", "switch")
    device:set_field(field_key, true)
  end
end

local function on_off_attr_handler(driver, device, value, zb_message)
  local endpoint = zb_message.address_header.src_endpoint.value
  register_native_switch_handler(device, endpoint)
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

local function apply_input_preference_changes(device, old_prefs, config)
  if old_prefs[config.reverse_pref] ~= device.preferences[config.reverse_pref] then
    write_basic_input_polarity_attr(device, config.endpoint, device.preferences[config.reverse_pref])
  end

  for _, bind_cfg in ipairs(config.binds) do
    if old_prefs[bind_cfg.pref] ~= device.preferences[bind_cfg.pref] then
      device:send(device.preferences[bind_cfg.pref]
        and build_bind_request(device, BasicInput.ID, config.endpoint, bind_cfg.endpoint)
        or build_unbind_request(device, BasicInput.ID, config.endpoint, bind_cfg.endpoint))
    end
  end
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
end

local function added_handler(self, device)
  ensure_child_devices(self, device)
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
  if device.parent_assigned_child_key ~= nil then
    return
  end

  ensure_child_devices(self, device)

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
  local default_old_prefs = {}
  for _, config in ipairs(INPUT_CONFIGS) do
    apply_input_preference_changes(device, default_old_prefs, config)
  end
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
    local old_prefs = (args.old_st_store and args.old_st_store.preferences) or {}
    for _, config in ipairs(INPUT_CONFIGS) do
      apply_input_preference_changes(device, old_prefs, config)
    end
  end
end

local function present_value_attr_handler(driver, device, value, zb_message)
  local ep_id = zb_message.address_header.src_endpoint
  register_native_switch_handler(device, ep_id.value)
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

local function make_switch_handler(command_name)
  return function(driver, device, command)
    local parent = device:get_parent_device()
    if parent then
      local info = OUTPUT_BY_KEY[device.parent_assigned_child_key]
      if info then
        handle_output_command(parent, info.suffix, command_name)
        return
      end
    end

    local num = command.component and command.component:match("output(%d)")
    if num then
      handle_output_command(device, num, command_name)
      return
    end
    num = command.component:match("input(%d)")
    if num then
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
      [Switch.commands.on.NAME] = make_switch_handler("on"),
      [Switch.commands.off.NAME] = make_switch_handler("off")
    }
  },
  lifecycle_handlers = {
    added = added_handler,
    init = init_handler,
    doConfigure = configure_handler,
    infoChanged = info_changed_handler
  },
  can_handle = require("frient-IO.can_handle"),
}

return frient_bridge_handler
