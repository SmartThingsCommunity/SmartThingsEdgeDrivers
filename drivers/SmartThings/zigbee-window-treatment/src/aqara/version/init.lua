local clusters = require "st.zigbee.zcl.clusters"
local aqara_utils = require "aqara/aqara_utils"

local WindowCovering = clusters.WindowCovering
local AnalogOutput = clusters.AnalogOutput

local APPLICATION_VERSION = "application_version"

local function shade_level_report_legacy_handler(driver, device, value, zb_rx)
  aqara_utils.emit_shade_level_event(device, value)
  aqara_utils.emit_shade_event(device, value)
end

local function shade_level_report_handler(driver, device, value, zb_rx)
  aqara_utils.emit_shade_level_event(device, value)
  aqara_utils.emit_shade_event(device, value)
end

local aqara_window_treatment_version_handler = {
  NAME = "Aqara Window Treatment Version Handler",
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = shade_level_report_legacy_handler
      },
      [AnalogOutput.ID] = {
        [AnalogOutput.attributes.PresentValue.ID] = shade_level_report_handler
      }
    }
  },
  can_handle = function(opts, driver, device)
    local softwareVersion = device:get_field(APPLICATION_VERSION)
    return softwareVersion and softwareVersion == 34
  end
}

return aqara_window_treatment_version_handler
