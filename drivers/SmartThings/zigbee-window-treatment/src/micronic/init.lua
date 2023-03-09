-- Copyright 2022 SmartThings
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
local zcl_clusters = require "st.zigbee.zcl.clusters"
local WindowCovering = zcl_clusters.WindowCovering
local cluster_base = require "st.zigbee.cluster_base"
local utils = require "st.utils"
local data_types = require "st.zigbee.data_types"

local INVERT_CLUSTER = 0xFC00
local INVERT_CLUSTER_ATTRIBUTE = 0x0000

local micronic_window_shade_FINGERPRINTS = {{
  mfr = "micronic-ko",
  model = "acm301"
}}

local is_micronic_window_shade = function(opts, driver, device)
  for _, fingerprint in ipairs(micronic_window_shade_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function invert_preference_handler(device)
  -- if invert is false then normal case handler or reverse case handler
  local invert_value = device.preferences.reverse
  local invert_cluster_cmd = cluster_base.write_manufacturer_specific_attribute(device, INVERT_CLUSTER,
      INVERT_CLUSTER_ATTRIBUTE, 0x0000, data_types.Boolean, invert_value)
  device:send(invert_cluster_cmd)
end

local function info_changed(driver, device, event, args)
  if device.preferences ~= nil and device.preferences.reverse ~= args.old_st_store.preferences.reverse then
    invert_preference_handler(device)
  end
end

local set_window_shade_level = function(level)
  return function(driver, device, cmd)
    device:send_to_component(cmd.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
  end
end

local function current_position_attr_handler(driver, device, value, zb_rx)

  local level = value.value
  local windowShade = capabilities.windowShade.windowShade
  if level == 0 then
    device:emit_event(windowShade.closed())
  elseif level == 100 then
    device:emit_event(windowShade.open())
  else
      device:emit_event(windowShade.partially_open())
  end
end

local do_refresh = function(self, device)
  device:send(WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
  local invert_cluster_read = cluster_base.read_manufacturer_specific_attribute(device, INVERT_CLUSTER,
      INVERT_CLUSTER_ATTRIBUTE, 0x0000)
  device:send(invert_cluster_read)
end

local micronic_window_shade = {
  NAME = "micronic window shade",
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = set_window_shade_level(100),
      [capabilities.windowShade.commands.close.NAME] = set_window_shade_level(0)
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  can_handle = is_micronic_window_shade
}

return micronic_window_shade
