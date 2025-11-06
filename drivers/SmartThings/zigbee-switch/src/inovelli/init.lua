-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local utils = require "st.utils"
local st_device = require "st.device"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local inovelli_common = require "inovelli.common"

-- Load VZM32-only dependencies (handlers will check device type)
local OccupancySensing = clusters.OccupancySensing

local LATEST_CLOCK_SET_TIMESTAMP = "latest_clock_set_timestamp"

local PRIVATE_CLUSTER_ID = 0xFC31
local PRIVATE_CLUSTER_MMWAVE_ID = 0xFC32
local PRIVATE_CMD_NOTIF_ID = 0x01
local PRIVATE_CMD_ENERGY_RESET_ID = 0x02
local PRIVATE_CMD_SCENE_ID = 0x00
local PRIVATE_CMD_MMWAVE_ID = 0x00
local MFG_CODE = 0x122F

-- Base preferences shared by all models
local base_preference_map = {
  parameter258 = {parameter_number = 258, size = data_types.Boolean, cluster = PRIVATE_CLUSTER_ID},
  parameter52 = {parameter_number = 52, size = data_types.Boolean, cluster = PRIVATE_CLUSTER_ID},
  parameter1 = {parameter_number = 1, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
  parameter2 = {parameter_number = 2, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
  parameter3 = {parameter_number = 3, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
  parameter4 = {parameter_number = 4, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
  parameter15 = {parameter_number = 15, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
  parameter95 = {parameter_number = 95, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
  parameter96 = {parameter_number = 96, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
  parameter97 = {parameter_number = 97, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
  parameter98 = {parameter_number = 98, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
}

-- Model-specific overrides/additions
local model_preference_overrides = {
  ["VZM30-SN"] = {
    parameter11 = {parameter_number = 11, size = data_types.Boolean, cluster = PRIVATE_CLUSTER_ID},
    parameter22 = {parameter_number = 22, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
  },
  ["VZM31-SN"] = {
    parameter9 = {parameter_number = 9, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
    parameter10 = {parameter_number = 10, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
    parameter11 = {parameter_number = 11, size = data_types.Boolean, cluster = PRIVATE_CLUSTER_ID},
    parameter17 = {parameter_number = 17, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
    parameter22 = {parameter_number = 22, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
  },
  ["VZM32-SN"] = {
    parameter9 = {parameter_number = 9, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
    parameter10 = {parameter_number = 10, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
    parameter34 = {parameter_number = 34, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
    parameter101 = {parameter_number = 101, size = data_types.Int16, cluster = PRIVATE_CLUSTER_MMWAVE_ID},
    parameter102 = {parameter_number = 102, size = data_types.Int16, cluster = PRIVATE_CLUSTER_MMWAVE_ID},
    parameter103 = {parameter_number = 103, size = data_types.Int16, cluster = PRIVATE_CLUSTER_MMWAVE_ID},
    parameter104 = {parameter_number = 104, size = data_types.Int16, cluster = PRIVATE_CLUSTER_MMWAVE_ID},
    parameter105 = {parameter_number = 105, size = data_types.Int16, cluster = PRIVATE_CLUSTER_MMWAVE_ID},
    parameter106 = {parameter_number = 106, size = data_types.Int16, cluster = PRIVATE_CLUSTER_MMWAVE_ID},
    parameter110 = {parameter_number = 110, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_ID},
    parameter111 = {parameter_number = 111, size = data_types.Uint32, cluster = PRIVATE_CLUSTER_MMWAVE_ID},
    parameter112 = {parameter_number = 112, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_MMWAVE_ID},
    parameter113 = {parameter_number = 113, size = data_types.Uint8, cluster = PRIVATE_CLUSTER_MMWAVE_ID},
    parameter114 = {parameter_number = 114, size = data_types.Uint32, cluster = PRIVATE_CLUSTER_MMWAVE_ID},
    parameter115 = {parameter_number = 115, size = data_types.Uint32, cluster = PRIVATE_CLUSTER_ID},
  }
}

local function get_preference_map_for_device(device)
  -- shallow copy base
  local merged = {}
  for k, v in pairs(base_preference_map) do merged[k] = v end
  -- merge model-specific
  local model = device and device:get_model() or nil
  local override = model and model_preference_overrides[model] or nil
  if override then
    for k, v in pairs(override) do merged[k] = v end
  end
  return merged
end

local preferences_to_numeric_value = function(new_value)
  local numeric = tonumber(new_value)
  if numeric == nil then
    numeric = new_value and 1 or 0
  end
  return numeric
end

local preferences_calculate_parameter = function(new_value, type, number)
  if number == "parameter9" or number == "parameter10" or number == "parameter13" or number == "parameter14"  or number == "parameter15" or number == "parameter55" or number == "parameter56" then
    if new_value == 101 then
      return 255
    else
      return utils.round(new_value / 100 * 254)
    end
  else
    return new_value
  end
end

local function to_boolean(value)
  if value == 0 or value == "0" then
    return false
  else
    return true
  end
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
  local additional_fields = { state_change = true }
  local event = capability_attribute and capability_attribute(additional_fields) or nil
  local comp = device.profile.components[button_to_component(button_number)]
  if comp ~= nil and event ~= nil then
    device:emit_component_event(comp, event)
  end
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
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    local time_diff = 3
    local last_clock_set_time = device:get_field(LATEST_CLOCK_SET_TIMESTAMP)
    if last_clock_set_time ~= nil then time_diff = os.difftime(os.time(), last_clock_set_time) end
    device:set_field(LATEST_CLOCK_SET_TIMESTAMP, os.time(), {persist = true})
    if time_diff > 2 then
      local preferences = get_preference_map_for_device(device)
      if args.old_st_store.preferences["notificationChild"] ~= device.preferences.notificationChild and args.old_st_store.preferences["notificationChild"] == false and device.preferences.notificationChild == true then
        if not device:get_child_by_parent_assigned_key('notification') then
          add_child(driver,device,'rgbw-bulb-2700K-6500K','notification')
        end
      end
      for id, value in pairs(device.preferences) do
        if args.old_st_store.preferences[id] ~= value and preferences and preferences[id] then
            local new_parameter_value = preferences_calculate_parameter(preferences_to_numeric_value(device.preferences[id]), preferences[id].size, id)
            if(preferences[id].size == data_types.Boolean) then
              new_parameter_value = to_boolean(new_parameter_value)
            end
            if id == "parameter111" then
              device:send(cluster_base.build_manufacturer_specific_command(
                device,
                PRIVATE_CLUSTER_MMWAVE_ID,
                PRIVATE_CMD_MMWAVE_ID,
                MFG_CODE,
                utils.serialize_int(new_parameter_value,1,false,false)))
            else
              device:send(cluster_base.write_manufacturer_specific_attribute(device, preferences[id].cluster, preferences[id].parameter_number, MFG_CODE, preferences[id].size, new_parameter_value))
            end
        end
      end
    end
  end
end

local function device_added(driver, device)
    if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
      device:refresh()
    else
      device:emit_event(capabilities.colorControl.hue(1))
      device:emit_event(capabilities.colorControl.saturation(1))
      device:emit_event(capabilities.colorTemperature.colorTemperatureRange({ value = {minimum = 2700, maximum = 6500} }))
      device:emit_event(capabilities.colorTemperature.colorTemperature(6500))
      device:emit_event(capabilities.switchLevel.level(100))
      device:emit_event(capabilities.switch.switch("off"))
    end
end

local function device_configure(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    inovelli_common.base_device_configure(driver, device, PRIVATE_CLUSTER_ID, MFG_CODE)
  else
    device:configure()
  end
end

local function huePercentToValue(value)
  if value <= 2 then return 0
  elseif value >= 98 then return 255
  else return utils.round(value / 100 * 255) end
end

local function getNotificationValue(device, value)
  local notificationValue = 0
  local level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or 100
  local color = utils.round(device:get_latest_state("main", capabilities.colorControl.ID, capabilities.colorControl.hue.NAME) or 100)
  local effect = device:get_parent_device().preferences.notificationType or 1
  notificationValue = notificationValue + (effect*16777216)
  notificationValue = notificationValue + (huePercentToValue(value or color)*65536)
  notificationValue = notificationValue + (level*256)
  notificationValue = notificationValue + (255*1)
  return notificationValue
end

local function on_handler(driver, device, command)
    if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
      device:send(clusters.OnOff.server.commands.On(device))
    else
      device:emit_event(capabilities.switch.switch("on"))
      local dev = device:get_parent_device()
      local send_configuration = function()
        dev:send(cluster_base.build_manufacturer_specific_command(
              dev,
              PRIVATE_CLUSTER_ID,
              PRIVATE_CMD_NOTIF_ID,
              MFG_CODE,
              utils.serialize_int(getNotificationValue(device),4,false,false)))
      end
      device.thread:call_with_delay(1,send_configuration)
    end
  end

  local function off_handler(driver, device, command)
    if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
      device:send(clusters.OnOff.server.commands.Off(device))
    else
      device:emit_event(capabilities.switch.switch("off"))
      local dev = device:get_parent_device()
      local send_configuration = function()
        dev:send(cluster_base.build_manufacturer_specific_command(
              dev,
              PRIVATE_CLUSTER_ID,
              PRIVATE_CMD_NOTIF_ID,
              MFG_CODE,
              utils.serialize_int(0,4,false,false)))
      end
      device.thread:call_with_delay(1,send_configuration)
    end
  end

local function switch_level_handler(driver, device, command)
    if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
      device:send(clusters.Level.server.commands.MoveToLevelWithOnOff(device, math.floor(command.args.level/100.0 * 254), command.args.rate or 0xFFFF))
    else
      device:emit_event(capabilities.switchLevel.level(command.args.level))
      device:emit_event(capabilities.switch.switch(command.args.level ~= 0 and "on" or "off"))
      local dev = device:get_parent_device()
      local send_configuration = function()
        dev:send(cluster_base.build_manufacturer_specific_command(
              dev,
              PRIVATE_CLUSTER_ID,
              PRIVATE_CMD_NOTIF_ID,
              MFG_CODE,
              utils.serialize_int(getNotificationValue(device),4,false,false)))
      end
      device.thread:call_with_delay(1,send_configuration)
    end
  end

local function set_color_temperature(driver, device, command)
    device:emit_event(capabilities.colorControl.hue(100))
    device:emit_event(capabilities.colorTemperature.colorTemperature(command.args.temperature))
    device:emit_event(capabilities.switch.switch("on"))
    local dev = device:get_parent_device()
    local send_configuration = function()
      dev:send(cluster_base.build_manufacturer_specific_command(
            dev,
            PRIVATE_CLUSTER_ID,
            PRIVATE_CMD_NOTIF_ID,
            MFG_CODE,
            utils.serialize_int(getNotificationValue(device, 100),4,false,false)))
    end
    device.thread:call_with_delay(1,send_configuration)
  end

  local function set_color(driver, device, command)
    device:emit_event(capabilities.colorControl.hue(command.args.color.hue))
    device:emit_event(capabilities.colorControl.saturation(command.args.color.saturation))
    device:emit_event(capabilities.switch.switch("on"))
    local dev = device:get_parent_device()
    local send_configuration = function()
      dev:send(cluster_base.build_manufacturer_specific_command(
            dev,
            PRIVATE_CLUSTER_ID,
            PRIVATE_CMD_NOTIF_ID,
            MFG_CODE,
            utils.serialize_int(getNotificationValue(device),4,false,false)))
    end
    device.thread:call_with_delay(1,send_configuration)
  end

local function occupancy_attr_handler(driver, device, occupancy, zb_rx)
  device:emit_event(occupancy.value == 0x01 and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
end

local function handle_resetEnergyMeter(self, device)
  device:send(cluster_base.build_manufacturer_specific_command(device, PRIVATE_CLUSTER_ID, PRIVATE_CMD_ENERGY_RESET_ID, MFG_CODE, utils.serialize_int(0,1,false,false)))
  device:send(clusters.SimpleMetering.attributes.CurrentSummationDelivered:read(device))
  device:send(clusters.ElectricalMeasurement.attributes.ActivePower:read(device))
end

local inovelli = {
  NAME = "inovelli combined handler",
  lifecycle_handlers = {
    doConfigure = device_configure,
    infoChanged = info_changed,
    added = device_added,
  },
  zigbee_handlers = {
    attr = {
      [OccupancySensing.ID] = {
        [OccupancySensing.attributes.Occupancy.ID] = occupancy_attr_handler
      },
    },
    cluster = {
      [PRIVATE_CLUSTER_ID] = {
        [PRIVATE_CMD_SCENE_ID] = scene_handler,
      }
    }
  },
  sub_drivers = require("inovelli.sub_drivers"),
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = on_handler,
      [capabilities.switch.commands.off.NAME] = off_handler,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = switch_level_handler
    },
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = set_color
    },
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temperature
    },
    [capabilities.energyMeter.ID] = {
      [capabilities.energyMeter.commands.resetEnergyMeter.NAME] = handle_resetEnergyMeter,
    }
  },
  can_handle = require("inovelli.can_handle"),
}

return inovelli
