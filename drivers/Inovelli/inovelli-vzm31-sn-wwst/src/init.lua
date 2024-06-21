-- Copyright 2024 Inovelli
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

local capabilities = require "st.capabilities"
local st_device = require "st.device"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.zcl.clusters"
local constants = require "st.zigbee.constants"
local bind_request = require "st.zigbee.zdo.bind_request"
local zdo_messages = require "st.zigbee.zdo"
local messages = require "st.zigbee.messages"
local SimpleMetering = clusters.SimpleMetering
local device_management = require "st.zigbee.device_management"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local log = require "log"

local Level = clusters.Level
local OnOff = clusters.OnOff

local Groups = clusters.Groups
local mgmt_bind_resp = require "st.zigbee.zdo.mgmt_bind_response"

local preferencesMap = require "preferences"

local LATEST_CLOCK_SET_TIMESTAMP = "latest_clock_set_timestamp"

local utils = require "st.utils"

local build_bind_request_64 = function(device, cluster, addr, src_endpoint, dst_endpoint)
  local addr_header = messages.AddressHeader(
    constants.HUB.ADDR, 
    constants.HUB.ENDPOINT, 
    device:get_short_address(), 
    device.fingerprinted_endpoint_id, 
    constants.ZDO_PROFILE_ID, 
    bind_request.BindRequest.ID)
    
  local bind_req = bind_request.BindRequest(
    device.zigbee_eui, 
    dst_endpoint, 
    cluster, 
    bind_request.ADDRESS_MODE_64_BIT, 
    addr,
    src_endpoint)

  return messages.ZigbeeMessageTx({
    address_header = addr_header,
    body = zdo_messages.ZdoMessageBody({zdo_body = bind_req})
  })
end

local send_bind_request_64 = function(device, cluster, addr, src_endpoint, dst_endpoint)
  return device:send( build_bind_request_64(device, cluster, addr, src_endpoint, dst_endpoint) )
end

local build_bind_request = function(device, cluster, group, dst_endpoint)
  local addr_header = messages.AddressHeader(
    constants.HUB.ADDR, 
    constants.HUB.ENDPOINT, 
    device:get_short_address(), 
    device.fingerprinted_endpoint_id, 
    constants.ZDO_PROFILE_ID, 
    bind_request.BindRequest.ID)
    
  local bind_req = bind_request.BindRequest(
    device.zigbee_eui, 
    dst_endpoint, 
    cluster, 
    bind_request.ADDRESS_MODE_16_BIT, 
    group)

  return messages.ZigbeeMessageTx({
    address_header = addr_header,
    body = zdo_messages.ZdoMessageBody({zdo_body = bind_req})
  })
end

local send_bind_request = function(device, cluster, group, dst_endpoint)
  return device:send( build_bind_request(device, cluster, group, dst_endpoint) )
end

local send_unbind_request = function(device, cluster, group, dst_endpoint)
  -- not tested
  local addr_header = messages.AddressHeader(
    constants.HUB.ADDR, 
    constants.HUB.ENDPOINT, 
    device:get_short_address(), 
    device.fingerprinted_endpoint_id, 
    constants.ZDO_PROFILE_ID, 
    0x0022)
    
  local bind_req = bind_request.BindRequest(
    device.zigbee_eui, 
    dst_endpoint, 
    cluster, 
    bind_request.ADDRESS_MODE_16_BIT, 
    group)

  return device:send( messages.ZigbeeMessageTx({
    address_header = addr_header,
    body = zdo_messages.ZdoMessageBody({zdo_body = bind_req})
  }) )
end

local send_unbind_request_64 = function(device, cluster, addr, src_endpoint, dst_endpoint)
  -- not tested
  local addr_header = messages.AddressHeader(
    constants.HUB.ADDR, 
    constants.HUB.ENDPOINT, 
    device:get_short_address(), 
    device.fingerprinted_endpoint_id, 
    constants.ZDO_PROFILE_ID, 
    0x0022)
    
  local bind_req = bind_request.BindRequest(
    device.zigbee_eui, 
    dst_endpoint, 
    cluster, 
    bind_request.ADDRESS_MODE_64_BIT, 
    addr,
    src_endpoint)

  return device:send( messages.ZigbeeMessageTx({
    address_header = addr_header,
    body = zdo_messages.ZdoMessageBody({zdo_body = bind_req})
  }) )
end

local function to_boolean(value)
  if value == 0 or value =="0" then
    return false
  else
    return true
  end
end

local function added(driver, device) 
  --device_init is ran when device is added?
end

local map_key_attribute_to_capability = {
  [0x00] = capabilities.button.button.pushed,
  [0x01] = capabilities.button.button.held,
  [0x02] = capabilities.button.button.down_hold,
  [0x03] = capabilities.button.button.pushed_2x,
  [0x04] = capabilities.button.button.pushed_3x,
  [0x05] = capabilities.button.button.pushed_4x,
  [0x06] = capabilities.button.button.pushed_5x,
}

local function button_to_component(buttonId)
  if buttonId > 0 then
    return string.format("button%d", buttonId)
  end
end

local function scene_handler(driver, device, zb_rx)
  local bytes = zb_rx.body.zcl_body.body_bytes
  local button_number = bytes:byte(1)
  local capability_attribute = map_key_attribute_to_capability[bytes:byte(2)]
  local additional_fields = {
    state_change = true
  }

  local event
  if capability_attribute ~= nil then
    event = capability_attribute(additional_fields)
  end

  local comp = device.profile.components[button_to_component(button_number)]
  if comp ~= nil then
    device:emit_component_event(comp, event)
  end
end

local function configuration_handler(driver, device, zb_rx)
  for i,v in ipairs(zb_rx.body.zcl_body.attr_records) do
    if (v.attr_id.value == 0x000D) then
    elseif (v.attr_id.value == 0x0015) then
      log.info("Parameter 21 is currently set to "..(v.data.value==true and "Neutral" or "Non-Neutral"))
      log.info("Parameter 21 is currently set to "..(v.data.value==true and "Neutral" or "Non-Neutral"))
    else
    end
  end
end

local version_handler = function(driver, device, value, zb_rx)
  log.info("Firmware Version: "..(value.value))
end

local function add_child(driver,parent,profile,child_type)
  local child_metadata = {
      type = "EDGE_CHILD",
      label = string.format("%s %s", parent.label, child_type:gsub("(%l)(%w*)", function(a,b) return string.upper(a)..b end)),
      profile = profile,
      parent_device_id = parent.id,
      parent_assigned_child_key = child_type,
      vendor_provided_label = string.format("%s %s", parent.label, child_type:gsub("(%l)(%w*)", function(a,b) return string.upper(a)..b end))
  }
  driver:try_create_device(child_metadata)
end

local function info_changed(driver, device, event, args)
  local time_diff = 0
  local last_clock_set_time = device:get_field(LATEST_CLOCK_SET_TIMESTAMP)
  if last_clock_set_time ~= nil then
      time_diff = os.difftime(os.time(), last_clock_set_time)
  end
  device:set_field(LATEST_CLOCK_SET_TIMESTAMP, os.time())

  if time_diff > 1 then
    local preferences = preferencesMap.get_device_parameters(device)

  if args.old_st_store.preferences["notificationChild"] ~= device.preferences.notificationChild and args.old_st_store.preferences["notificationChild"] and device.preferences.notificationChild == "Yes" then
      if not device:get_child_by_parent_assigned_key('notification') then
        log.info("Attempting to add child device")
          add_child(driver,device,'child-notification','notificaiton')
      end
    end

    for id, value in pairs(device.preferences) do
    if args.old_st_store.preferences[id] ~= value and preferences and preferences[id] then
      local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
      local new_new_parameter_value = preferencesMap.calculate_parameter(new_parameter_value, preferences[id].size, id)

      if(preferences[id].size == data_types.Boolean) then
        device:send(cluster_base.write_manufacturer_specific_attribute(device, 0xFC31, preferences[id].parameter_number, 0x122F, preferences[id].size, to_boolean(new_new_parameter_value)))
      else
        device:send(cluster_base.write_manufacturer_specific_attribute(device, 0xFC31, preferences[id].parameter_number, 0x122F, preferences[id].size, new_new_parameter_value))
      end
    end
  end

  local rebind = false

  if args.old_st_store.preferences["configall"] ~= device.preferences.configall and args.old_st_store.preferences["configall"] then
    rebind = true
    local preferences = preferencesMap.get_device_parameters(device)
    for id, value in pairs(device.preferences) do
      if preferences[id] then
        local new_parameter_value = preferencesMap.to_numeric_value(device.preferences[id])
        local new_new_parameter_value = preferencesMap.calculate_parameter(new_parameter_value, preferences[id].size, id)

  
        if(preferences[id].size == data_types.Boolean) then
          device:send(cluster_base.write_manufacturer_specific_attribute(device, 0xFC31, preferences[id].parameter_number, 0x122F, preferences[id].size, to_boolean(new_new_parameter_value)))
        else
          device:send(cluster_base.write_manufacturer_specific_attribute(device, 0xFC31, preferences[id].parameter_number, 0x122F, preferences[id].size, new_new_parameter_value))
        end
      end
    end
    
    end

  local bindings = {'binding1', 'binding2', 'binding3', 'binding4', 'binding5', 'binding6'}
  for i, bind in ipairs(bindings) do

  if (args.old_st_store.preferences[bind] ~= device.preferences[bind] and args.old_st_store.preferences[bind])  or rebind == true then
    if ((device.preferences[bind] ~= 0 and device.preferences[bind] ~= "" and device.preferences[bind] ~= nil)) then
      local devadd = {}
      local i = 0
      for word in device.preferences[bind]:gmatch("([^/]+)") do
        devadd[i] = word
        i = i + 1
      end
      local src_ep
      local dest_eui
      local dst_ep
      if(i == 2) then 
        --log.info("Old binding format")
        src_ep = 2
        dst_ep = devadd[1]
        dest_eui = devadd[0]
      elseif (i == 3) then 
        --log.info("New binding format")
        src_ep = devadd[0]
        dst_ep = devadd[2]
        dest_eui = devadd[1]
      else 
        log.info("Invalid binding format")
      end
      if (src_ep ~= NULL) then
        log.info("Attempting bind device ieee: "..dest_eui.." src_ep: "..src_ep.." dst_ep: "..dst_ep)
        device:set_field(bind,  dest_eui, {persist = true})
        local add_ieee = dest_eui:gsub('%x%x',function(c)return c.char(tonumber(c,16))end)
        local add_ep = dst_ep
        send_bind_request_64(device, OnOff.ID, data_types.IeeeAddress(add_ieee),tonumber(add_ep),tonumber(src_ep))
        send_bind_request_64(device, Level.ID, data_types.IeeeAddress(add_ieee),tonumber(add_ep),tonumber(src_ep))
      else
        log.info("Invalid configuration detected for binding")
      end
    elseif ((args.old_st_store.preferences[bind] ~= 0 and args.old_st_store.preferences[bind] ~= "" and args.old_st_store.preferences[bind] ~= nil)) then 
      local rmv = {}
      local i = 0
      for word in args.old_st_store.preferences[bind]:gmatch("([^/]+)") do
        rmv[i] = word
        i = i + 1
      end
      local src_ep
      local dest_eui
      local dst_ep
      if(i == 2) then 
        --log.info("Old binding format")
        src_ep = 2
        dst_ep = rmv[1]
        dest_eui = rmv[0]
      elseif (i == 3) then 
        --log.info("New binding format")
        src_ep = rmv[0]
        dst_ep = rmv[2]
        dest_eui = rmv[1]
      else 
        log.info("Invalid binding format")
      end
      log.info("Attempting unbind device ieee: "..dest_eui.." src_ep: "..src_ep.." dst_ep: "..dst_ep)
      local rmv_ieee = dest_eui:gsub('%x%x',function(c)return c.char(tonumber(c,16))end)
	    local rmv_ep = dst_ep
      send_unbind_request_64(device, OnOff.ID, data_types.IeeeAddress(rmv_ieee),tonumber(rmv_ep),tonumber(src_ep))
      send_unbind_request_64(device, Level.ID, data_types.IeeeAddress(rmv_ieee),tonumber(rmv_ep),tonumber(src_ep))
    end
  end
  end

  local groupbindings = {'groupbinding1', 'groupbinding2', 'groupbinding3'}
  for i, gbind in ipairs(groupbindings) do

    if (args.old_st_store.preferences[gbind] ~= device.preferences[gbind] and args.old_st_store.preferences[gbind]) or rebind == true  then
      if (device.preferences[gbind] ~= 0 and device.preferences[gbind] ~= "" and device.preferences[gbind] ~= nil) then
        device:set_field(gbind,  device.preferences[gbind], {persist = true})
        log.info("Adding group binding for group #: "..device.preferences[gbind])
        send_bind_request(device, OnOff.ID, tonumber(device.preferences[gbind]), 2)
        send_bind_request(device, Level.ID, tonumber(device.preferences[gbind]), 2)
        local query_configuration = function()
          device:send(Groups.server.commands.AddGroup(device, device.preferences[gbind], "Group"..tostring(device.preferences[gbind])))
          device:send(Groups.server.commands.GetGroupMembership(device, {}))
        end
        device.thread:call_with_delay(3,query_configuration)
      elseif (args.old_st_store.preferences[gbind] ~= 0 and args.old_st_store.preferences[gbind] ~= "" and args.old_st_store.preferences[gbind] ~= nil) then
        log.info("Removing group binding for group #: "..args.old_st_store.preferences[gbind])
        send_unbind_request(device, OnOff.ID, tonumber(args.old_st_store.preferences[gbind]), 2)
        send_unbind_request(device, Level.ID, tonumber(args.old_st_store.preferences[gbind]), 2)
        device:send(Groups.server.commands.RemoveGroup(device, args.old_st_store.preferences[gbind]))
        device:send(Groups.server.commands.GetGroupMembership(device, {}))
      end
    end
    end
    device:send(cluster_base.read_attribute(device, data_types.ClusterId(0x0000), 0x4000))
  else
    log.info("info_changed event duplicate detected. Not performing any actions.")  
  end

end

local function get_print_ready(t)
  local text_value = utils.get_print_safe_string(t)
  text_value = text_value:gsub("%\\x", "")
  return text_value
end

local function zdo_binding_table_handler(driver, device, zb_rx)
  local groups = ""
  local devicebinds = ""
  log.info(zb_rx.body.zdo_body.start_index.value)
  for _, binding_table in pairs(zb_rx.body.zdo_body.binding_table_entries) do
    log.info(get_print_ready(binding_table.dest_addr.value))
    if binding_table.dest_addr_mode.value == binding_table.DEST_ADDR_MODE_SHORT then
      -- send add hub to zigbee group command
      driver:add_hub_to_zigbee_group(binding_table.dest_addr.value)
      print("Adding to zigbee group: "..binding_table.dest_addr.value)
      groups = groups..binding_table.cluster_id.value.."("..binding_table.dest_addr.value.."),"
    else
      driver:add_hub_to_zigbee_group(0x0000)
      local binding_info = {}
      binding_info.cluster_id = binding_table.cluster_id.value
      binding_info.src_endpoint = binding_table.src_endpoint.value
      binding_info.dest_endpoint = binding_table.dest_endpoint.value
      binding_info.dest_addr = utils.get_print_safe_string(binding_table.dest_addr.value)
      binding_info.dest_addr = binding_info.dest_addr:gsub("%\\x", "")
      devicebinds = devicebinds..utils.stringify_table(binding_info)
    end
  end
  if devicebinds ~= "" then
    local binding_table_number = zb_rx.body.zdo_body.start_index.value
    log.info("Processing Binding Table Index #"..binding_table_number)
    log.info("DEVICE BINDS: "..devicebinds)
  end
end

local function Groups_handler(driver, device, value, zb_rx)

  local zb_message = value
  local group_list = zb_message.body.zcl_body.group_list_list
  --Print table group_lists with function utils.stringify_table(group_list)
  print("group_list >>>>>>",utils.stringify_table(group_list))
  
  local group_Names =""
  for i, value in pairs(group_list) do
    print("Message >>>>>>>>>>>",group_list[i].value)
    group_Names = group_Names..tostring(group_list[i].value).."-"
  end
  local text_Groups = "Groups Added: "..group_Names
  --local text_Groups = group_Names
  if text_Groups == "" then text_Groups = "All Deleted" end
  print (text_Groups)
  log.info(text_Groups)
end 

local zigbee_light_switch_driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.button,
  },
  capability_handlers = {
  },
  lifecycle_handlers = {
    added = added,
    infoChanged = info_changed
  },
  sub_drivers = {
    require("inovelli-vzm31-sn"),
    require("child-notification")
  },
  zigbee_handlers = {
    attr = {
      [0x0000] = {
        [0x4000] = version_handler
      },
    },
    global = {
      [0xFC31] = {
        [0x01] = configuration_handler
      }
    },
    cluster = {
      [0xFC31] = {
        [0x00] = scene_handler,
      },
      [clusters.Groups.ID] = {
        [clusters.Groups.commands.GetGroupMembershipResponse.ID] = Groups_handler
      }
    },
    zdo = {
      [mgmt_bind_resp.MGMT_BIND_RESPONSE] = zdo_binding_table_handler
    },
  }
}

defaults.register_for_default_handlers(zigbee_light_switch_driver_template, zigbee_light_switch_driver_template.supported_capabilities)
local zigbee_light_switch = ZigbeeDriver("zigbee_light_switch", zigbee_light_switch_driver_template)
zigbee_light_switch:run()