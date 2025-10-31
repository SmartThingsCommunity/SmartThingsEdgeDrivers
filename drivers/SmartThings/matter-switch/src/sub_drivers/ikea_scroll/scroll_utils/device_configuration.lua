-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local button_cfg = require "switch_utils.device_configuration".ButtonCfg
local switch_fields = require "switch_utils.fields"
local scroll_fields = require "sub_drivers.ikea_scroll.scroll_utils.fields"

local IkeaScrollConfiguration = {}

function IkeaScrollConfiguration.build_button_component_map(device)
  local component_map = {
    group1 = scroll_fields.ENDPOINTS_PRESS[1],
    group2 = scroll_fields.ENDPOINTS_PRESS[2],
    group3 = scroll_fields.ENDPOINTS_PRESS[3],
  }
  device:set_field(switch_fields.COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
end

function IkeaScrollConfiguration.match_profile(driver, device)
  device:try_update_metadata({profile = "ikea-scroll"})
  IkeaScrollConfiguration.build_button_component_map(device)
  button_cfg.configure_buttons(device)
end

return IkeaScrollConfiguration
