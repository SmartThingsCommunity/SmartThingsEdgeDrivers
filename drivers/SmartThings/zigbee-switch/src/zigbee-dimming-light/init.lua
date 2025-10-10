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

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local configurations = require "configurations"
local switch_utils = require "switch_utils"

local OnOff = clusters.OnOff
local Level = clusters.Level

local DIMMING_LIGHT_CONFIGURATION = {
  {
    cluster = OnOff.ID,
    attribute = OnOff.attributes.OnOff.ID,
    minimum_interval = 0,
    maximum_interval = 300,
    data_type = OnOff.attributes.OnOff.base_type,
    reportable_change = 1

  },
  {
    cluster = Level.ID,
    attribute = Level.attributes.CurrentLevel.ID,
    minimum_interval = 0,
    maximum_interval = 300,
    data_type = Level.attributes.CurrentLevel.base_type,
    reportable_change = 1

  }
}

local function do_configure(driver, device)
  device:refresh()
  device:configure()
end

local function device_init(driver, device)
  for _,attribute in ipairs(DIMMING_LIGHT_CONFIGURATION) do
    device:add_configured_attribute(attribute)
  end
end

local function device_added(driver, device)
  switch_utils.emit_event_if_latest_state_missing(device, "main", capabilities.switchLevel, capabilities.switchLevel.level.NAME, capabilities.switchLevel.level(100))
end

local zigbee_dimming_light = {
  NAME = "Zigbee Dimming Light",
  lifecycle_handlers = {
    init = configurations.power_reconfig_wrapper(device_init),
    added = device_added,
    doConfigure = do_configure
  },
  sub_drivers = require("zigbee-dimming-light.sub_drivers"),
  can_handle = require("zigbee-dimming-light.can_handle"),
}

return zigbee_dimming_light
