-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local function ezex_can_handle(opts, driver, device, ...)
  local clusters = require "st.zigbee.zcl.clusters"
  if device:get_model() == "E253-KR0B0ZX-HA" and not device:supports_server_cluster(clusters.PowerConfiguration.ID) then
    return true, require("ezex")
  end
  return false
end

return ezex_can_handle
