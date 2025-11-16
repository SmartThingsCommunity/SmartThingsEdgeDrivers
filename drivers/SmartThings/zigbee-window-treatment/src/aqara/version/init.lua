local clusters = require "st.zigbee.zcl.clusters"

local WindowCovering = clusters.WindowCovering

local APPLICATION_VERSION = "application_version"

local function shade_level_report_legacy_handler(driver, device, value, zb_rx)
  -- not implemented
end

local aqara_window_treatment_version_handler = {
  NAME = "Aqara Window Treatment Version Handler",
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = shade_level_report_legacy_handler
      }
    }
  },
  can_handle = function(opts, driver, device)
    local softwareVersion = device:get_field(APPLICATION_VERSION)
    return softwareVersion and softwareVersion ~= 34
  end
}

return aqara_window_treatment_version_handler
