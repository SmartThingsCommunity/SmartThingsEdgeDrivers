local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"
local aqara_utils = require "aqara/aqara_utils"

local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput
local Basic = clusters.Basic

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(aqara_utils.FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function window_shade_level_cmd(driver, device, command)
  print("-------------- window_shade_level_cmd ")
  -- if aqara_utils.isInitializedStateField(device) ~= true then
  --   return
  -- end

  local level = command.args.shadeLevel
  if level > 100 then
    level = 100
  end
  level = utils.round(level)

  -- update ui to the new level
  aqara_utils.emit_shade_level_event(device, level)

  -- send
  aqara_utils.send_lift_percentage_cmd(device, command, level)
end

local function window_shade_open_cmd(driver, device, command)
  print("-------------- window_shade_open_cmd ")
  -- if aqara_utils.isInitializedStateField(device) ~= true then
  --   return
  -- end

  aqara_utils.send_lift_percentage_cmd(device, command, 100)
end

local function window_shade_close_cmd(driver, device, command)
  print("-------------- window_shade_close_cmd ")
  -- if aqara_utils.isInitializedStateField(device) ~= true then
  --   return
  -- end

  aqara_utils.send_lift_percentage_cmd(device, command, 0)
end

local function window_shade_pause_cmd(driver, device, command)
  print("-------------- window_shade_pause_cmd ")
  device:send_to_component(command.component, WindowCovering.server.commands.Stop(device))
end

-- local function current_position_attr_handler(driver, device, value, zb_rx)
--   print("-------------- current_position_attr_handler ")
--   aqara_utils.shade_position_changed(device, value)
-- end

-- local function shade_state_attr_handler(driver, device, value, zb_rx)
--   print("-------------- shade_state_attr_handler ")
--   aqara_utils.shade_state_changed(device, value)

-- -- update initialization ui
-- local state = value.value
-- if state == aqara_utils.SHADE_STATE_STOP then
--   local flag = getInitializationField(device)
--   if flag == INIT_STATE_CLOSE then
--     setInitializationField(device, INIT_STATE_REVERSE)
--     aqara_utils.send_open_cmd(device, { component = "main" })
--   elseif flag == INIT_STATE_OPEN then
--     setInitializationField(device, INIT_STATE_REVERSE)
--     aqara_utils.send_close_cmd(device, { component = "main" })
--   elseif flag == INIT_STATE_REVERSE then
--     setInitializationField(device, INIT_STATE_DONE)
--     aqara_utils.read_pref_attribute(device)
--   end
-- end
-- end

local aqara_window_treatment_handler = {
  NAME = "Aqara Window Treatment Handler",
  capability_handlers = {
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd
    },
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = window_shade_open_cmd,
      [capabilities.windowShade.commands.close.NAME] = window_shade_close_cmd,
      [capabilities.windowShade.commands.pause.NAME] = window_shade_pause_cmd
    }
  },
  -- zigbee_handlers = {
  -- attr = {
  -- [WindowCovering.ID] = {
  --   [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
  -- },
  -- [AnalogOutput.ID] = {
  --   [AnalogOutput.attributes.PresentValue.ID] = current_position_attr_handler
  -- },
  -- [Basic.ID] = {
  --   [aqara_utils.SHADE_STATE_ATTRIBUTE_ID] = shade_state_attr_handler
  -- }
  --   }
  -- },
  sub_drivers = {
    require("aqara.curtain"),
    require("aqara.roller-shade")
  },
  can_handle = is_aqara_products
}

return aqara_window_treatment_handler
