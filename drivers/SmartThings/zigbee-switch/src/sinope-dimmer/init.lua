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
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local zcl_clusters = require "st.zigbee.zcl.clusters"
local Basic = zcl_clusters.Basic
local Level = zcl_clusters.Level
local OnOff = zcl_clusters.OnOff

local SINOPE_DIMMER_CLUSTER = 0xFF01
local SINOPE_MAX_INTENSITY_ON_ATTRIBUTE = 0x0052
local SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE = 0x0053
local SINOPE_MIN_LIGHT_INTENSITY_ATTRIBUTE = 0x0055
local VERSION_MIN = 106
-- Constants
local SWBUILD = "swBuild"

local timingTable = {
  [1]  = 100,
  [2]  = 250,
  [3]  = 500,
  [4]  = 750,
  [5]  = 1000,
  [6]  = 1250,
  [7]  = 1500,
  [8]  = 1750,
  [9]  = 2000,
  [10] = 2250
}

local function info_changed(driver, device, event, args)
  -- handle minimalIntensity preference setting, only if swBuild is > 106
  if(device:get_field(SWBUILD) ~= nil and device:get_field(SWBUILD) > VERSION_MIN) then
    local timeValue = 600
    if (args.old_st_store.preferences.minimalIntensity ~= device.preferences.minimalIntensity) then
      timeValue = timingTable[device.preferences.minimalIntensity] and timingTable[device.preferences.minimalIntensity] or 600
    end

    device:send(cluster_base.write_attribute(device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MIN_LIGHT_INTENSITY_ATTRIBUTE),
                data_types.validate_or_build_type(timeValue, data_types.Uint16, "payload")))

  end

  -- handle ledIntensity preference setting
  if (args.old_st_store.preferences.ledIntensity ~= device.preferences.ledIntensity) then
    local ledIntensity = device.preferences.ledIntensity

    device:send(cluster_base.write_attribute(device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_ON_ATTRIBUTE),
                data_types.validate_or_build_type(ledIntensity, data_types.Uint8, "payload")))
    device:send(cluster_base.write_attribute(device,
                data_types.ClusterId(SINOPE_DIMMER_CLUSTER),
                data_types.AttributeId(SINOPE_MAX_INTENSITY_OFF_ATTRIBUTE),
                data_types.validate_or_build_type(ledIntensity, data_types.Uint8, "payload")))
  end
end

local do_refresh = function(self, device)
  local attributes = {
    OnOff.attributes.OnOff,
    Level.attributes.CurrentLevel,
    Basic.attributes.ApplicationVersion
  }
  for _, attribute in pairs(attributes) do
    device:send(attribute:read(device))
  end
end

local application_version_handler = function(driver, device, swBuild)
  device:set_field(SWBUILD, swBuild.value, {persist = true})
end

local zigbee_sinope_dimmer = {
  NAME = "Zigbee Sinope Dimmer",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh,
    }
  },
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [Basic.attributes.ApplicationVersion.ID] = application_version_handler
      }
    }
  },
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  can_handle = function(opts, driver, device, ...)
    local can_handle = device:get_manufacturer() == "Sinope Technologies" and device:get_model() == "DM2500ZB"
    if can_handle then
      local subdriver = require("sinope-dimmer")
      return true, subdriver
    else
      return false
    end
  end
}

return zigbee_sinope_dimmer
