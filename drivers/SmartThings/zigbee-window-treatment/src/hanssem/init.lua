--
-- Based on https://github.com/iquix/ST-Edge-Driver/blob/master/tuya-window-shade/src/init.lua
-- Copyright 2021-2022 Jaewon Park (iquix)
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--

local capabilities = require "st.capabilities"

local ZigbeeZcl = require "st.zigbee.zcl"
local Messages = require "st.zigbee.messages"
local data_types = require "st.zigbee.data_types"
local ZigbeeConstants = require "st.zigbee.constants"
local generic_body = require "st.zigbee.generic_body"
local window_preset_defaults = require "st.zigbee.defaults.windowShadePreset_defaults"

local TUYA_CLUSTER = 0xEF00
local DP_TYPE_VALUE = "\x02"
local DP_TYPE_ENUM = "\x04"

local SeqNum = 0

-------- Send Command Function for Tuya Zigbee device -------------
-- ZigbeeMessageTx:
--    Uint16: 0x0000
--    AddressHeader:
--        src_addr: 0x0000
--        src_endpoint: 0x01
--        dest_addr: 0xDEAD
--        dest_endpoint: 0x01
--        profile: 0x0104
--        cluster: OnOff
--    ZCLMessageBody:
--        ZCLHeader:
--            frame_ctrl: 0x00
--            seqno: 0x00
--            ZCLCommandId: 0x00
--        ReadAttribute:
--            AttributeId: 0x0000

local function SendCommand(device, DpId, Type, Value)
  local addrh = Messages.AddressHeader(
    ZigbeeConstants.HUB.ADDR, 					-- Source Address
    ZigbeeConstants.HUB.ENDPOINT,				-- Source Endpoint
    device:get_short_address(),			-- Destination Address
    device:get_endpoint(TUYA_CLUSTER),	-- Destination Address
    ZigbeeConstants.HA_PROFILE_ID,				-- Profile Id
    TUYA_CLUSTER						-- Cluster Id
  )
  local zclh = ZigbeeZcl.ZclHeader({cmd = data_types.ZCLCommandId(0x00)})
  zclh.frame_ctrl:set_cluster_specific()	-- sets this frame control field to be cluster specific
  -- Make a payload body
  SeqNum = (SeqNum + 1) % 65536
  local strSeqNum = string.pack(">I2", SeqNum)  -- Pack the Sequence number to 2 bytes unsigned integer type with big endian.
  local LenOfValue = string.pack(">I2",string.len(Value))  -- Pack length of Value to 2 bytes unsigned integer type wiht big endian.
  local PayloadBody = generic_body.GenericBody(strSeqNum .. DpId .. Type .. LenOfValue .. Value)
  local MsgBody = ZigbeeZcl.ZclMessageBody({zcl_header = zclh, zcl_body = PayloadBody})
  local TxMsg = Messages.ZigbeeMessageTx({address_header = addrh, body = MsgBody})
  device:send(TxMsg)
end

----------------- Functions to emit a capability event -------------------

local function getLatestLevel(device)
  local ret = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  if ret == nil then ret = 0 end
  return ret
end

local function emit_event_movement_status(device, target_level)
  local ret = false
  local current_level = getLatestLevel(device)
  if current_level ~= nil and current_level ~= target_level then
    if current_level > target_level then
      device:emit_event(capabilities.windowShade.windowShade.closing())
    elseif (current_level < target_level) then
      device:emit_event(capabilities.windowShade.windowShade.opening())
    end
    ret =  true
  end
  return ret
end

local function emit_event_final_position(device, feedback_level)
  local window_shade_val
  if type(feedback_level) ~= "number" then
    window_shade_val = "unknown"
    feedback_level = 50
  elseif feedback_level == 0 then
    window_shade_val = "closed"
  elseif feedback_level == 100 then
    window_shade_val = "open"
  elseif feedback_level > 0 and feedback_level < 100 then
    window_shade_val = "partially open"
  else
    window_shade_val = "unknown"
    feedback_level = 50
  end
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(feedback_level))
  device:emit_event(capabilities.windowShade.windowShade(window_shade_val))
end

-------------------- Capability Handlers -----------------------

local DP_ID_CONTROL = "\x01"
local DP_ID_SET_POSITION= "\x02"
local DP_ID_RESET_DIRECTION = "\x05"
local DP_VAL_OPEN = "\x00"
local DP_VAL_PAUSE = "\x01"
local DP_VAL_CLOSE = "\x02"
local DP_VAL_DIRECT = "\x00"
local DP_VAL_REVERSE = "\x01"

local function OpenHandler(driver, device, capability_command)
  local level = getLatestLevel(device)
  if level == 100 then
    device:emit_event(capabilities.windowShade.windowShade.open())
  else
    SendCommand(device, DP_ID_CONTROL, DP_TYPE_ENUM, DP_VAL_OPEN)
  end
end

local function CloseHandler(driver, device, capability_command)
  local level = getLatestLevel(device)
  if level == 0 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  else
    SendCommand(device, DP_ID_CONTROL, DP_TYPE_ENUM, DP_VAL_CLOSE)
  end
end

local function PauseHandler(driver, device, capability_command)
  local ShadeState = device:get_latest_state("main", capabilities.windowShade.ID, capabilities.windowShade.windowShade.NAME)
  device:emit_event(capabilities.windowShade.windowShade(ShadeState))
  SendCommand(device, DP_ID_CONTROL, DP_TYPE_ENUM, DP_VAL_PAUSE)
end

local function SetShadeLevelHandler(driver, device, capability_command)
  local level = getLatestLevel(device)
  if level == capability_command.args.shadeLevel then
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  end
  SendCommand(device, DP_ID_SET_POSITION, DP_TYPE_VALUE, string.pack(">I4", capability_command.args.shadeLevel))
end

local function PresetPositionHandler(driver, device, capability_command)
  local level = device.preferences.presetPosition or device:get_field(window_preset_defaults.PRESET_LEVEL_KEY) or window_preset_defaults.PRESET_LEVEL
  SetShadeLevelHandler(driver, device, {args = { shadeLevel = level }})
end

--------------------- Tuya Cluster Recieve Handlers --------------------

local function TuyaClusterRx(driver, device, zb_rx)
  local rx_body = zb_rx.body.zcl_body.body_bytes
  local dp_id = string.byte(rx_body:sub(3,3))
  local len = string.unpack(">I2", rx_body:sub(5,6))
  local value = string.unpack(">I"..len, rx_body:sub(7))
  if dp_id == 1 then -- 0x01: Control
    if value == 0 then 		-- 0 : open
      device:emit_event(capabilities.windowShade.windowShade.opening())
    elseif value == 2 then	-- 2 : close
      device:emit_event(capabilities.windowShade.windowShade.closing())
    end
  elseif dp_id == 2 then -- 0x02: Set Curtain Position in Percentage
    emit_event_movement_status(device, value)
  elseif dp_id == 3 then -- 0x03: Current Curtain Position
    emit_event_final_position(device, value)
  elseif dp_id == 5 then -- 0x05: Reset Direction
    device:set_field("DirectionChange",1)
  elseif dp_id == 7 then -- 0x07: Work state
    if value == 0 then		-- 0 : opening
      device:emit_event(capabilities.windowShade.windowShade.opening())
    elseif value == 1 then	-- 1 : Closing
      device:emit_event(capabilities.windowShade.windowShade.closing())
    end
    if device:get_field("DirectionChange") == 1 then
      device:set_field("DirectionChange",0)
      emit_event_final_position(device, getLatestLevel(device))
    end
  end
end

-------------------- Lifecycle Handlers -------------------

local function device_added(driver, device)
  device:emit_event(capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"}, {visibility = {displayed = false}}))
  if getLatestLevel(device) == 0 then
    emit_event_final_position(device, getLatestLevel(device))
    device.thread:call_with_delay(3, function(d)
      SetShadeLevelHandler(driver, device, {args = { shadeLevel = 50 }})
    end)
  end
end

local function device_info_changed(driver, device, event, args)
  if args.old_st_store.preferences.reverse ~= device.preferences.reverse then
    SetShadeLevelHandler(driver, device, {args = { shadeLevel = 50 }})
    device.thread:call_with_delay(2, function()
      SendCommand(device, DP_ID_RESET_DIRECTION, DP_TYPE_ENUM, device.preferences.reverse and DP_VAL_REVERSE or DP_VAL_DIRECT)
    end)
  end
end

---------------------- Driver Template ------------------------h

local hanssem_window_treatment = {
  NAME = "hanssem window treatment",
  supported_capabilities = {
    capabilities.windowShade,
    capabilities.windowShadePreset,
    capabilities.windowShadeLevel
  },
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = OpenHandler,
      [capabilities.windowShade.commands.close.NAME] = CloseHandler,
      [capabilities.windowShade.commands.pause.NAME] = PauseHandler
    },
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = PresetPositionHandler
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = SetShadeLevelHandler
    }
  },
--- See https://developer.smartthings.com/docs/edge-device-drivers/zigbee/zigbee_message_handlers.html for detailed
--- Also see https://developer.tuya.com/en/docs/iot/tuya-zigbee-universal-docking-access-standard?id=K9ik6zvofpzql for detailed
  zigbee_handlers = {
    cluster = {
      [TUYA_CLUSTER] = {
        [0x01] = TuyaClusterRx,	-- TY_DATA_RESPONSE
        [0x02] = TuyaClusterRx	-- TY_DATA_REPORT
      }
    }
  },
  lifecycle_handlers = {
    added = device_added,
    infoChanged = device_info_changed
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "TS0601"
  end
}

return hanssem_window_treatment