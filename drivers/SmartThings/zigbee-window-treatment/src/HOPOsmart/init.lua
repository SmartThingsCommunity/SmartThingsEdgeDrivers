-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local custom_clusters = require "HOPOsmart/custom_clusters"
local cluster_base = require "st.zigbee.cluster_base"

local ZIGBEE_WINDOW_SHADE_FINGERPRINTS = {
  { mfr = "HOPOsmart", model = "A2230011" }
}


local is_zigbee_window_shade = function(opts, driver, device)
  for _, fingerprint in ipairs(ZIGBEE_WINDOW_SHADE_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function send_read_attr_request(device, cluster, attr)
  device:send(
    cluster_base.read_manufacturer_specific_attribute(
      device,
      cluster.id,
      attr.id,
      cluster.mfg_specific_code
    )
  )
end

local function state_value_attr_handler(driver, device, value, zb_rx)
  if value.value == 0 then
    device:emit_event(capabilities.windowShade.windowShade.open())
  elseif value.value == 1 then
    device:emit_event(capabilities.windowShade.windowShade.opening())
  elseif value.value == 2 then
    device:emit_event(capabilities.windowShade.windowShade.closed())
  elseif value.value == 3 then
    device:emit_event(capabilities.windowShade.windowShade.closing())
  elseif value.value == 4 then
    device:emit_event(capabilities.windowShade.windowShade.partially_open())
  end
end

local function do_refresh(driver, device)
  send_read_attr_request(device, custom_clusters.motor, custom_clusters.motor.attributes.state_value)
end

local function added_handler(self, device)
  do_refresh(self, device)
end

local HOPOsmart_handler = {
  NAME = "HOPOsmart Device Handler",
  supported_capabilities = {
    capabilities.refresh
  },
  lifecycle_handlers = {
    added = added_handler
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    attr = {
      [custom_clusters.motor.id] = {
        [custom_clusters.motor.attributes.state_value.id] = state_value_attr_handler
      }
    }
  },
  can_handle = is_zigbee_window_shade,
}

return HOPOsmart_handler
