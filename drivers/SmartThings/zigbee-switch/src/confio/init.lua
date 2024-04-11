-- Copyright 2021 SmartThings
--- Confio Technologies Pvt Ltd 2024
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--     http://www.apache.org/licenses/LICENSE-2.0
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local OnOff = zcl_clusters.OnOff
local data_types = require "st.zigbee.data_types"
local utils = require "st.utils"
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local write_attribute = require "st.zigbee.zcl.global_commands.write_attribute"
local read_attribute = require "st.zigbee.zcl.global_commands.read_attribute"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local Status = require "st.zigbee.generated.types.ZclStatus"
local ep_ini = 1

------- Write attribute ----
local function write_attribute_function(device, cluster_id, attr_id, data_value, endpoint)
  local write_body = write_attribute.WriteAttribute({
   write_attribute.WriteAttribute.AttributeRecord(attr_id, data_types.ZigbeeDataType(data_value.ID), data_value.value)})
   local zclh = zcl_messages.ZclHeader({
     cmd = data_types.ZCLCommandId(write_attribute.WriteAttribute.ID)
   })
   local addrh = messages.AddressHeader(
       zb_const.HUB.ADDR,
       zb_const.HUB.ENDPOINT,
       device:get_short_address(),
       device:get_endpoint(cluster_id.value),
       zb_const.HA_PROFILE_ID,
       cluster_id.value
   )
   local message_body = zcl_messages.ZclMessageBody({
     zcl_header = zclh,
     zcl_body = write_body
   })
   device:send(messages.ZigbeeMessageTx({
     address_header = addrh,
     body = message_body
   }):to_endpoint (endpoint))
end

local function read_attribute_function(device, cluster_id, attr_id)
    local read_body = read_attribute.ReadAttribute( attr_id )
    local zclh = zcl_messages.ZclHeader({
      cmd = data_types.ZCLCommandId(read_attribute.ReadAttribute.ID)
    })
    local addrh = messages.AddressHeader(
        zb_const.HUB.ADDR,
        zb_const.HUB.ENDPOINT,
        device:get_short_address(),
        device:get_endpoint(cluster_id.value),
        zb_const.HA_PROFILE_ID,
        cluster_id.value
    )
    local message_body = zcl_messages.ZclMessageBody({
      zcl_header = zclh,
      zcl_body = read_body
    })
    return messages.ZigbeeMessageTx({
      address_header = addrh,
      body = message_body
  })
  end

--- Update preferences after infoChanged recived ---
local function do_preferences (driver, device)
  if device.network_type == "DEVICE_EDGE_CHILD" then return end ---- device (is Child device)
  for id, value in pairs(device.preferences) do
    local oldPreferenceValue = device:get_field(id)
    local newParameterValue = device.preferences[id]
    if oldPreferenceValue ~= newParameterValue then
      device:set_field(id, newParameterValue, {persist = true})
      ------ Change profile & Icon
      if id == "onOffReports" then
        -- Configure OnOff interval report
        local interval =  device.preferences.onOffReports
        if  device.preferences.onOffReports == nil then interval = 300 end
        local config ={
            cluster = zcl_clusters.OnOff.ID,
            attribute = zcl_clusters.OnOff.attributes.OnOff.ID,
            minimum_interval = 0,
            maximum_interval = interval,
            data_type = zcl_clusters.OnOff.attributes.OnOff.base_type
        }
        device:add_configured_attribute(config)
        device:add_monitored_attribute(config)
        device:configure()
      end
      if id == "restoreState" then
        for ids, value in pairs(device.profile.components) do
          local comp = device.profile.components[ids].id
          if comp == "main" then
            local endpoint = device:get_endpoint_for_component_id(comp)
            local value_send = tonumber(newParameterValue)
            local data_value = {value = value_send, ID = 0x30}
            local cluster_id = {value = 0x0006}
            local attr_id = 0x4003
            write_attribute_function(device, cluster_id, attr_id, data_value, endpoint)
            if newParameterValue == "255" then data_value = {value = 0x02, ID = 0x30} end
            attr_id = 0x8002
            write_attribute_function(device, cluster_id, attr_id, data_value, endpoint)
          end
        end
      end
      -- Call to Create child device
      if id == "switch2LevelChild" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
         profile_type = "child-switch-level"
         local label = "CONFIO Dimmer 2"
         if not device:get_child_by_parent_assigned_key("switch2") then
            local metadata = {
                type = "EDGE_CHILD",
                label = label,                              -- Initial Label for Child device
                profile = profile_type,                     -- Profile assigned to Child device created
                parent_device_id = device.id,               -- used to save parent device ID
                parent_assigned_child_key = "switch2",      -- used as libraries parent_assigned_child_key
                vendor_provided_label = profile_type        -- used to save profile_type to easy recovery with device.vendor_provided_label
            }
            driver:try_create_device(metadata)
         end
        end
      end
      ---print manufacturer, model and leng of the strings
      if device.manufacturer == nil then    ---- device.manufacturer == nil is NO Child device
        local manufacturer = device:get_manufacturer()
        local model = device:get_model()
        local manufacturer_len = string.len(manufacturer)
        local model_len = string.len(model)
        print("Device ID", device)
        print("Manufacturer >>>", manufacturer, "Manufacturer_Len >>>",manufacturer_len)
        print("Model >>>", model,"Model_len >>>",model_len)
        -- This will print in the log the total memory in use by Lua in Kbytes
        print("Memory >>>>>>>",collectgarbage("count"), " Kbytes")
        local firmware_full_version = device.data.firmwareFullVersion
        if firmware_full_version == nil then firmware_full_version = "Unknown" end
        print("<<<<< Firmware Version >>>>>",firmware_full_version)
      end
    end
  end
end

--- set All switch status
local function all_switches_status(driver,device)
   for id, value in pairs(device.preferences) do
     local total_on = 0
     local  total = 2
     local status_Text = ""
    if id == "changeProfileTwoSw" or
    (id == "switch2LevelChild") then
     if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
       total_on = total_on + 1
       status_Text = status_Text.."S1:On "
     end
     if device:get_latest_state("switch2", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
       total_on = total_on + 1
       status_Text = status_Text.."S2:On "
     end
    end
   end
 end

 --- return endpoint from component_id
local function component_to_endpoint(device, component_id)
  local endpoint_odd = false
  ep_ini = device.fingerprinted_endpoint_id
  if component_id == "main" then
    return ep_ini
  else
    local ep_num = component_id:match("switch(%d)")
    if ep_num == "2" then
      if endpoint_odd == true then
        return 3
      else
        return ep_ini + 1
      end
    end
  end
end

--- return Component_id from endpoint
local function endpoint_to_component(device, ep)
  local endpoint_odd = false
  ep_ini = device.fingerprinted_endpoint_id
  if ep == ep_ini then
    return "main"
  else
    if ep == ep_ini + 1 and endpoint_odd == false then
      return "switch2"
    elseif ep == ep_ini + 2 then
      if endpoint_odd == true then -- use endpoints odd only
        return "switch2"
      else
        return "switch3"
      end
    end
  end
end

--do_configure
local function do_configure(driver, device)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    -- Configure OnOff interval report
    local interval =  device.preferences.onOffReports
    if  device.preferences.onOffReports == nil then interval = 300 end
    local config ={
        cluster = zcl_clusters.OnOff.ID,
        attribute = zcl_clusters.OnOff.attributes.OnOff.ID,
        minimum_interval = 0,
        maximum_interval = interval,
        data_type = zcl_clusters.OnOff.attributes.OnOff.base_type
    }
    device:add_configured_attribute(config)
    device:add_monitored_attribute(config)
    device:configure()
  end
end

---device init ----
local function device_init (driver, device)
  print("device_network_id >>>",device.device_network_id)
  print("label >>>",device.label)
  print("parent_device_id >>>",device.parent_device_id)
  print("device.preferences.profileType >>>",device.preferences.profileType)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    device:set_component_to_endpoint_fn(component_to_endpoint)
    device:set_endpoint_to_component_fn(endpoint_to_component)
      ------ Selected profile & Icon
      for id, value in pairs(device.preferences) do
        if id == "changeProfileTwoSw" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "two-switch"})
          else
            device:try_update_metadata({profile = "two-switch-level"})
          end
        end
    end
    local attr_ids = {0x0004, 0x0000, 0x0001, 0x0005, 0x0007,0xFFFE}
    device:send(read_attribute_function (device, data_types.ClusterId(0x0000), attr_ids))
      -- Configure OnOff interval report
    local interval =  device.preferences.onOffReports
    if  device.preferences.onOffReports == nil then interval = 300 end
    local config ={
        cluster = zcl_clusters.OnOff.ID,
        attribute = zcl_clusters.OnOff.attributes.OnOff.ID,
        minimum_interval = 0,
        maximum_interval = interval,
        data_type = zcl_clusters.OnOff.attributes.OnOff.base_type
    }
    device:add_configured_attribute(config)
    device:add_monitored_attribute(config)
  end
end

------ do_configure device
local function driver_Switched(driver,device)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    print("<<< Read Basic clusters attributes >>>")
    local attr_ids = {0x0004, 0x0000, 0x0001, 0x0005, 0x0007,0xFFFE}
    device:send(read_attribute_function (device, data_types.ClusterId(0x0000), attr_ids))
      -- Configure OnOff interval report
      local interval =  device.preferences.onOffReports
      if  device.preferences.onOffReports == nil then interval = 300 end
      local config ={
        cluster = zcl_clusters.OnOff.ID,
        attribute = zcl_clusters.OnOff.attributes.OnOff.ID,
        minimum_interval = 0,
        maximum_interval = interval,
        data_type = zcl_clusters.OnOff.attributes.OnOff.base_type
      }
      device:add_configured_attribute(config)
      device:add_monitored_attribute(config)
      device.thread:call_with_delay(2, function(d)
        device:configure()
      end, "configure")
  end
end

--- Command on handler ----
local function on_handler(driver, device, command)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    device:send_to_component(command.component, zcl_clusters.Level.server.commands.MoveToLevelWithOnOff(device, math.floor(100.0/100.0 * 254), 0xFFFF))
  else
    local parent_device = device:get_parent_device()
    device:emit_event(capabilities.switch.switch.on())
    local component = device.parent_assigned_child_key
    if component~="main" then
parent_device:send_to_component(component, zcl_clusters.Level.server.commands.MoveToLevelWithOnOff(parent_device, math.floor(100.0/100.0 * 254), 0xFFFF))
    end
  end
end

--- Command off handler ----
local function off_handler(driver, device, command)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    device:send_to_component(command.component, zcl_clusters.Level.server.commands.MoveToLevelWithOnOff(device, math.floor(0/100.0 * 254), 0xFFFF))
  else
    local parent_device = device:get_parent_device()
    device:emit_event(capabilities.switch.switch.off())
    local component = device.parent_assigned_child_key
    if component~="main" then
parent_device:send_to_component(component, zcl_clusters.Level.server.commands.MoveToLevelWithOnOff(parent_device, math.floor(0/100.0 * 254), 0xFFFF))
    end
  end
end

--- read zigbee attribute OnOff messages ----
local function on_off_attr_handler(driver, device, value, zb_rx)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    local src_endpoint = zb_rx.address_header.src_endpoint.value
    local attr_value = value.value
    if attr_value == false or attr_value == 0 then
      device:emit_event_for_endpoint(src_endpoint, capabilities.switch.switch.off())
    elseif attr_value == true or attr_value == 1 then
      device:emit_event_for_endpoint(src_endpoint, capabilities.switch.switch.on())
    end
    -- emit event for child devices
    local component = device:get_component_id_for_endpoint(src_endpoint)
    local child_device = device:get_child_by_parent_assigned_key(component)
    if child_device ~= nil and component ~= "main" then
      if attr_value == false or attr_value == 0 then
        child_device:emit_event(capabilities.switch.switch.off())
      elseif attr_value == true or attr_value == 1 then
        child_device:emit_event(capabilities.switch.switch.on())
      end
    end
    --- Set all_switches_status capability status
    device.thread:call_with_delay(2, function(d)
      all_switches_status(driver, device)
    end)
  else
  end
end

--- do_added
local function do_added(driver, device)
  if device.network_type == "DEVICE_EDGE_CHILD" then  ---- device (is Child device)
    print("Adding EDGE:CHILD device...")
    local component = device.parent_assigned_child_key
    local parent_device = device:get_parent_device()
      if parent_device:get_latest_state(component, capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        device:emit_event(capabilities.switch.switch.on())
      else
        device:emit_event(capabilities.switch.switch.off())
      end
      if device.preferences.profileType == "level" then
        print("device.preferences.profileType >>>",device.preferences.profileType)
        local child_level = parent_device:get_latest_state(component, capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME)
        device:emit_event(capabilities.switchLevel.level(math.floor((child_level / 254.0 * 100) + 0.5)))
      end
  end
end

--- default_response_handler
local function default_response_handler(driver, device, zb_rx)
  local status = zb_rx.body.zcl_body.status.value
  local attr_value = false
  if status == Status.SUCCESS then
    local cmd = zb_rx.body.zcl_body.cmd.value
    local event = nil
    if cmd == zcl_clusters.OnOff.server.commands.On.ID then
      event = capabilities.switch.switch.on()
      attr_value = true
    elseif cmd == zcl_clusters.OnOff.server.commands.Off.ID then
      event = capabilities.switch.switch.off()
    end
    if event ~= nil then
      device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, event)
    end
  end

  -- emit event for child devices
  local component = device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value)
  local child_device = device:get_child_by_parent_assigned_key(component)
  if child_device ~= nil and component ~= "main" then
    if attr_value == false then
      child_device:emit_event(capabilities.switch.switch.off())
    else
      child_device:emit_event(capabilities.switch.switch.on())
    end
  end

  --- Set all_switches_status capability status
  device.thread:call_with_delay(2, function(d)
    all_switches_status(driver, device)
  end)
end
  --- switch_level_handler
  local function switch_level_handler(self,device,command)
    local on_Level = command.args.level
    if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
      device:send_to_component(command.component, zcl_clusters.Level.server.commands.MoveToLevelWithOnOff(device, math.floor(on_Level/100.0 * 254), 0xFFFF))
      -- emit event for child devices
      local component = command.component
      local child_device = device:get_child_by_parent_assigned_key(component)
      if child_device ~= nil and component ~= "main" then
        if child_device.preferences.profileType == "level" then
          child_device:emit_event(capabilities.switchLevel.level(on_Level))
        end
      end
    else
      device:emit_event(capabilities.switchLevel.level(on_Level))
      local component = device.parent_assigned_child_key
      local parent_device = device:get_parent_device()
      -- send comamd level to parent device
      if component ~= "main" then
        parent_device:send_to_component(component, zcl_clusters.Level.commands.MoveToLevelWithOnOff(parent_device, math.floor(on_Level/100.0 * 254), 0xFFFF))
      end
    end
  end
---- Level response emit event
local function level_attr_handler(driver, device, value, zb_rx)
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.switchLevel.level(math.floor((value.value / 254.0 * 100) + 0.5)))
    -- emit event for child devices
    local component = device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value)
    local child_device = device:get_child_by_parent_assigned_key(component)
    if child_device ~= nil and component ~= "main" then
      if child_device.preferences.profileType == "level" then
        child_device:emit_event(capabilities.switchLevel.level(math.floor((value.value / 254.0 * 100) + 0.5)))
      end
    end
  else
  end
end

---- Driver configure ---------
local zigbee_switch_driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
  --  capabilities.refresh
  },
  lifecycle_handlers = {
    init = device_init,
    driverSwitched = driver_Switched,
    infoChanged = do_preferences,
    doConfigure = do_configure,
    added = do_added,
  },
  zigbee_handlers = {
    global = {
     [zcl_clusters.OnOff.ID] = {
        [zcl_global_commands.DEFAULT_RESPONSE_ID] = default_response_handler
      }
    },
    attr = {
      [zcl_clusters.OnOff.ID] = {
         [zcl_clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler
     },
    [zcl_clusters.Level.ID] = {
        [zcl_clusters.Level.attributes.CurrentLevel.ID] = level_attr_handler
      }
   }
},
capability_handlers = {
  [capabilities.switch.ID] = {
    [capabilities.switch.commands.on.NAME] = on_handler,
    [capabilities.switch.commands.off.NAME] = off_handler
  },
  [capabilities.switchLevel.ID] = {
    [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_handler
  },
},
}

defaults.register_for_default_handlers(zigbee_switch_driver_template,zigbee_switch_driver_template.supported_capabilities)
local zigbee_switch = ZigbeeDriver("zigbee_switch", zigbee_switch_driver_template)
zigbee_switch:run()
