-- Copyright 2021 SmartThings
-- M. Colmenarejo 2022
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
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local device_management = require "st.zigbee.device_management"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local OnOff = zcl_clusters.OnOff
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"
local utils = require "st.utils"
local ElectricalMeasurement = zcl_clusters.ElectricalMeasurement
local SimpleMetering = zcl_clusters.SimpleMetering
local zcl_global_commands = require "st.zigbee.zcl.global_commands"

local write_attribute = require "st.zigbee.zcl.global_commands.write_attribute"
local read_attribute = require "st.zigbee.zcl.global_commands.read_attribute"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
--local Groups = zcl_clusters.Groups
local Status = require "st.zigbee.generated.types.ZclStatus"
local ep_ini = 1

local child_devices = require "child-devices"
local signal = require "signal-metrics"

-- Custom Capabilities Declaration
local switch_All_On_Off = capabilities["legendabsolute60149.switchAllOnOff1"]
local signal_Metrics = capabilities["legendabsolute60149.signalMetrics"]

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

  --tuyaBlackMagic() {return zigbee.readAttribute(0x0000, [0x0004, 0x000, 0x0001, 0x0005, 0x0007, 0xfffe], [:], delay=200)}
  local function read_attribute_function(device, cluster_id, attr_id)
    if device.preferences.logDebugPrint == true then
      print("<<<< attr_id >>>>",utils.stringify_table(attr_id))
    end
    --local read_body = read_attribute.ReadAttribute({ attr_id }) --- Original lua librares
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
    --}))
  })
  end

--- Update preferences after infoChanged recived ---
local function do_preferences (driver, device)
  if device.network_type == "DEVICE_EDGE_CHILD" then return end ---- device (is Child device)
  for id, value in pairs(device.preferences) do
    if device.preferences.logDebugPrint == true then
      print("device.preferences[infoChanged]=", device.preferences[id])
    end
    local oldPreferenceValue = device:get_field(id)
    local newParameterValue = device.preferences[id]
    if oldPreferenceValue ~= newParameterValue then
      device:set_field(id, newParameterValue, {persist = true})
      print("<< Preference changed name:",id,"oldPreferenceValue:",oldPreferenceValue, "newParameterValue: >>", newParameterValue)
 
      ------ Change profile & Icon
      if id == "changeProfileThreePlug" then
       if newParameterValue == "Single" then
        device:try_update_metadata({profile = "three-outlet"})
       else
        device:try_update_metadata({profile = "three-outlet-multi"})
       end
      elseif id == "changeProfileThreeSw" then
        if newParameterValue == "Single" then
         device:try_update_metadata({profile = "three-switch"})
        else
         device:try_update_metadata({profile = "three-switch-multi"})
        end
      elseif id == "changeProfileTwoPlug" then
        if newParameterValue == "Single" then
          device:try_update_metadata({profile = "two-outlet"})
        else
          device:try_update_metadata({profile = "two-outlet-multi"})
        end
      elseif id == "changeProfileTwoPlugPw" then
        if newParameterValue == "Single" then
          device:try_update_metadata({profile = "two-plug-power"})
        else
          device:try_update_metadata({profile = "two-plug-power-multi"})
        end
      elseif id == "changeProfileTwoSwPw" then
        if newParameterValue == "Single" then
          device:try_update_metadata({profile = "two-switch-power-energy"})
        else
          device:try_update_metadata({profile = "two-switch-power-energy-multi"})
        end
      elseif id == "changeProfileTwoSwPw1" then
        if newParameterValue == "Single" then
          device:try_update_metadata({profile = "two-switch-power-energy-1"})
        else
          device:try_update_metadata({profile = "two-switch-power-energy-multi-1"})
        end
      elseif id == "changeProfileTwoSw" then
        if newParameterValue == "Single" then
         device:try_update_metadata({profile = "two-switch"})
        else
         device:try_update_metadata({profile = "two-switch-multi"})
        end
      elseif id == "changeProfileFourSw" then
        if newParameterValue == "Single" then
         device:try_update_metadata({profile = "four-switch"})
        else
         device:try_update_metadata({profile = "four-switch-multi"})
        end
      elseif id == "changeProfileFourPlug" then
        if newParameterValue == "Single" then
          device:try_update_metadata({profile = "four-outlet"})
        else
          device:try_update_metadata({profile = "four-outlet-multi"})
        end
      elseif id == "changeProfileFiveSw" then
        if device.preferences[id] == "Single" then
         device:try_update_metadata({profile = "five-switch"})
        else
         device:try_update_metadata({profile = "five-switch-multi"})
        end      
      elseif id == "changeProfileFivePlug" then
        if newParameterValue == "Single" then
          device:try_update_metadata({profile = "five-outlet"})
        else
          device:try_update_metadata({profile = "five-outlet-multi"})
        end
      elseif id == "changeProfileSix" then
        if newParameterValue == "Switch" then
          device:try_update_metadata({profile = "six-switch"})
        else
          device:try_update_metadata({profile = "five-outlet"})
        end
      end

      --- Configure on-off cluster, attributte 0x8002 and 4003 to value restore state in preferences
      if id == "restoreState" then
        for ids, value in pairs(device.profile.components) do
          print("<<< Write restore state >>>")
          local comp = device.profile.components[ids].id
          if comp == "main" then
            local endpoint = device:get_endpoint_for_component_id(comp)
            if device.preferences.logDebugPrint == true then
              print("<<<< Componente, end_point >>>>",comp, endpoint)
            end
            local value_send = tonumber(newParameterValue)
            local data_value = {value = value_send, ID = 0x30}
            local cluster_id = {value = 0x0006}
            --write atribute for standard devices
            local attr_id = 0x4003
            write_attribute_function(device, cluster_id, attr_id, data_value, endpoint)

            --write atribute for Tuya devices (Restore previous state = 0x02)
            if newParameterValue == "255" then data_value = {value = 0x02, ID = 0x30} end
            attr_id = 0x8002
            write_attribute_function(device, cluster_id, attr_id, data_value, endpoint)
          end
        end
      end
      -- Call to Create child device
      local profile_type = "child-switch"
      if id == "switch1Child" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
         child_devices.create_new_device(driver, device, "main", profile_type)
        end       
      elseif id == "switch2Child" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
         child_devices.create_new_device(driver, device, "switch2", profile_type)
        end
      elseif id == "switch2LevelChild" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
          profile_type = "child-switch-level"
          child_devices.create_new_device(driver, device, "switch2", profile_type)
        end
      elseif id == "switch3Child" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
          child_devices.create_new_device(driver, device, "switch3", profile_type)
        end
      elseif id == "switch3LevelChild" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
          profile_type = "child-switch-level"
          child_devices.create_new_device(driver, device, "switch3", profile_type)
        end
      elseif id == "switch4Child" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
          child_devices.create_new_device(driver, device, "switch4", profile_type)
        end
      elseif id == "switch5Child" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
          child_devices.create_new_device(driver, device, "switch5",profile_type)
        end
      elseif id == "switch6Child" then
        if oldPreferenceValue ~= nil and newParameterValue == "Yes" then
          child_devices.create_new_device(driver, device, "switch6", profile_type)
        end
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

-- Emit event for all Switch On-Off and child device
local function emit_event_all_On_Off(driver, device, total_on, total,status_Text)
  local child_device = device:get_child_by_parent_assigned_key("main")
  if total_on == total then
    device:emit_event(switch_All_On_Off.switchAllOnOff("All On"))
    if child_device ~= nil then
      child_device:emit_event(capabilities.switch.switch.on())
    end
  elseif total_on == 0 then
    device:emit_event(switch_All_On_Off.switchAllOnOff("All Off"))
    if child_device ~= nil then
      child_device:emit_event(capabilities.switch.switch.off())
    end
  elseif total_on > 0 and total_on < total then
    device:emit_event(switch_All_On_Off.switchAllOnOff(status_Text))
    if child_device ~= nil then
      child_device:emit_event(capabilities.switch.switch.off())
    end
  end
end

--- set All switch status
local function all_switches_status(driver,device)

  print("all_switches_status >>>>>")
   for id, value in pairs(device.preferences) do
     local total_on = 0
     local  total = 2
     local status_Text = ""
     if id == "changeProfileSix" then
      total = 6
      if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S1:On "
      end
      if device:get_latest_state("switch2", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S2:On "
      end
      if device:get_latest_state("switch3", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S3:On "
      end
      if device:get_latest_state("switch4", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S4:On "
      end
      if device:get_latest_state("switch5", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S5:On "
      end
      if device:get_latest_state("switch6", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S6:On "
      end
      --print("Total_on >>>>>>", total_on,"Total >>>",total)

      emit_event_all_On_Off(driver, device, total_on, total,status_Text)

     elseif id == "changeProfileFivePlug" or id == "changeProfileFiveSw" then
      total = 5
      if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S1:On "
      end
      if device:get_latest_state("switch2", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S2:On "
      end
      if device:get_latest_state("switch3", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S3:On "
      end
      if device:get_latest_state("switch4", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S4:On "
      end
      if device:get_latest_state("switch5", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
        total_on = total_on + 1
        status_Text = status_Text.."S5:On "
      end
      --print("Total_on >>>>>>", total_on,"Total >>>",total)

      emit_event_all_On_Off(driver, device, total_on, total,status_Text)

    elseif id == "changeProfileFourPlug" or id == "changeProfileFourSw" then
       total = 4
       if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
         total_on = total_on + 1
         status_Text = status_Text.."S1:On "
       end
       if device:get_latest_state("switch2", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
         total_on = total_on + 1
         status_Text = status_Text.."S2:On "
       end
       if device:get_latest_state("switch3", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
         total_on = total_on + 1
         status_Text = status_Text.."S3:On "
       end
       if device:get_latest_state("switch4", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
         total_on = total_on + 1
         status_Text = status_Text.."S4:On "
       end
       --print("Total_on >>>>>>", total_on,"Total >>>",total)
       emit_event_all_On_Off(driver, device, total_on, total,status_Text)
 
    elseif id == "changeProfileThreePlug" or id == "changeProfileThreeSw" then
     total = 3
     if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
       total_on = total_on + 1
       status_Text = status_Text.."S1:On "
     end
     if device:get_latest_state("switch2", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
       total_on = total_on + 1
       status_Text = status_Text.."S2:On "
     end
     if device:get_latest_state("switch3", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
       total_on = total_on + 1
       status_Text = status_Text.."S3:On "
     end
     --print("Total_on >>>>>>", total_on,"Total >>>",total)
     emit_event_all_On_Off(driver, device, total_on, total,status_Text)
 
    elseif id == "changeProfileTwoPlug" or id == "changeProfileTwoSw" then
     if device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
       total_on = total_on + 1
       status_Text = status_Text.."S1:On "
     end
     if device:get_latest_state("switch2", capabilities.switch.ID, capabilities.switch.switch.NAME) == "on" then
       total_on = total_on + 1
       status_Text = status_Text.."S2:On "
     end
     --print("Total_on >>>>>>", total_on,"Total >>>",total)
     emit_event_all_On_Off(driver, device, total_on, total,status_Text)
 
    end
   end

 end

 --- return endpoint from component_id
local function component_to_endpoint(device, component_id)
  --print("<<<<< device.fingerprinted_endpoint_id >>>>>>",device.fingerprinted_endpoint_id)
  --------- in this models device.fingerprinted_endpoint_id is the last endpoint
  if device:get_model() == "FB56+ZSW1JKJ2.7" or 
    device:get_model()=="FB56+ZSW1IKJ2.5" or 
    device:get_model()=="FB56+ZSW1HKJ2.5" or
    device:get_model()=="FB56+ZSW1IKJ1.7" or
    device:get_model()=="FB56+ZSW1JK2.5" or
    device:get_model()=="FB56+ZSW1HKJ2.7"  then
      ep_ini = 16
  else
    ep_ini = device.fingerprinted_endpoint_id
  end

  if component_id == "main" then
    return ep_ini
  else
    local ep_num = component_id:match("switch(%d)")
    if ep_num == "2" then
      return ep_ini + 1
    elseif ep_num == "3" then
      return ep_ini + 2
    elseif ep_num == "4" then
      return ep_ini + 3
    elseif ep_num == "5" then
      if device:get_manufacturer() == "_TYZB01_vkwryfdr" then
        return ep_ini + 6
      else
        return ep_ini + 4
      end
    elseif ep_num == "6" then
      return ep_ini + 5
    end
  end
end

--- return Component_id from endpoint
local function endpoint_to_component(device, ep)

  --print("<<<<< device.fingerprinted_endpoint_id >>>>>>",device.fingerprinted_endpoint_id)
  ------------------ in this models device.fingerprinted_endpoint_id is the last endpoint
  if device:get_model() == "FB56+ZSW1JKJ2.7" or 
    device:get_model()=="FB56+ZSW1IKJ2.5" or 
    device:get_model()=="FB56+ZSW1HKJ2.5" or
    device:get_model()=="FB56+ZSW1IKJ1.7" or
    device:get_model()=="FB56+ZSW1JK2.5" or
    device:get_model()=="FB56+ZSW1HKJ2.7" then
      ep_ini = 16
  else
    ep_ini = device.fingerprinted_endpoint_id
  end

  if ep == ep_ini then
    return "main"
  else
    if ep == ep_ini + 1 then
      --return string.format("switch%d", ep)
      return "switch2"
    elseif ep == ep_ini + 2 then
      return "switch3"
    elseif ep == ep_ini + 3 then
      return "switch4"
    elseif ep == ep_ini + 4 then
      return "switch5"
    elseif ep == ep_ini + 6 and device:get_manufacturer() == "_TYZB01_vkwryfdr" then
      return "switch5"
    elseif ep == ep_ini + 5 then
      return "switch6"
    end 
  end
end

--do_configure
local function do_configure(driver, device)

  --print("Device table >>>>>>",utils.stringify_table(device))
  --print("Driver table >>>>>>",utils.stringify_table(driver))

  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    if device:get_manufacturer() ~= "_TZ3000_fvh3pjaz" 
    and device:get_manufacturer() ~= "_TZ3000_wyhuocal" then   -- devices tutn off after 2 minutes
    
      device:configure()

      -- Additional one time configuration
      if device:supports_capability(capabilities.energyMeter) or device:supports_capability(capabilities.powerMeter) then
        -- Divisor and multipler for EnergyMeter
        device:send(ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
        device:send(ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
        -- Divisor and multipler for PowerMeter
        device:send(SimpleMetering.attributes.Divisor:read(device))
        device:send(SimpleMetering.attributes.Multiplier:read(device))
      end

    else
      --device:send(device_management.build_bind_request(device, zcl_clusters.OnOff.ID, driver.environment_info.hub_zigbee_eui):to_endpoint (1))
      --device:send(zcl_clusters.OnOff.attributes.OnOff:configure_reporting(device, 0, 120):to_endpoint (1))
      --device:send(device_management.build_bind_request(device, zcl_clusters.OnOff.ID, driver.environment_info.hub_zigbee_eui):to_endpoint (2))
      --device:send(zcl_clusters.OnOff.attributes.OnOff:configure_reporting(device, 0, 120):to_endpoint (2))
    end
  else

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
        if device.preferences.logDebugPrint == true then
          print("<< Preference name: >>", id, "Preference value:", device.preferences[id])
        end
        if id == "changeProfileThreePlug" then
          if device.preferences[id] == "Single" then
          device:try_update_metadata({profile = "three-outlet"})
          else
          device:try_update_metadata({profile = "three-outlet-multi"})
          end
        elseif id == "changeProfileThreeSw" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "three-switch"})
          else
            device:try_update_metadata({profile = "three-switch-multi"})
          end
        elseif id == "changeProfileTwoPlug" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "two-outlet"})
          else
            device:try_update_metadata({profile = "two-outlet-multi"})
          end
        elseif id == "changeProfileTwoPlugPw" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "two-plug-power"})
          else
            device:try_update_metadata({profile = "two-plug-power-multi"})
          end
        elseif id == "changeProfileTwoSwPw" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "two-switch-power-energy"})
          else
            device:try_update_metadata({profile = "two-switch-power-energy-multi"})
          end
        elseif id == "changeProfileTwoSwPw1" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "two-switch-power-energy-1"})
          else
            device:try_update_metadata({profile = "two-switch-power-energy-multi-1"})
          end
        elseif id == "changeProfileTwoSw" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "two-switch"})
          else
            device:try_update_metadata({profile = "two-switch-multi"})
          end
        elseif id == "changeProfileFourSw" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "four-switch"})
          else
            device:try_update_metadata({profile = "four-switch-multi"})
          end
        elseif id == "changeProfileFourPlug" then
          if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "four-outlet"})
          else
            device:try_update_metadata({profile = "four-outlet-multi"})
          end
        elseif id == "changeProfileFiveSw" then
            if device.preferences[id] == "Single" then
            device:try_update_metadata({profile = "five-switch"})
            else
            device:try_update_metadata({profile = "five-switch-multi"})
            end
        elseif id == "changeProfileFivePlug" then
            if device.preferences[id] == "Single" then
              device:try_update_metadata({profile = "five-outlet"})
            else
              device:try_update_metadata({profile = "five-outlet-multi"})
            end
        elseif id == "changeProfileSix" then
          if device.preferences[id] == "Switch" then
            device:try_update_metadata({profile = "six-switch"})
          else
            device:try_update_metadata({profile = "six-outlet"})
          end
        end
    end

    --tuyaBlackMagic() {return zigbee.readAttribute(0x0000, [0x0004, 0x000, 0x0001, 0x0005, 0x0007, 0xfffe], [:], delay=200)}
    if device:get_model() ~= "FB56+ZSW1JKJ2.7" and 
      device:get_model()~="FB56+ZSW1IKJ2.5" and 
      device:get_model()~= "FB56+ZSW1HKJ2.5" and
      device:get_model()~="FB56+ZSW1IKJ1.7" and
      device:get_model()~="FB56+ZSW1JK2.5" and
      device:get_model()~= "FB56+ZSW1HKJ2.7" then
        print("<<< Read Basic clusters attributes >>>")
        local attr_ids = {0x0004, 0x0000, 0x0001, 0x0005, 0x0007,0xFFFE} 
       device:send(read_attribute_function (device, data_types.ClusterId(0x0000), attr_ids))
    end

    --- special cofigure for this device, read attribute on-off every 120 sec and not configure reports
    if device:get_manufacturer() == "_TZ3000_fvh3pjaz"
     or device:get_manufacturer() == "_TZ3000_wyhuocal" then   -- devices tutn off after 2 minutes

      --- Configure basic cluster, attributte 0x0099 to 0x1
      local data_value = {value = 0x01, ID = 0x20}
      local cluster_id = {value = 0x0000}
      local attr_id = 0x0099
      write_attribute_function(device, cluster_id, attr_id, data_value, 1)

      print("<<<<<<<<<<< read attribute 0xFF, 1 & 2 >>>>>>>>>>>>>")
      device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (0xFF))
      device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (1))
      device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (2))
      if device:get_manufacturer() == "_TZ3000_wyhuocal" then
        device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (3))
      end

      ---- Timers Cancel ------
        for timer in pairs(device.thread.timers) do
          print("<<<<< Cancelando timer >>>>>")
          device.thread:cancel_timer(timer)
      end
      --- Refresh atributte read schedule
      --print("<<<<<<<<<<<<< Timer read attribute >>>>>>>>>>>>>>>>")
      device.thread:call_on_schedule(
      120,
      function ()
        if device:get_manufacturer() == "_TZ3000_fvh3pjaz" 
        or device:get_manufacturer() == "_TZ3000_wyhuocal" then    -- devices tutn off after 2 minutes
          if device.preferences.logDebugPrint == true then
            print("<<< Timer read attribute >>>")
          end
          device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (1))
          device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (2))
          if device:get_manufacturer() == "_TZ3000_wyhuocal" then
            device:send(zcl_clusters.OnOff.attributes.OnOff:read(device):to_endpoint (3))
          end
        end
      end,
      'Refresh schedule')
    else

    end

    if device:get_latest_state("main", signal_Metrics.ID, signal_Metrics.signalMetrics.NAME) == nil then
      device:emit_event(signal_Metrics.signalMetrics({value = "Waiting Zigbee Message"}, {visibility = {displayed = false }}))
    end
    
  else
   
  end
end

------ do_configure device
local function driver_Switched(driver,device)

  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)

    device:refresh()
    if device:get_manufacturer() ~= "_TZ3000_fvh3pjaz"  -- devices tutn off after 2 minutes
      and device:get_manufacturer() ~= "_TZ3000_wyhuocal"
      and device:get_manufacturer() ~= nil then

      --tuyaBlackMagic() {return zigbee.readAttribute(0x0000, [0x0004, 0x000, 0x0001, 0x0005, 0x0007, 0xfffe], [:], delay=200)}
      if (device:get_model() ~= "FB56+ZSW1JKJ2.7" and 
        device:get_model()~="FB56+ZSW1IKJ2.5" and 
        device:get_model()~= "FB56+ZSW1HKJ2.5" and
        device:get_model()~="FB56+ZSW1IKJ1.7" and
        device:get_model()~="FB56+ZSW1JK2.5" and
        device:get_model()~= "FB56+ZSW1HKJ2.7") then
          print("<<< Read Basic clusters attributes >>>")
          local attr_ids = {0x0004, 0x0000, 0x0001, 0x0005, 0x0007,0xFFFE} 
          device:send(read_attribute_function (device, data_types.ClusterId(0x0000), attr_ids))
      end
      device:configure()
      -- Additional one time configuration
      if device:supports_capability(capabilities.energyMeter) or device:supports_capability(capabilities.powerMeter) then
        -- Divisor and multipler for EnergyMeter
        device:send(ElectricalMeasurement.attributes.ACPowerDivisor:read(device))
        device:send(ElectricalMeasurement.attributes.ACPowerMultiplier:read(device))
        -- Divisor and multipler for PowerMeter
        device:send(SimpleMetering.attributes.Divisor:read(device))
        device:send(SimpleMetering.attributes.Multiplier:read(device))
      end
    end

  else

  end
end 

---- switch_All_On_Off_handler
local function switch_All_On_Off_handler(driver, device, command)
  if device.preferences.logDebugPrint == true then
    print("command >>>>>", command)
    print("command.args.value >>>>>", command.args.value)
  end
  local ep_init = 1
  local state = ""
  local attr = capabilities.switch.switch
  if command ~= "All On" and  command ~= "All Off" then    ---- commad with this values is from child device command
    state = command.args.value
    device:emit_event(switch_All_On_Off.switchAllOnOff(state))
    ep_init = device:get_endpoint_for_component_id(command.component)
  else
    state = command
  end

  for id, value in pairs(device.preferences) do
   if id == "changeProfileSix" then
    if state == "All Off" then
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 1))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 2))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 3))
      if device:get_manufacturer() == "_TYZB01_vkwryfdr" then
        device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 6))
      else
        device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 4))
      end
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 5))
    else
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 1))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 2))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 3))
      if device:get_manufacturer() == "_TYZB01_vkwryfdr" then
        device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 6))
      else
        device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 4))
      end
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 5))
    end
  elseif id == "changeProfileFivePlug" or id == "changeProfileFiveSw" then
      if state == "All Off" then
        device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init))
        device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 1))
        device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 2))
        device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 3))
        if device:get_manufacturer() == "_TYZB01_vkwryfdr" then
          device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 6))
        else
          device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 4))
        end
      else
        device:send(OnOff.server.commands.On(device):to_endpoint(ep_init))
        device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 1))
        device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 2))
        device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 3))
        if device:get_manufacturer() == "_TYZB01_vkwryfdr" then
          device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 6))
        else
          device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 4))
        end
      end
   elseif id == "changeProfileFourPlug" or id == "changeProfileFourSw" then
    if state == "All Off" then
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 1))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 2))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 3))
    else
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 1))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 2))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 3))
    end
   elseif id == "changeProfileThreePlug" or id == "changeProfileThreeSw" then
    if state == "All Off" then
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 1))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 2))
    else
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 1))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 2))
    end
   elseif id == "changeProfileTwoPlug" or id == "changeProfileTwoSw" then
    if state == "All Off" then
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.Off(device):to_endpoint(ep_init + 1))
    else
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init))
      device:send(OnOff.server.commands.On(device):to_endpoint(ep_init + 1))
    end  
   end
  end
end

--- Command on handler ---- 
local function on_handler(driver, device, command)
  print("<<<< On command Handler >>>>")
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)

    device:send_to_component(command.component, zcl_clusters.OnOff.server.commands.On(device))
  else
    local parent_device = device:get_parent_device()
    if parent_device.preferences.logDebugPrint == true then
      print("<<< parent_device_id >>>", parent_device)
    end
    device:emit_event(capabilities.switch.switch.on())

    local component = device.parent_assigned_child_key
    if component == "main" then
      switch_All_On_Off_handler(driver, parent_device, "All On")
    else
      -- send comamd On to parent device
      parent_device:send_to_component(component, OnOff.server.commands.On(parent_device))
    end
  end
end

--- Command off handler ----
local function off_handler(driver, device, command)
  print("<<<< Off command Handler >>>>")
  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
    
    device:send_to_component(command.component, zcl_clusters.OnOff.server.commands.Off(device))
    
  else
    local parent_device = device:get_parent_device()
    if parent_device.preferences.logDebugPrint == true then
      print("<<< parent_device_id >>>", parent_device)
    end
    device:emit_event(capabilities.switch.switch.off())

    local component = device.parent_assigned_child_key
    if component == "main" then
      switch_All_On_Off_handler(driver, parent_device, "All Off")
    else
      -- send comamd Off to parent device
      parent_device:send_to_component(component, OnOff.server.commands.Off(parent_device))
    end
  end
end

--- read zigbee attribute OnOff messages ----
local function on_off_attr_handler(driver, device, value, zb_rx)
    print ("function: on_off_attr_handler")

  if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)

    -- emit signal metrics
    signal.metrics(device, zb_rx)

    local src_endpoint = zb_rx.address_header.src_endpoint.value
    local attr_value = value.value
    if device.preferences.logDebugPrint == true then
      print ("src_endpoint =", zb_rx.address_header.src_endpoint.value , "value =", value.value)
    end

    --- Emit event from zigbee message recived
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

    if component == "main" then
      if parent_device:get_latest_state(component, switch_All_On_Off.ID, switch_All_On_Off.switchAllOnOff.NAME) == "All On" then
        device:emit_event(capabilities.switch.switch.on())
      else
        device:emit_event(capabilities.switch.switch.off())
      end
    else
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
end

--- default_response_handler
local function default_response_handler(driver, device, zb_rx)
  print("<<<<<< default_response_handler >>>>>>")

  -- emit signal metrics
  signal.metrics(device, zb_rx)

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
    print("handler_Level >>>>>>>>>>>>>>",command.args.level)
    local on_Level = command.args.level

    if device.network_type ~= "DEVICE_EDGE_CHILD" then  ---- device (is NO Child device)
      device:send_to_component(command.component,zcl_clusters.Level.commands.MoveToLevelWithOnOff(device, math.floor(on_Level/100.0 * 254), 0xFFFF))
    
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
  print("<<<< emit Level >>>>")

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
local zigbee_outlet_driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.refresh
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
  [switch_All_On_Off.ID] = {
    [switch_All_On_Off.commands.setSwitchAllOnOff.NAME] = switch_All_On_Off_handler,
  },
  [capabilities.switchLevel.ID] = {
    [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_handler
  },
},
--health_check = false
}

defaults.register_for_default_handlers(zigbee_outlet_driver_template, zigbee_outlet_driver_template.supported_capabilities)
local zigbee_outlet = ZigbeeDriver("Zigbee_Multi_Switch", zigbee_outlet_driver_template)
zigbee_outlet:run()