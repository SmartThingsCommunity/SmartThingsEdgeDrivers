-- Copyright 2024 SmartThings
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

local IASZone = clusters.IASZone
local Basic = clusters.Basic
local OnOff = clusters.OnOff

local configuration = {
  {
    cluster = IASZone.ID,
    attribute = IASZone.attributes.ZoneStatus.ID,
    minimum_interval = 0,
    maximum_interval = 3600,
    data_type = IASZone.attributes.ZoneStatus.base_type,
    reportable_change = 1
  },
  {
    cluster = Basic.ID,
    attribute = Basic.attributes.PowerSource.ID,
    minimum_interval = 30,
    maximum_interval = 21600,
    data_type = Basic.attributes.PowerSource.base_type,
  },
  {
    cluster = OnOff.ID,
    attribute = OnOff.attributes.OnOff.ID,
    minimum_interval = 0,
    maximum_interval = 600,
    data_type = OnOff.attributes.OnOff.base_type
  }
}

local function ias_zone_status_attr_handler(driver, device, zone_status, zb_rx)
  -- this is cribbed from the DTH
  if zone_status:is_battery_low_set() then
    device:emit_event(capabilities.battery.battery(5))
  else
    device:emit_event(capabilities.battery.battery(50))
  end
end

local function device_init(driver, device)
  for _, attribute in ipairs(configuration) do
    device:add_configured_attribute(attribute)
    device:add_monitored_attribute(attribute)
  end
end

local ezex_valve = {
  NAME = "Ezex Valve",
  zigbee_handlers = {
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      },
    }
  },
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "E253-KR0B0ZX-HA" and not device:supports_server_cluster(clusters.PowerConfiguration.ID)
  end
}

return ezex_valve
