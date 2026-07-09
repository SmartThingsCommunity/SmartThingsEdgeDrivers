-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"
local FINGERPRINTS = require "stateless_handler.fingerprints"
local ZigbeeZcl = require "st.zigbee.zcl"
local Messages = require "st.zigbee.messages"
local data_types = require "st.zigbee.data_types"
local ZigbeeConstants = require "st.zigbee.constants"
local generic_body = require "st.zigbee.generic_body"

-- Tuya cluster constants (for hanssem)
local TUYA_CLUSTER = 0xEF00
local DP_TYPE_VALUE = "\x02"
local DP_ID_SET_POSITION = "\x02"

-- Get next sequence number for Tuya commands (per-device storage to avoid counter conflicts)
local function get_next_tuya_seq_num(device)
  local seq = device:get_field("tuya_seq_num") or 0
  seq = (seq + 1) % 65536
  device:set_field("tuya_seq_num", seq)
  return seq
end

-- When the curtain is moving, LATEST_TARGET_LEVEL is used to store the latest target position value, 
-- which will be cleared when the curtain status is updated.
local LATEST_TARGET_LEVEL = "_latestTargetLevel"

-- Get fingerprint for a device
local function get_fingerprint(device)
  local manufacturer = device:get_manufacturer() or ""
  local model = device:get_model() or ""

  for _, config in ipairs(FINGERPRINTS) do
    -- Match manufacturer (case-insensitive)
    -- Support both single mfr string and mfrs array
    local mfr_match = false
    if config.mfrs then
      -- Check if manufacturer is in the mfrs array
      for _, mfr in ipairs(config.mfrs) do
        if string.lower(manufacturer) == string.lower(mfr) then
          mfr_match = true
          break
        end
      end
    elseif config.mfr then
      mfr_match = string.lower(manufacturer) == string.lower(config.mfr)
    end

    if mfr_match then
      -- If models list is empty, match any model from this manufacturer
      if #config.models == 0 then
        return config
      end
      -- Check if model matches any in the list (case-insensitive exact match)
      for _, model_pattern in ipairs(config.models) do
        if string.lower(model) == string.lower(model_pattern) then
          return config
        end
      end
    end
  end
  return nil -- No matching fingerprint, use default behavior
end

-- Step shade level handler for statelessWindowShadeLevelStep capability
local function step_shade_level_handler(driver, device, command)
  -- Get fingerprint-specific configuration
  local fingerprint = get_fingerprint(device)
  
  -- Support both args.stepSize (named) and args[1] (array) formats
  local step = command.args.stepSize or command.args[1]

  if not step or step == 0 then
    return
  end

  -- When LATEST_TARGET_LEVEL is empty, it means the curtain motor is not moving,
  -- and capabilities.windowShadeLevel.shadeLevel is used as the reference for position offset calculation;
  -- when LATEST_TARGET_LEVEL is not empty, it means the curtain motor is moving,
  -- and LATEST_TARGET_LEVEL is used as the reference for position offset calculation to obtain a more accurate position calculation.
  local latest_target_level = device:get_field(LATEST_TARGET_LEVEL)
  local current_level = latest_target_level or
    device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME) or 0

  -- Calculate command level (user's expected percentage)
  local command_level = utils.clamp_value(current_level + step, 0, 100)
  
  command_level = utils.round(command_level)

  -- Apply fingerprint-specific inversion if needed
  local device_target_level = command_level
  if fingerprint and fingerprint.invert_level then
    device_target_level = 100 - command_level
  end

  -- Set target_level for tracking (store UI value)
  device:set_field(LATEST_TARGET_LEVEL, command_level)

  -- Send command based on fingerprint configuration
  if fingerprint and fingerprint.use_level_cluster then
    -- Feibit/Axis uses Level cluster
    local level_value = math.floor(device_target_level / 100.0 * 254)
    device:send_to_component(command.component, clusters.Level.server.commands.MoveToLevelWithOnOff(device, level_value))
  elseif fingerprint and fingerprint.use_tuya_cluster then
    -- Hanssem uses Tuya custom cluster 0xEF00
    local strSeqNum = string.pack(">I2", get_next_tuya_seq_num(device))
    local value = string.pack(">I4", device_target_level)
    local LenOfValue = string.pack(">I2", string.len(value))
    local PayloadBody = generic_body.GenericBody(strSeqNum .. DP_ID_SET_POSITION .. DP_TYPE_VALUE .. LenOfValue .. value)
    local zclh = ZigbeeZcl.ZclHeader({cmd = data_types.ZCLCommandId(0x00)})
    zclh.frame_ctrl:set_cluster_specific()
    local addrh = Messages.AddressHeader(
      ZigbeeConstants.HUB.ADDR,
      ZigbeeConstants.HUB.ENDPOINT,
      device:get_short_address(),
      device:get_endpoint(TUYA_CLUSTER),
      ZigbeeConstants.HA_PROFILE_ID,
      TUYA_CLUSTER
    )
    local MsgBody = ZigbeeZcl.ZclMessageBody({zcl_header = zclh, zcl_body = PayloadBody})
    local TxMsg = Messages.ZigbeeMessageTx({address_header = addrh, body = MsgBody})
    device:send(TxMsg)
  else
    -- Standard: use WindowCovering.GoToLiftPercentage
    device:send_to_component(command.component, clusters.WindowCovering.server.commands.GoToLiftPercentage(device, device_target_level))
  end
end

local function shade_level_report_handler(driver, device, value, zb_rx)
  -- Since the curtain position status has been updated,
  -- the target value is no longer used as a reference for position offset calculation,
  -- so LATEST_TARGET_LEVEL needs to be set to nil.
  device:set_field(LATEST_TARGET_LEVEL, nil)
  -- Get fingerprint configuration
  local fingerprint = get_fingerprint(device)

  -- If no fingerprint configuration exists, call the main driver's default handler
  if fingerprint == nil then
    local windowShade_defaults = require "st.zigbee.defaults.windowShade_defaults"
    windowShade_defaults.default_current_lift_percentage_handler(driver, device, value, zb_rx)
  end
end

local stateless_handler = {
  NAME = "Zigbee Window Treatment Stateless Step Handlers",
  capability_handlers = {
    [capabilities.statelessWindowShadeLevelStep.ID] = {
      [capabilities.statelessWindowShadeLevelStep.commands.stepShadeLevel.NAME] = step_shade_level_handler,
    },
  },
  zigbee_handlers = {
    attr = {
      -- Window Covering cluster: handles standard curtain/blind devices 
      -- (e.g., Vimar: Window_Cov_v1.0/Window_Cov_Module_v1.0, SOMFY: Glydea Ultra Curtain/Sonesse series, 
      --        IKEA: KADRILJ/FYRTUR, Smartwings: WM25/L-Z, Insta GmbH: NEXENTRO Blinds Actuator, 
      --        Yookee: D10110, Rooms Beautiful: C001, Screen Innovations: WM25/L-Z)
      [clusters.WindowCovering.ID] = {
        [clusters.WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = shade_level_report_handler,
      },
      -- Level cluster: handles devices that use Level cluster for position control 
      -- (e.g., Feibit: FTB56-ZT218AK1.6/FTB56-ZT218AK1.8, Axis: Gear)
      [clusters.Level.ID] = {
        [clusters.Level.attributes.CurrentLevel.ID] = shade_level_report_handler,
      },
      -- Analog Output cluster: handles Aqara devices that report position via AnalogOutput 
      -- (e.g., lumi.curtain, lumi.curtain.v1, lumi.curtain.aq2, lumi.curtain.agl001)
      [clusters.AnalogOutput.ID] = {
        [clusters.AnalogOutput.attributes.PresentValue.ID] = shade_level_report_handler,
      },
    },
  },
  can_handle = require("stateless_handler.can_handle")
}

return stateless_handler
