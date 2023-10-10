-- Copyright 2023 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--

local capabilities = require "st.capabilities"
local zb_zcl = require "st.zigbee.zcl"
local zb_messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"
local zb_data_types = require "st.zigbee.data_types"
local zb_generic_body = require "st.zigbee.generic_body"
local zb_window_preset_defaults = require "st.zigbee.defaults.windowShadePreset_defaults"

--local Log = require "log"

-------- Define Constants for TUYA Cluster -------------
local TUYA_CLUSTER = 0xEF00
local DP_ID_CURRENT_POS = "\x01"
local DP_ID_CONTROL = "\x02"
local DP_ID_SET_POSITION= "\x03"
local DP_ID_RESET_DIRECTION = "\x05"
local DP_ID_OPERATION_STATE = "\x07"
local DP_ID_AUTOCAL = "\x65"
local DP_ID_SPEED = "\x69"
local DP_TYPE_BOOL = "\x01"
local DP_TYPE_VALUE = "\x02"
local DP_TYPE_ENUM = "\x04"
local DP_VAL_FALSE = "\x00"
local DP_VAL_TRUE = "\x01"
local DP_VAL_OPEN = "\x00"
local DP_VAL_PAUSE = "\x01"
local DP_VAL_CLOSE = "\x02"
local DP_VAL_DIRECT = "\x00"
local DP_VAL_REVERSE = "\x01"

-------- Send Command Function for Tuya Zigbee device -------------
local SeqNum = 0
local function send_cmd_to_device(device, DpId, Type, Value)
  local addrh = zb_messages.AddressHeader(
    zb_const.HUB.ADDR, 					-- Source Address
    zb_const.HUB.ENDPOINT,				-- Source Endpoint
    device:get_short_address(),			-- Destination Address
    device:get_endpoint(TUYA_CLUSTER),	-- Destination Address
    zb_const.HA_PROFILE_ID,				-- Profile Id
    TUYA_CLUSTER						-- Cluster Id
  )
  local zclh = zb_zcl.ZclHeader({cmd = zb_data_types.ZCLCommandId(0x00)})
  zclh.frame_ctrl:set_cluster_specific()	-- sets this frame control field to be cluster specific
  -- Make a payload body
  SeqNum = SeqNum + 1
  if SeqNum > 65535 then SeqNum = 0 end
  local strSeqNum = string.pack(">I2", SeqNum)  -- Pack the Sequence number to 2 bytes unsigned integer type with big endian.
  local LenOfValue = string.pack(">I2",string.len(Value))  -- Pack length of Value to 2 bytes unsigned integer type wiht big endian.
  local PayloadBody = zb_generic_body.GenericBody(strSeqNum .. DpId .. Type .. LenOfValue .. Value)
  local MsgBody = zb_zcl.ZclMessageBody({zcl_header = zclh, zcl_body = PayloadBody})
  local TxMsg = zb_messages.ZigbeeMessageTx({address_header = addrh, body = MsgBody})
  device:send(TxMsg)
end

-------------------- Capability Handlers -----------------------

local function open_handler(driver, device, capability_command)
  local CurrentPosition = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  if CurrentPosition == 100 then
    device:emit_event(capabilities.windowShade.windowShade.open())
  else
    send_cmd_to_device(device, DP_ID_CONTROL, DP_TYPE_ENUM, DP_VAL_OPEN)
  end
end

local function close_handler(driver, device, capability_command)
  local CurrentPosition = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  if CurrentPosition == 0 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  else
    send_cmd_to_device(device, DP_ID_CONTROL, DP_TYPE_ENUM, DP_VAL_CLOSE)
  end
end

local function pause_handler(driver, device, capability_command)
  local ShadeState = device:get_latest_state("main", capabilities.windowShade.ID, capabilities.windowShade.windowShade.NAME)
  device:emit_event(capabilities.windowShade.windowShade(ShadeState))
  send_cmd_to_device(device, DP_ID_CONTROL, DP_TYPE_ENUM, DP_VAL_PAUSE)
end

local function set_shade_level_handler(driver, device, capability_command)
  local CurrentPostion = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  if CurrentPostion == capability_command.args.shadeLevel then
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(CurrentPostion))
  end
  send_cmd_to_device(device, DP_ID_SET_POSITION, DP_TYPE_VALUE, string.pack(">I4", capability_command.args.shadeLevel))
end

local function preset_position_handler(driver, device, capability_command)
  local level = device.preferences.presetPosition or device:get_field(zb_window_preset_defaults.PRESET_LEVEL_KEY) or zb_window_preset_defaults.PRESET_LEVEL
  set_shade_level_handler(driver, device, {args = { shadeLevel = level }})
end

--------------------- Tuya Cluster Recieve Handlers --------------------
local function update_final_position(device, feedback, dtype)
  local window_shade_state
  if(dtype == DP_TYPE_VALUE) then
    if feedback > 0 and feedback < 100 then
      window_shade_state = "partially open"
    elseif feedback == 0 then
      window_shade_state = "closed"
    elseif feedback == 100 then
      window_shade_state = "open"
    else
      window_shade_state = "unknown"
      feedback = 50
    end
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(feedback))
    device:emit_event(capabilities.windowShade.windowShade(window_shade_state))
  end
end

local function rx_open_close_control(device, SetValue, dtype)
  if SetValue == 0 then
    device:emit_event(capabilities.windowShade.windowShade.opening())
  elseif SetValue == 2 then
    device:emit_event(capabilities.windowShade.windowShade.closing())
  end
end

local function rx_set_target_position(device, TargetPosition, dtype)
  local CurrentPosition = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  if CurrentPosition ~= nil and CurrentPosition ~= TargetPosition then
    if CurrentPosition > TargetPosition then
      device:emit_event(capabilities.windowShade.windowShade.closing())
    elseif (CurrentPosition < TargetPosition) then
      device:emit_event(capabilities.windowShade.windowShade.opening())
    end
  end
end

local function rx_reset_direction(device, value, dtype)
  device:set_field("DirectionChange", 1)
end

local function rx_operation_state(device, value, dtype)
  if value == 0 then		-- 0 : opening
    device:emit_event(capabilities.windowShade.windowShade.opening())
  elseif value == 1 then	-- 1 : Closing
    device:emit_event(capabilities.windowShade.windowShade.closing())
  end
  if device:get_field("DirectionChange") == 1 then
    device:set_field("DirectionChange",0)
    local final_position = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
    update_final_position(device, final_position, DP_TYPE_VALUE)
  end
end

local function rx_auto_calibration(device, value, dtype)
  device.set_field("AutoCalibration", 1)
end

local ReceiveHandlerSet = { [DP_ID_CURRENT_POS] = update_final_position, [DP_ID_CONTROL] = rx_open_close_control,
  [DP_ID_SET_POSITION] = rx_set_target_position, [DP_ID_RESET_DIRECTION] = rx_reset_direction, [DP_ID_OPERATION_STATE] = rx_operation_state,
  [DP_ID_AUTOCAL] = rx_auto_calibration }

local function TY_cluster_rx_handler(driver, device, zb_rx)
  local rx_body = zb_rx.body.zcl_body.body_bytes
  local dp_id = string.sub(rx_body, 3, 3)
  local dtype = string.sub(rx_body, 4, 4)
  local len = string.unpack(">I2", string.sub(rx_body, 5, 6))
  local value = string.unpack(">I"..len, string.sub(rx_body, 7))
  if ReceiveHandlerSet[dp_id] then
    local rx_handler = ReceiveHandlerSet[dp_id]
    rx_handler(device, value, dtype)
  end
end

-------------------- Lifecycle Handlers -------------------

local function device_added(driver, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}))
  send_cmd_to_device(device, DP_ID_AUTOCAL, DP_TYPE_BOOL, DP_VAL_TRUE)
  local final_position = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  device:emit_event(capabilities.switchLevel.level(0))
  if final_position ~= 0 then
    device.thread:call_with_delay(10, function()
      set_shade_level_handler(driver, device, {args = { shadeLevel = 0 }})
    end)
  end
end

local function device_info_changed(driver, device, event, args)
  if args.old_st_store.preferences.reverse ~= device.preferences.reverse then
    set_shade_level_handler(driver, device, {args = { shadeLevel = 50 }})
    device.thread:call_with_delay(2, function()
      send_cmd_to_device(device, DP_ID_RESET_DIRECTION, DP_TYPE_ENUM, device.preferences.reverse and DP_VAL_REVERSE or DP_VAL_DIRECT)
    end)
  end
end

---------------------- Driver Template ------------------------h

local cheil_window_treatment = {
  NAME = "cheil autotech window treatment",
  supported_capabilities = {
    capabilities.windowShade,
    capabilities.windowShadePreset,
    capabilities.windowShadeLevel
  },
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = open_handler,
      [capabilities.windowShade.commands.close.NAME] = close_handler,
      [capabilities.windowShade.commands.pause.NAME] = pause_handler
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = preset_position_handler
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = set_shade_level_handler
    }
  },

  zigbee_handlers = {
    cluster = {
      [TUYA_CLUSTER] = {
        [0x01] = TY_cluster_rx_handler
      }
    }
  },
  lifecycle_handlers = {
    added = device_added,
    infoChanged = device_info_changed
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "jsMotor01"
  end
}

return cheil_window_treatment