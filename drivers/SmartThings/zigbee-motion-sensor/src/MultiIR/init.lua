-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"
local FrameCtrl = require "st.zigbee.zcl.frame_ctrl"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"

local sensitivityAdjustment = capabilities["stse.sensitivityAdjustment"]
local sensitivityAdjustmentCommandName = "setSensitivityAdjustment"
local IASZone = zcl_clusters.IASZone
local IASZone_PRIVATE_COMMAND_ID = 0xF4

local PREF_SENSITIVITY_VALUE_HIGH = 3
local PREF_SENSITIVITY_VALUE_MEDIUM = 2
local PREF_SENSITIVITY_VALUE_LOW = 1

local function send_iaszone_private_cmd(device, priv_cmd, data)
  local frame_ctrl = FrameCtrl(0x00)
  frame_ctrl:set_cluster_specific()

  local zclh = zcl_messages.ZclHeader({
    frame_ctrl = frame_ctrl,
    cmd = data_types.ZCLCommandId(priv_cmd)
  })

  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = data_types.Uint16(data)
  })

  local addr_header = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(IASZone.ID),
    zb_const.HA_PROFILE_ID,
    IASZone.ID
  )

  local zigbee_msg = messages.ZigbeeMessageTx({
    address_header = addr_header,
    body = message_body
  })

  device:send(zigbee_msg)
end

local function iaszone_attr_sen_handler(driver, device, value, zb_rx)
  if value.value == PREF_SENSITIVITY_VALUE_HIGH then
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.High())
  elseif value.value == PREF_SENSITIVITY_VALUE_MEDIUM then
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Medium())
  elseif value.value == PREF_SENSITIVITY_VALUE_LOW then
    device:emit_event(sensitivityAdjustment.sensitivityAdjustment.Low())
  end
end

local function send_sensitivity_adjustment_value(device, value)
  device:send(IASZone.attributes.CurrentZoneSensitivityLevel:write(device, value))
end

local function sensitivity_adjustment_capability_handler(driver, device, command)
  local sensitivity = command.args.sensitivity
  if sensitivity == 'High' then
    send_sensitivity_adjustment_value(device, PREF_SENSITIVITY_VALUE_HIGH)
  elseif sensitivity == 'Medium' then
    send_sensitivity_adjustment_value(device, PREF_SENSITIVITY_VALUE_MEDIUM)
  elseif sensitivity == 'Low' then
    send_sensitivity_adjustment_value(device, PREF_SENSITIVITY_VALUE_LOW)
  end
  device:send(IASZone.attributes.CurrentZoneSensitivityLevel:read(device))
end

local function added_handler(self, device)
  device:emit_event(capabilities.motionSensor.motion.inactive())
  device:emit_event(sensitivityAdjustment.sensitivityAdjustment.High())
  device:emit_event(capabilities.battery.battery(100))
  device:send(IASZone.attributes.CurrentZoneSensitivityLevel:read(device))
end

local function info_changed(driver, device, event, args)
  for name, value in pairs(device.preferences) do
    if (device.preferences[name] ~= nil and args.old_st_store.preferences[name] ~= device.preferences[name]) then
      if (name == "detectionfrequency") then
        local detectionfrequency = tonumber(device.preferences.detectionfrequency)
        send_iaszone_private_cmd(device, IASZone_PRIVATE_COMMAND_ID, detectionfrequency)
      end
    end
  end
end

local MultiIR_motion_handler = {
  NAME = "MultiIR motion handler",
  lifecycle_handlers = {
    added = added_handler,
    infoChanged = info_changed
  },
  capability_handlers = {
    [sensitivityAdjustment.ID] = {
      [sensitivityAdjustmentCommandName] = sensitivity_adjustment_capability_handler,
    }
  },
  zigbee_handlers = {
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.CurrentZoneSensitivityLevel.ID] = iaszone_attr_sen_handler
      }
    }
  },
  can_handle = require("MultiIR.can_handle")
}

return MultiIR_motion_handler
