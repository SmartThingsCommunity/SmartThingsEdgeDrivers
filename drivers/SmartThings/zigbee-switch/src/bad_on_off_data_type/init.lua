-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local function on_off_attr_handler(driver, device, value, zb_rx)
  local attr = capabilities.switch.switch
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, value.value == 0 and attr.off() or attr.on())
end

local bad_on_off_data_type = {
  NAME = "Bad OnOff Data Type",
  zigbee_handlers = {
    attr = {
      [zcl_clusters.OnOff.ID] = {
        [zcl_clusters.OnOff.attributes.OnOff.ID] = on_off_attr_handler
      }
    }
  },
  can_handle = require("bad_on_off_data_type.can_handle"),
}

return bad_on_off_data_type
