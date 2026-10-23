-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local switch_defaults = require "st.zigbee.defaults.switch_defaults"
local data_types = require "st.zigbee.data_types"
local device_management = require "st.zigbee.device_management"
local capabilities = require "st.capabilities"
local utils = require "st.utils"
local OnOff = clusters.OnOff
local ColorControl = clusters.ColorControl
local Level = clusters.Level
local log = require "log"

local PRI_CLU = 0xFCC0
local PRI_ATTR = 0x0009
local MFG_CODE = 0x115F
local OP_MODE_ATTR = 0x0509
local COMPONENT_MAIN = "main"
local COMPONENT_LAMP1 = "lamp1"
local COMPONENT_LAMP2 = "lamp2"
local COMPONENT_MODE = "mode"
local SUPPORTED_MODES = { "rgbw", "cct" }
local SUPPORTED_MODES_CODE = { 0x003, 0x0001 }
local COMPONENT_INFO_TABLE = {
  { name = COMPONENT_MAIN,  supportMode = SUPPORTED_MODES[1], endPoint = 1, numOfReceiver = 1 },
  { name = COMPONENT_MAIN,  supportMode = SUPPORTED_MODES[2], endPoint = 1, numOfReceiver = 2 },
  { name = COMPONENT_LAMP1, supportMode = SUPPORTED_MODES[2], endPoint = 1, numOfReceiver = 1 },
  { name = COMPONENT_LAMP2, supportMode = SUPPORTED_MODES[2], endPoint = 2, numOfReceiver = 1 }
}
local MODE_INFO_TABLE = {
  { name = SUPPORTED_MODES[1], code = SUPPORTED_MODES_CODE[1], profileName = "aqara-lightstrip-rgbw" },
  { name = SUPPORTED_MODES[2], code = SUPPORTED_MODES_CODE[2], profileName = "aqara-lightstrip-cct" }
}
local CONVERSION_CONSTANT = 1000000
local CURRENT_X = "current_x_value"               -- y value from xyY color space
local CURRENT_Y = "current_y_value"               -- x value from xyY color space
local Y_TRISTIMULUS_VALUE = "y_tristimulus_value" -- Y tristimulus value which is used to convert color xyY -> RGB -> HSV
local HUESAT_TIMER = "huesat_timer"
local TARGET_HUE = "target_hue"
local TARGET_SAT = "target_sat"
local MODE_CHANGE_STABILIZE_DELAY_SEC = 10

local function isCCTmode(device)
  local lastMode = device:get_latest_state(COMPONENT_MODE, capabilities.mode.ID, capabilities.mode.mode.NAME) or 0
  local ret = true
  if lastMode == SUPPORTED_MODES[1] then ret = false end
  return ret
end

local function store_xyY_values(device, x, y, Y)
  device:set_field(Y_TRISTIMULUS_VALUE, Y)
  device:set_field(CURRENT_X, x)
  device:set_field(CURRENT_Y, y)
end

local query_device = function(device)
  return function()
    device:send(ColorControl.attributes.CurrentX:read(device))
    device:send(ColorControl.attributes.CurrentY:read(device))
  end
end

local function switch_on_handler(driver, device, cmd)
  local curMode = SUPPORTED_MODES[1]
  local cmdComponent = cmd.component

  if isCCTmode(device) then curMode = SUPPORTED_MODES[2] end
  for _, i in ipairs(COMPONENT_INFO_TABLE) do
    if i.supportMode == curMode and i.name == cmdComponent then
      for j = 0, i.numOfReceiver - 1 do
        device:send(OnOff.commands.On(device):to_endpoint(i.endPoint + j))
      end
    end
  end
end

local function switch_off_handler(driver, device, cmd)
  local curMode = SUPPORTED_MODES[1]
  local cmdComponent = cmd.component

  if isCCTmode(device) then curMode = SUPPORTED_MODES[2] end
  for _, i in ipairs(COMPONENT_INFO_TABLE) do
    if i.supportMode == curMode and i.name == cmdComponent then
      for j = 0, i.numOfReceiver - 1 do
        device:send(OnOff.commands.Off(device):to_endpoint(i.endPoint + j))
      end
    end
  end
end

local function set_level_handler(driver, device, cmd)
  local curMode = SUPPORTED_MODES[1]
  local cmdComponent = cmd.component
  local level = math.floor(cmd.args.level / 100.0 * 254)

  if isCCTmode(device) then curMode = SUPPORTED_MODES[2] end
  for _, i in ipairs(COMPONENT_INFO_TABLE) do
    if i.supportMode == curMode and i.name == cmdComponent then
      for j = 0, i.numOfReceiver - 1 do
        device:send(Level.commands.MoveToLevelWithOnOff(device, level):to_endpoint(i.endPoint + j))
      end
    end
  end
end

local function set_color_temp_handler(driver, device, cmd)
  local curMode = SUPPORTED_MODES[1]
  local cmdComponent = cmd.component
  local temp_in_mired = utils.round(CONVERSION_CONSTANT / cmd.args.temperature)

  if isCCTmode(device) then curMode = SUPPORTED_MODES[2] end
  for _, i in ipairs(COMPONENT_INFO_TABLE) do
    if i.supportMode == curMode and i.name == cmdComponent then
      for j = 0, i.numOfReceiver - 1 do
        device:send(ColorControl.commands.MoveToColorTemperature(device, temp_in_mired):to_endpoint(i.endPoint + j))
      end
    end
  end
end

local function set_color_handler(driver, device, cmd)
  -- Cancel the hue/sat timer if it's running, since setColor includes both hue and saturation
  local huesat_timer = device:get_field(HUESAT_TIMER)
  if huesat_timer ~= nil then
    device.thread:cancel_timer(huesat_timer)
    device:set_field(HUESAT_TIMER, nil)
  end

  local hue = (cmd.args.color.hue ~= nil and cmd.args.color.hue > 99) and 99 or cmd.args.color.hue
  local sat = cmd.args.color.saturation

  local x, y, Y = utils.safe_hsv_to_xy(hue, sat)
  store_xyY_values(device, x, y, Y)
  switch_defaults.on(driver, device, cmd)

  device:send(ColorControl.commands.MoveToColor(device, x, y, 0x0000))

  device:set_field(TARGET_HUE, nil)
  device:set_field(TARGET_SAT, nil)
  device.thread:call_with_delay(2, query_device(device))
end

-- The device only accepts MoveToColor (XY); it does not respond to MoveToHue / MoveToSaturation.
-- setHue and setSaturation are therefore debounced: if both arrive within 200 ms (SmartThings
-- color pickers typically emit them together), they are combined into one setColor; otherwise the
-- missing value is filled from the latest known state and setColor is sent once the timer fires.
local huesat_timer_callback = function(driver, device, cmd)
  return function()
    device:set_field(HUESAT_TIMER, nil)
    local hue = device:get_field(TARGET_HUE)
    local sat = device:get_field(TARGET_SAT)
    hue = hue ~= nil and hue or device:get_latest_state(COMPONENT_MAIN, capabilities.colorControl.ID, capabilities.colorControl.hue.NAME)
    sat = sat ~= nil and sat or device:get_latest_state(COMPONENT_MAIN, capabilities.colorControl.ID, capabilities.colorControl.saturation.NAME)
    cmd.args = {
      color = {
        hue = hue,
        saturation = sat
      }
    }
    set_color_handler(driver, device, cmd)
  end
end

local function set_hue_sat_helper(driver, device, cmd, hue, sat)
  local huesat_timer = device:get_field(HUESAT_TIMER)
  if huesat_timer ~= nil then
    device.thread:cancel_timer(huesat_timer)
    device:set_field(HUESAT_TIMER, nil)
  end
  if hue ~= nil and sat ~= nil then
    cmd.args = {
      color = {
        hue = hue,
        saturation = sat
      }
    }
    set_color_handler(driver, device, cmd)
  else
    if hue ~= nil then
      device:set_field(TARGET_HUE, hue)
    elseif sat ~= nil then
      device:set_field(TARGET_SAT, sat)
    end
    device:set_field(HUESAT_TIMER, device.thread:call_with_delay(0.2, huesat_timer_callback(driver, device, cmd)))
  end
end

local function set_hue_handler(driver, device, cmd)
  set_hue_sat_helper(driver, device, cmd, cmd.args.hue, device:get_field(TARGET_SAT))
end

local function set_saturation_handler(driver, device, cmd)
  set_hue_sat_helper(driver, device, cmd, device:get_field(TARGET_HUE), cmd.args.saturation)
end

local function onoff_handler(driver, device, value, zb_rx)
  local curMode = SUPPORTED_MODES[1]
  local srcEndpoint = zb_rx.address_header.src_endpoint.value
  local evt = capabilities.switch.switch.off()
  if value.value then evt = capabilities.switch.switch.on() end

  if isCCTmode(device) then curMode = SUPPORTED_MODES[2] end
  for _, i in ipairs(COMPONENT_INFO_TABLE) do
    if i.supportMode == curMode and i.endPoint == srcEndpoint then
      device:emit_component_event(device.profile.components[i.name], evt)
    end
  end
end

local function current_level_handler(driver, device, value, zb_rx)
  local curMode = SUPPORTED_MODES[1]
  local srcEndpoint = zb_rx.address_header.src_endpoint.value
  local level = math.floor((value.value / 254.0 * 100) + 0.5)
  local evt = capabilities.switchLevel.level(level)

  if isCCTmode(device) then curMode = SUPPORTED_MODES[2] end
  for _, i in ipairs(COMPONENT_INFO_TABLE) do
    if i.supportMode == curMode and i.endPoint == srcEndpoint then
      device:emit_component_event(device.profile.components[i.name], evt)
    end
  end
end

local function current_color_temp_mireds_handler(driver, device, value, zb_rx)
  local srcEndpoint = zb_rx.address_header.src_endpoint.value
  local mired = utils.clamp_value(utils.round(CONVERSION_CONSTANT / value.value), 2700, 6500)
  local evt = capabilities.colorTemperature.colorTemperature(mired)

  local curMode = SUPPORTED_MODES[1]

  if isCCTmode(device) then curMode = SUPPORTED_MODES[2] end
  for _, i in ipairs(COMPONENT_INFO_TABLE) do
    if i.supportMode == curMode and i.endPoint == srcEndpoint then
      device:emit_component_event(device.profile.components[i.name], evt)
    end
  end
end

local function current_x_attr_handler(driver, device, value, zb_rx)
  local Y_tristimulus = device:get_field(Y_TRISTIMULUS_VALUE)
  local y = device:get_field(CURRENT_Y)
  local x = value.value

  if y then
    local hue, saturation = utils.safe_xy_to_hsv(x, y, Y_tristimulus)

    device:emit_component_event(device.profile.components[COMPONENT_MAIN], capabilities.colorControl.hue(hue))
    device:emit_component_event(device.profile.components[COMPONENT_MAIN], capabilities.colorControl.saturation(saturation))
  end

  device:set_field(CURRENT_X, x)
end

local function current_y_attr_handler(driver, device, value, zb_rx)
  local Y_tristimulus = device:get_field(Y_TRISTIMULUS_VALUE)
  local x = device:get_field(CURRENT_X)
  local y = value.value

  if x then
    local hue, saturation = utils.safe_xy_to_hsv(x, y, Y_tristimulus)

    device:emit_component_event(device.profile.components[COMPONENT_MAIN], capabilities.colorControl.hue(hue))
    device:emit_component_event(device.profile.components[COMPONENT_MAIN], capabilities.colorControl.saturation(saturation))
  end

  device:set_field(CURRENT_Y, y)
end

local function set_mode_handler(driver, device, command)
  local newMode = command.args.mode

  for _, i in ipairs(MODE_INFO_TABLE) do
    if newMode == i.name then
      device:send(cluster_base.write_manufacturer_specific_attribute(device,
        PRI_CLU, OP_MODE_ATTR, MFG_CODE, data_types.Uint32, i.code))
    end
  end
end

local function do_refresh(driver, device)
  if isCCTmode(device) then
    device:send(OnOff.attributes.OnOff:read(device):to_endpoint(0x01))
    device:send(Level.attributes.CurrentLevel:read(device):to_endpoint(0x01))
    device:send(ColorControl.attributes.ColorTemperatureMireds:read(device):to_endpoint(0x01))
    device:send(OnOff.attributes.OnOff:read(device):to_endpoint(0x02))
    device:send(Level.attributes.CurrentLevel:read(device):to_endpoint(0x02))
    device:send(ColorControl.attributes.ColorTemperatureMireds:read(device):to_endpoint(0x02))
  else
    device:send(OnOff.attributes.OnOff:read(device))
    device:send(Level.attributes.CurrentLevel:read(device))
    device:send(ColorControl.attributes.ColorTemperatureMireds:read(device))
    device:send(ColorControl.attributes.CurrentX:read(device))
    device:send(ColorControl.attributes.CurrentY:read(device))
  end
end

local function default_response_handler(driver, device, zb_rx)
  -- no action
end

local function device_added(driver, device)
  device:emit_component_event(device.profile.components[COMPONENT_MODE],
    capabilities.mode.supportedModes(SUPPORTED_MODES, { visibility = { displayed = false } }))
  -- Set private attribute
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRI_CLU, PRI_ATTR, MFG_CODE, data_types.Uint8, 1))
  device:send(cluster_base.read_manufacturer_specific_attribute(device,
    PRI_CLU, OP_MODE_ATTR, MFG_CODE))
end

local function set_restore_powerState(device)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRI_CLU, 0x0201, MFG_CODE, data_types.Boolean, device.preferences["stse.restorePowerState"]))
end

local function set_light_fadeInTimeState(device)
  local fadeInTime = device.preferences["stse.lightFadeInTimeInSec"] * 10
  device:send(clusters.Level.attributes.OnTransitionTime:write(device, fadeInTime):to_endpoint(0x01))
  if isCCTmode(device) then
    device:send(clusters.Level.attributes.OnTransitionTime:write(device, fadeInTime):to_endpoint(0x02))
  end
end

local function set_light_fadeOutTimeState(device)
  local fadeOutTime = device.preferences["stse.lightFadeOutTimeInSec"] * 10
  device:send(clusters.Level.attributes.OffTransitionTime:write(device, fadeOutTime):to_endpoint(0x01))
  if isCCTmode(device) then
    device:send(clusters.Level.attributes.OffTransitionTime:write(device, fadeOutTime):to_endpoint(0x02))
  end
end

local function device_info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    local mode = isCCTmode(device) and "cct" or "rgbw"
    log.info_with({ hub_logs = true }, string.format("profile changed to mode=%s (model=%s)", mode, device:get_model()))
    -- The device auto-reboots (~5-8s) when its operating mode (RGB/CCT) changes.
    -- Delay these writes so they aren't lost during the reboot window.
    device.thread:call_with_delay(MODE_CHANGE_STABILIZE_DELAY_SEC, function()
      set_restore_powerState(device)
      set_light_fadeInTimeState(device)
      set_light_fadeOutTimeState(device)
    end)
  end
  if device.preferences ~= nil then
    if device.preferences["stse.restorePowerState"] ~= nil and device.preferences["stse.restorePowerState"] ~= args.old_st_store.preferences["stse.restorePowerState"] then
      set_restore_powerState(device)
    end
    if device.preferences["stse.lightFadeInTimeInSec"] ~= nil and device.preferences["stse.lightFadeInTimeInSec"] ~= args.old_st_store.preferences["stse.lightFadeInTimeInSec"] then
      set_light_fadeInTimeState(device)
    end
    if device.preferences["stse.lightFadeOutTimeInSec"] ~= nil and device.preferences["stse.lightFadeOutTimeInSec"] ~= args.old_st_store.preferences["stse.lightFadeOutTimeInSec"] then
      set_light_fadeOutTimeState(device)
    end
  end
end

local function do_configure(driver, device)
  -- The device auto-reboots (~5-8s) when its operating mode (RGB/CCT) changes.
  -- Delay the refresh so we read state after the device has stabilized.
  device.thread:call_with_delay(MODE_CHANGE_STABILIZE_DELAY_SEC, function()
    do_refresh(driver, device)
  end)
  device:configure()
  device:send(device_management.build_bind_request(device, OnOff.ID, driver.environment_info.hub_zigbee_eui))
  do_refresh(driver, device)
end

local function change_plugin_mode(device, value)
  local modeCode = value
  for _, i in ipairs(MODE_INFO_TABLE) do
    if modeCode == i.code then
      device:emit_component_event(device.profile.components[COMPONENT_MODE], capabilities.mode.mode(i.name))
      device:try_update_metadata({ profile = i.profileName })
    end
  end
end

local function op_mode_handler(driver, device, value)
  change_plugin_mode(device, value.value)
end


local aqara_lightstrip_driver_handler = {
  NAME = "Aqara Lightstrip Driver Handler",
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = set_level_handler
    },
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temp_handler,
    },
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = set_color_handler,
      [capabilities.colorControl.commands.setHue.NAME] = set_hue_handler,
      [capabilities.colorControl.commands.setSaturation.NAME] = set_saturation_handler
    },
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = set_mode_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    global = {
      [OnOff.ID] = {
        [zcl_global_commands.DEFAULT_RESPONSE_ID] = default_response_handler
      }
    },
    attr = {
      [OnOff.ID] = {
        [OnOff.attributes.OnOff.ID] = onoff_handler
      },
      [Level.ID] = {
        [Level.attributes.CurrentLevel.ID] = current_level_handler
      },
      [ColorControl.ID] = {
        [ColorControl.attributes.ColorTemperatureMireds.ID] = current_color_temp_mireds_handler,
        [ColorControl.attributes.CurrentX.ID] = current_x_attr_handler,
        [ColorControl.attributes.CurrentY.ID] = current_y_attr_handler
      },
      [PRI_CLU] = {
        [OP_MODE_ATTR] = op_mode_handler
      }
    }
  },
  lifecycle_handlers = {
    added = device_added,
    infoChanged = device_info_changed,
    doConfigure = do_configure
  },
  can_handle = require("aqara-strip.can_handle")
}

return aqara_lightstrip_driver_handler
