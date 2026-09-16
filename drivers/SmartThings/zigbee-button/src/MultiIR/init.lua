-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local log = require "log"

local IASZone = zcl_clusters.IASZone
local PRIVATE_CMD_ID = 0xF1

local function ias_zone_private_cmd_handler(self, device, zb_rx)
  local cmd_data = zb_rx.body.zcl_body.body_bytes:byte(1)
  if cmd_data == 0 then
    device:emit_event(capabilities.button.button.pushed({state_change = true}))
  elseif cmd_data == 1 then
    device:emit_event(capabilities.button.button.double({state_change = true}))
  elseif cmd_data == 0x80 then
    device:emit_event(capabilities.button.button.held({state_change = true}))
  else
    log.info("ias_zone_private_cmd Unknown value",zb_rx.body.zcl_body.body_bytes:byte(1))
  end
end

local MultiIR_Emergency_Button = {
  NAME = "MultiIR Emergency Button",
  zigbee_handlers = {
    cluster = {
      [IASZone.ID] = {
        [PRIVATE_CMD_ID] = ias_zone_private_cmd_handler
      }
    }
  },
  can_handle = require("MultiIR.can_handle")
}

return MultiIR_Emergency_Button
