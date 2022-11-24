local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local utils = require "st.utils"
local aqara_utils = require "aqara/aqara_utils"

local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput

local function is_aqara_products(opts, driver, device)
  for _, fingerprint in ipairs(aqara_utils.FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function window_shade_level_cmd(driver, device, command)
  if aqara_utils.isInitializedStateField(device) ~= true then
    return
  end

  local level = command.args.shadeLevel
  if level > 100 then
    level = 100
  end
  level = utils.round(level)
  device:send_to_component(command.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))

  -- update ui to the new level
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
end

local function window_shade_open_cmd(driver, device, command)
  if aqara_utils.isInitializedStateField(device) ~= true then
    return
  end

  aqara_utils.send_open_cmd(device, command)
end

local function window_shade_close_cmd(driver, device, command)
  if aqara_utils.isInitializedStateField(device) ~= true then
    return
  end

  aqara_utils.send_close_cmd(device, command)
end

local function window_shade_pause_cmd(driver, device, command)
  device:send_to_component(command.component, WindowCovering.server.commands.Stop(device))
end

local function current_position_attr_handler(driver, device, value, zb_rx)
  aqara_utils.shade_position_changed(device, value)
end

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
  zigbee_handlers = {
    attr = {
      [AnalogOutput.ID] = {
        [AnalogOutput.attributes.PresentValue.ID] = current_position_attr_handler
      }
    }
  },
  sub_drivers = {
    require("aqara.curtain"),
    require("aqara.roller-shade")
  },
  can_handle = is_aqara_products
}

return aqara_window_treatment_handler
