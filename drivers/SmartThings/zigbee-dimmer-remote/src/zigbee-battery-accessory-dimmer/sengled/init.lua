-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"

local STEP = 5
local DOUBLE_STEP = 10

local SENGLED_MFR_SPECIFIC_CLUSTER = 0xFC10
local SENGLED_MFR_SPECIFIC_COMMAND = 0x00


local generate_switch_level_event = function(device, value)
  device:emit_event(capabilities.switchLevel.level(value))
end

local generate_switch_onoff_event = function(device, value, state_change_value)
  local additional_fields = {
    state_change = state_change_value
  }
  if value == "on" then
    device:emit_event(capabilities.switch.switch.on(additional_fields))
  else
    device:emit_event(capabilities.switch.switch.off(additional_fields))
  end
end

local sengled_mfr_specific_command_handler = function(driver, device, zb_rx)
  local cmd = zb_rx.body.zcl_body.body_bytes:byte(1)
  local sub_cmd = string.byte(zb_rx.body.zcl_body.body_bytes:sub(3, 3))
  local current_level = device:get_latest_state("main", capabilities.switchLevel.ID, capabilities.switchLevel.level.NAME) or 0
  local level

  if cmd == 0x01 then
    generate_switch_onoff_event(device, "on", false)
  elseif cmd == 0x02 then
    if sub_cmd == 0x02 then
      level = math.min(current_level + DOUBLE_STEP, 100)
    elseif sub_cmd == 0x01 then
      level = math.min(current_level + STEP, 100)
    else
      level = current_level
    end

    generate_switch_onoff_event(device, "on", false)
    generate_switch_level_event(device, level)
  elseif cmd == 0x03 then
    if sub_cmd == 0x02 then
      level = math.max(current_level - DOUBLE_STEP, 0)
    elseif sub_cmd == 0x01 then
      level = math.max(current_level - STEP, 0)
    else
      level = current_level
    end

    if level == 0 then
      generate_switch_onoff_event(device, "off", false)
    else
      generate_switch_onoff_event(device, "on", false)
      generate_switch_level_event(device, level)
    end
  elseif cmd == 0x04 then
    generate_switch_onoff_event(device, "off", false)
  elseif cmd == 0x06 then
    generate_switch_onoff_event(device, "on", false)
  elseif cmd == 0x08 then
    generate_switch_onoff_event(device, "off", false)
  else
    return
  end
end


local sengled = {
  NAME = "sengled",
  zigbee_handlers = {
    cluster = {
      [SENGLED_MFR_SPECIFIC_CLUSTER] = {
        [SENGLED_MFR_SPECIFIC_COMMAND] = sengled_mfr_specific_command_handler
      }
    }
  },
  can_handle = require("zigbee-battery-accessory-dimmer.sengled.can_handle"),
}

return sengled
