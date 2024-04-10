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

local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local SINOPE_SWITCH_CLUSTER = 0xFF01
local SINOPE_MAX_INTENSITY_ON_ATTRIBUTE = 0x0052
local SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE = 0x0053

local function info_changed(driver, device, event, args)
  -- handle ledIntensity preference setting
  if (args.old_st_store.preferences.ledIntensity ~= device.preferences.ledIntensity) then
    local ledIntensity = device.preferences.ledIntensity

    device:send(cluster_base.write_attribute(device,
                data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(ledIntensity, data_types.Uint8, "payload")))
    device:send(cluster_base.write_attribute(device,
                data_types.ClusterId(SINOPE_SWITCH_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(ledIntensity, data_types.Uint8, "payload")))

  end
end

local zigbee_sinope_switch = {
  NAME = "Zigbee Sinope switch",
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  can_handle = function(opts, driver, device, ...)
    local can_handle = device:get_manufacturer() == "Sinope Technologies" and device:get_model() == "SW2500ZB"
    if can_handle then
      local subdriver = require("sinope")
      return true, subdriver
    else
      return false
    end
  end
}

return zigbee_sinope_switch
